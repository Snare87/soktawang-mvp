// Firebase Functions v2 API 및 로거, Admin SDK 모듈 가져오기
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler"; // <--- 이 줄 추가!
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// --- 함수 전역 설정 ---
// 모든 함수에 적용될 기본 리전을 설정합니다.
// 이렇게 하면 개별 함수마다 .region()을 붙이지 않아도 됩니다.
setGlobalOptions({ region: "asia-southeast1" });

// Firebase Admin SDK 초기화
// databaseURL을 명시적으로 지정하여 RTDB 리전을 함수 리전과 일치시킵니다.
admin.initializeApp({
  databaseURL: "https://soktawang-mvp-app-2025-4b0ca-default-rtdb.asia-southeast1.firebasedatabase.app"
});

// 클라이언트에서 전달될 데이터의 타입을 정의하는 인터페이스
interface ScoreSubmitData {
  score: number;
  wpm: number;
  accuracy: number;
  sentenceId: string;
  roundId: string; // 라운드 ID 필드 추가
}

/**
 * Processes score submission (Firebase Functions v2 Style)
 * - Initializes Admin SDK with specific RTDB URL.
 * - Deploys to "asia-southeast1" region.
 * - Validates data and authentication.
 * - Creates user doc if not exists, then updates points in Firestore using a transaction.
 * - Writes score to Realtime Database for ranking.
 */
export const scoreSubmit = onCall(
  // request 파라미터에 ScoreSubmitData 인터페이스 적용
  async (request: CallableRequest<ScoreSubmitData>) => {
    logger.info("scoreSubmit function triggered (v2, region: asia-southeast1)", {
      structuredData: true,
    });

    // 1. 데이터 및 인증 정보 가져오기
    const data = request.data; // v2에서는 request.data로 클라이언트 데이터 접근
    const score = data.score;
    const wpm = data.wpm;
    const accuracy = data.accuracy;
    const sentenceId = data.sentenceId;
    const roundId = data.roundId;
    const uid = request.auth?.uid; // v2에서는 request.auth로 사용자 인증 정보 접근

    logger.info("Received data:", { data });

    // 2. 인증 확인
    if (!uid) {
      logger.error("User is not authenticated.");
      throw new HttpsError( // v2에서 import된 HttpsError 사용
        "unauthenticated",
        "User must be authenticated to submit score."
      );
    }
    logger.info(`Processing score for authenticated user: ${uid}`);

    // 3. 데이터 유효성 검사
    if (
      typeof score !== "number" ||
      typeof wpm !== "number" ||
      typeof accuracy !== "number" ||
      typeof sentenceId !== "string" ||
      typeof roundId !== "string" || roundId.length === 0
    ) {
      logger.error("Invalid data types received or missing roundId:", data);
      throw new HttpsError(
        "invalid-argument",
        "Required data missing, invalid type, or empty roundId."
      );
    }

    // 4. 포인트 계산
    const pointsEarned = Math.floor(score / 5); // 예시 로직
    logger.info(`Calculated points to award: ${pointsEarned}`);

    // 5. Firestore 트랜잭션 (사용자 포인트 업데이트 및 닉네임 가져오기)
    const userRef = admin.firestore().collection("users").doc(uid);
    let userNick = `User_${uid.substring(0, 6)}`; // 기본 닉네임

    try {
      await admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          logger.info(`User document for ${uid} not found. Creating new document.`);
          transaction.set(userRef, {
            coins: pointsEarned,
            nick: userNick,
            tier: "bronze",
            freePlaysLeft: 9, // 예시 기본값
            lastActive: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          const userData = userDoc.data();
          userNick = userData?.nick ?? userNick;
          const currentCoins = userData?.coins ?? 0;
          const newCoins = currentCoins + pointsEarned;
          logger.info(
            `Updating coins for user ${uid}: ${currentCoins} -> ${newCoins}`
          );
          transaction.update(userRef, {
            coins: newCoins,
            nick: userNick,
            lastActive: admin.firestore.FieldValue.serverTimestamp(),
           });
        }
      });
      logger.info(`Firestore transaction successful for user ${uid}. Nick: ${userNick}`);

      // 6. RTDB 랭킹 기록
      logger.info(`Attempting to update RTDB ranking for round ${roundId}`);
      const rtdbRef = admin.database().ref(`/liveRank/${roundId}/${uid}`);
      await rtdbRef.set({
         score: score,
         nick: userNick,
         ts: admin.database.ServerValue.TIMESTAMP,
      });
      logger.info(`RTDB ranking update successful for user ${uid} in round ${roundId}.`);

      // 7. 성공 응답 반환
      const successMessage =
        `Score ${score} processed. Awarded ${pointsEarned} points to user ${uid}. Ranking updated.`;
      return {
        status: "success",
        message: successMessage,
        pointsAwarded: pointsEarned,
      };

    } catch (error) {
      logger.error(`Transaction or RTDB update failed for user ${uid}:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Failed to process score due to an internal error."
      );
    }
  } // async 함수의 끝
); // onCall의 끝

// --- ✅ NEW: 하루 144개 라운드 일괄 생성 (23:00 KST) ---
export const roundBatchCreator = onSchedule(
  {
    schedule: "0 23 * * *",          // 매일 23:00
    timeZone: "Asia/Seoul",
    memory: "128MiB",
  },
  async () => {
    const db = admin.firestore();

    // 1) 내일 00:00 기준 타임스탬프
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(0, 0, 0, 0); // 00:00:00.000

    // --- 문장 144개 확보 (부족하면 순환 재사용) ---
const snap = await db.collection("sentences")
                     .orderBy("__name__")   // random 필드 없어도 OK
                     .limit(144)
                     .get();

if (snap.empty) {
  logger.error("❌ No sentences in collection — aborting round creation.");
  return;                       // 문장이 0개면 그냥 중단
}

// snap.docs.length == 10  →  base 배열 크기 = 10
const base = snap.docs.map(d => d.id);   // ['id1', … 'id10']

// 144칸짜리 배열에 0~9를 반복 삽입
const sentences: string[] = [];
for (let i = 0; i < 144; i++) {
  sentences.push(base[i % base.length]);
}

    // 3) 배치 작성
    const batch = db.batch();
    for (let i = 0; i < 144; i++) {
      const startMillis     = tomorrow.getTime() + i * 10 * 60 * 1000; // 00:00, 00:10, ...
      const startAt         = admin.firestore.Timestamp.fromMillis(startMillis);
      const notifyAt        = admin.firestore.Timestamp.fromMillis(startMillis + 60_000);   // +1m
      const entryCloseAt    = admin.firestore.Timestamp.fromMillis(startMillis + 120_000);  // +2m
      const submitCloseAt   = admin.firestore.Timestamp.fromMillis(startMillis + 600_000);  // +10m
      const roundId         = `R${startMillis}`;  // 예: R1715404800000
      const expireAt      = admin.firestore.Timestamp.fromMillis(
                          startMillis + 30 * 24 * 60 * 60 * 1000  // +30일
                        );

      batch.set(db.doc(`rounds/${roundId}`), {
        roundId,
        sentenceId: sentences[i % sentences.length],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        startAt,
        notifyAt,
        entryCloseAt,
        submitCloseAt,
        expireAt,
        status: "scheduled",
        participantCount: 0,
      });
    }

    await batch.commit();
    logger.info(`✅ Created 144 rounds for ${tomorrow.toISOString().slice(0,10)}`);
  }
);




// 다른 함수들이 있다면 여기에 추가...

// 파일 끝 (ESLint eol-last 규칙을 위해 필요할 수 있음)
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

// --- 새로운 roundTrigger 함수 정의 시작 ---

/**
 * 주기적으로 실행되어 새 게임 라운드를 생성하는 함수 (Scheduled Function)
 * 예: 매 10분마다 실행
 */
export const roundTrigger = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Seoul",
    // V2 함수 옵션들 추가 가능 (예: memory, timeoutSeconds 등)
    // memory: "256MiB",
    // timeoutSeconds: 60,
  },
  async (event) => { // event 파라미터 사용
    logger.info("roundTrigger function triggered by scheduler (v2)", {
      timestamp: event.scheduleTime, // V2에서는 event.scheduleTime
    });

    try {
      const db = admin.firestore();
      const newRoundId = db.collection("rounds").doc().id;
      const now = admin.firestore.Timestamp.now();
      const startTime = admin.firestore.Timestamp.fromMillis(
        now.toMillis() + 2 * 60 * 1000
      ); // 2분 후
      const sampleSentenceId = "s_placeholder_123";

      const newRoundData = {
        roundId: newRoundId,
        createdAt: now,
        startAt: startTime,
        status: "pending",
        sentenceId: sampleSentenceId,
        participantCount: 0,
      };

      await db.collection("rounds").doc(newRoundId).set(newRoundData);
      logger.info(`New round created successfully (v2): ${newRoundId}`, {
        data: newRoundData,
      });
      // 명시적으로 아무것도 반환하지 않거나 return; 사용
      // V2 onSchedule 핸들러는 Promise<void> 또는 void를 반환해야 함
      return; // <--- 수정: return null; 대신 return; 또는 아무것도 반환 안 함
    } catch (error) {
      logger.error("Error creating new round (v2):", error);
      // 오류 발생 시에도 명시적으로 아무것도 반환하지 않음
      return; // <--- 수정: return null; 대신 return; 또는 아무것도 반환 안 함
    }
  }
); // onSchedule 끝

// 다른 함수들이 있다면 여기에 추가...

// 파일 끝 (ESLint eol-last 규칙을 위해 필요할 수 있음)
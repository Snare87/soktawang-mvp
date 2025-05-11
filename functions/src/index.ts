// Firebase Functions v2 API 및 로거, Admin SDK 모듈 가져오기
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// --- 함수 전역 설정 ---
setGlobalOptions({ region: "asia-southeast1" });

// Firebase Admin SDK 초기화
admin.initializeApp({
  databaseURL: "https://soktawang-mvp-app-2025-4b0ca-default-rtdb.asia-southeast1.firebasedatabase.app"
});

// 클라이언트에서 전달될 데이터의 타입 정의
interface ScoreSubmitData {
  score: number;
  wpm: number;
  accuracy: number;
  sentenceId: string;
  roundId: string;
}

// --- 점수 제출 함수 ---
export const scoreSubmit = onCall(
  async (request: CallableRequest<ScoreSubmitData>) => {
    logger.info("scoreSubmit function triggered (v2, region: asia-southeast1)", { structuredData: true });

    const { score, wpm, accuracy, sentenceId, roundId } = request.data;
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "User must be authenticated to submit score.");
    }

    if (typeof score !== "number" || typeof wpm !== "number" || typeof accuracy !== "number"
        || typeof sentenceId !== "string" || typeof roundId !== "string" || !roundId) {
      throw new HttpsError("invalid-argument", "Required data missing, invalid type, or empty roundId.");
    }

    const pointsEarned = Math.floor(score / 5);
    const userRef = admin.firestore().collection("users").doc(uid);
    let userNick = `User_${uid.substring(0,6)}`;

    try {
      await admin.firestore().runTransaction(async (tx) => {
        const userDoc = await tx.get(userRef);
        if (!userDoc.exists) {
          tx.set(userRef, { coins: pointsEarned, nick: userNick, tier: "bronze", freePlaysLeft: 9, lastActive: admin.firestore.FieldValue.serverTimestamp() });
        } else {
          const data = userDoc.data()!;
          userNick = data.nick || userNick;
          tx.update(userRef, { coins: (data.coins || 0) + pointsEarned, nick: userNick, lastActive: admin.firestore.FieldValue.serverTimestamp() });
        }
      });

      const rtdbRef = admin.database().ref(`/liveRank/${roundId}/${uid}`);
      await rtdbRef.set({ score, nick: userNick, ts: admin.database.ServerValue.TIMESTAMP });

      return { status: "success", message: `Score ${score} processed. Awarded ${pointsEarned} points.`, pointsAwarded: pointsEarned };
    } catch (e) {
      logger.error(`Error processing score:`, e);
      if (e instanceof HttpsError) throw e;
      throw new HttpsError("internal", "Failed to process score due to an internal error.");
    }
  }
);

// --- 144개 라운드 일괄 생성 (23:00 KST) ---
export const roundBatchCreator = onSchedule(
  { schedule: '0 14 * * *', timeZone: 'Asia/Seoul' },
  async () => {
    const db = admin.firestore();

    // 1) 내일 한국 시간 자정(Date) 생성
    const kstNowStr = new Date().toLocaleString('en-US', { timeZone: 'Asia/Seoul' });
    const localDatePart = kstNowStr.split(',')[0];             // "M/D/YYYY"
    const midnightStr = `${localDatePart} 00:00:00 GMT+0900`;
    const seoulMidnight = new Date(midnightStr);
    // ▶ 오늘 자정 KST 기준
    logger.info(`▶ Today midnight KST: ${seoulMidnight.toISOString()}`);

    // ▶ 내일 자정으로 오프셋
    const tomorrowMidnight = new Date(seoulMidnight);
    tomorrowMidnight.setDate(seoulMidnight.getDate() + 1);
    logger.info(`▶ Tomorrow midnight KST: ${tomorrowMidnight.toISOString()}`);

    // 2) 문장 144개 로드 (부족 시 순환 재사용)
    const sentSnap = await db.collection('sentences').orderBy('__name__').limit(144).get();
    if (sentSnap.empty) {
      logger.error('❌ No sentences in collection — aborting round creation.');
      return;
    }
    const baseIds = sentSnap.docs.map(d => d.id);
    const sentences: string[] = Array.from({ length: 144 }, (_, i) => baseIds[i % baseIds.length]);

    // 3) 배치 작성
    const batch = db.batch();
    for (let i = 0; i < 144; i++) {
      const startMs = tomorrowMidnight.getTime() + i * 10 * 60 * 1000;
      const startAt = admin.firestore.Timestamp.fromMillis(startMs);
      const notifyAt = admin.firestore.Timestamp.fromMillis(startMs + 60_000);
      const entryCloseAt = admin.firestore.Timestamp.fromMillis(startMs + 120_000);
      const submitCloseAt = admin.firestore.Timestamp.fromMillis(startMs + 600_000);
      const expireAt = admin.firestore.Timestamp.fromMillis(startMs + 30 * 24 * 60 * 60 * 1000);
      const roundId = `R${startMs}`;

      batch.set(db.doc(`rounds/${roundId}`), {
        roundId,
        sentenceId: sentences[i],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        startAt,
        notifyAt,
        entryCloseAt,
        submitCloseAt,
        expireAt,
        status: 'scheduled',
        participantCount: 0,
      });
    }
    await batch.commit();
    logger.info(`✅ Created 144 rounds for ${(tomorrowMidnight.toISOString().slice(0,10))}`);
  }
);

// 다른 함수 추가 가능...

// functions/seedSentences.js
/**
 * Flutter의 sentences.dart 내용을 읽어
 * Firestore  ↳ sentences 컬렉션으로 한꺼번에 업로드
 */

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

// 1) Firebase Admin 초기화 (functions 디렉터리엔 이미 node_modules/firebase-admin 존재)
admin.initializeApp({
  credential: admin.credential.cert('C:/keys/soktawang-mvp-app-2025-4b0ca-7ea8652e6291.json'),
  projectId: 'soktawang-mvp-app-2025-4b0ca'
});




const db = admin.firestore();  
// 2) sentences.dart 경로 (필요 시 수정)
const dartPath = path.join(__dirname, "../Client/lib/data/sentences.dart");
const dartFile = fs.readFileSync(dartPath, "utf8");

// 3) 따옴표 안 문자열 모두 추출
const matches = [...dartFile.matchAll(/["'`]([^"'`]+)["'`]/g)];
const sentences = matches.map((m) => m[1]);

if (!sentences.length) {
  console.error("❌ sentences.dart에서 문장을 찾지 못했습니다.");
  process.exit(1);
}

console.log(`📄 ${sentences.length}개 문장 업로드…`);

const batch = db.batch();
sentences.forEach((txt) => {
  const ref = db.collection("sentences").doc();      // 자동 ID
  batch.set(ref, { text: txt, random: Math.random() });
});

batch
  .commit()
  .then(() => {
    console.log("✅ 업로드 완료");
    process.exit(0);
  })
  .catch((err) => {
    console.error("🔥 Firestore 업로드 실패:", err);
    process.exit(1);
  });

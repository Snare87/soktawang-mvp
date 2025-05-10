// tools/seedSentences.ts
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

// 🔑 1) Firebase Admin 초기화 -----------------------------
admin.initializeApp();             // (default) 프로젝트 인증 사용
const db = admin.firestore();

// 🔍 2) Flutter sentences.dart 읽어서 문장 배열 추출 --------
const dartPath = path.join(__dirname, "../Client/lib/data/sentences.dart");
const dartFile = fs.readFileSync(dartPath, "utf8");

// 정규식: 큰따옴표 "…" 또는 작은따옴표 '…' 안에 있는 문장만 매칭
const matches = Array.from(dartFile.matchAll(/["']([^"']+)["']/g));
const sentences = matches.map(m => m[1]);

if (sentences.length === 0) {
  console.error("❌ sentences.dart에서 문장을 하나도 찾지 못했습니다.");
  process.exit(1);
}

console.log(`📄 추출한 문장 ${sentences.length}개, Firestore에 업로드 시작…`);

// 📝 3) Firestore batch 작성 ------------------------------
const batch = db.batch();
sentences.forEach(txt => {
  const docRef = db.collection("sentences").doc();   // 자동 ID
  batch.set(docRef, {
    text: txt,
    random: Math.random()         // 0~1 난수
  });
});

// 4) 커밋 -------------------------------------------------
batch.commit()
  .then(() => {
    console.log(`✅ 업로드 완료 (${sentences.length}개)`);
    process.exit(0);
  })
  .catch(err => {
    console.error("🔥 Firestore 업로드 실패:", err);
    process.exit(1);
  });

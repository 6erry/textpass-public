const crypto = require("crypto");
const path = require("path");
const admin = require("../textappkey/node_modules/firebase-admin");

const DEFAULT_UNIVERSITY_ID = "hokudai.ac.jp";
const BATCH_SIZE = 450;

function cleanText(value) {
  return String(value || "").replace(/\u3000/g, " ").replace(/\s+/g, " ").trim();
}

function parseTitle(value) {
  const lines = String(value || "")
    .split("\n")
    .map(cleanText)
    .filter(Boolean);
  if (!lines.length) return "";
  const courseName = lines[0];
  const themeName = lines[1] && /[\u3040-\u30ff\u3400-\u9fff]/.test(lines[1]) ? lines[1] : "";
  return themeName ? `${courseName} (${themeName})` : courseName;
}

function parseTeacher(value) {
  const firstLine = cleanText(String(value || "").split("\n")[0]);
  return cleanText(firstLine.replace(/\(.*?\)|（.*?）/g, ""));
}

function normalizePart(value) {
  return cleanText(value)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[‐-―ー－]/g, "-")
    .replace(/[【】「」『』]/g, "");
}

function buildClassKey(title, teacher, universityId = DEFAULT_UNIVERSITY_ID) {
  const source = [universityId, title, teacher].map(normalizePart).join("|");
  const digest = crypto.createHash("sha1").update(source).digest("hex").slice(0, 20);
  const prefix = normalizePart(universityId).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return `${prefix}_${digest}`;
}

function parseArgs(argv) {
  const args = {
    serviceAccount: "scripts/serviceAccountKey.json",
    universityId: DEFAULT_UNIVERSITY_ID,
    dryRun: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--service-account") args.serviceAccount = argv[++i];
    else if (arg === "--university-id") args.universityId = argv[++i];
  }
  return args;
}

async function backfillCollection(db, collectionName, universityId, dryRun) {
  console.log(`Backfilling ${collectionName}...`);
  const snapshot = await db.collection(collectionName).get();
  let batch = db.batch();
  let pending = 0;
  let updated = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.classKey) continue;

    const title = parseTitle(data.title || data.name || "");
    const teacher = parseTeacher(data.teacher || "");
    if (!title || !teacher) continue;

    const classKey = buildClassKey(title, teacher, universityId);
    updated += 1;
    if (dryRun) {
      if (updated <= 40) {
        console.log(`[dry-run] ${collectionName}/${doc.id}: ${title} / ${teacher} -> ${classKey}`);
      }
      continue;
    }

    batch.update(doc.ref, { classKey, class_key: classKey });
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      console.log(`Updated ${updated} documents...`);
      batch = db.batch();
      pending = 0;
    }
  }

  if (!dryRun && pending) await batch.commit();
  console.log(`${collectionName}: ${updated} documents ${dryRun ? "would be updated" : "updated"}.`);
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccount = require(path.resolve(args.serviceAccount));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  await backfillCollection(db, "syllabus_master", args.universityId, args.dryRun);
  await backfillCollection(db, "class_reviews", args.universityId, args.dryRun);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

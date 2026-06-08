const path = require("path");
const admin = require("../textappkey/node_modules/firebase-admin");

function parseArgs(argv) {
  const args = {
    serviceAccount: "scripts/serviceAccountKey.json",
    dryRun: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--service-account") args.serviceAccount = argv[++i];
    else if (arg === "--dry-run") args.dryRun = true;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccount = require(path.resolve(args.serviceAccount));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();
  const rooms = await db.collection("chat_rooms").get();

  let updated = 0;
  let skipped = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of rooms.docs) {
    const data = doc.data();
    const bookId = data.bookId;
    if (!bookId) {
      skipped += 1;
      continue;
    }
    const bookDoc = await db.collection("books").doc(bookId).get();
    const bookExists = bookDoc.exists;
    if (data.bookExists === bookExists) {
      skipped += 1;
      continue;
    }
    updated += 1;
    if (!args.dryRun) {
      batch.update(doc.ref, { bookExists });
      batchCount += 1;
      if (batchCount >= 450) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }
  }

  if (!args.dryRun && batchCount > 0) await batch.commit();
  console.log(JSON.stringify({ updated, skipped, dryRun: args.dryRun }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

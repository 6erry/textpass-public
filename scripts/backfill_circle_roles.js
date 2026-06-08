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

function buildRoles(circle) {
  const existing = circle.member_roles || {};
  const members = Array.isArray(circle.member_uids) ? circle.member_uids : [];
  const admins = Array.isArray(circle.admin_uids) ? circle.admin_uids : [];
  const roles = {};

  for (const uid of members) roles[uid] = existing[uid] || "member";
  admins.forEach((uid, index) => {
    roles[uid] = existing[uid] || (index === 0 ? "owner" : "admin");
  });

  const hasOwner = Object.values(roles).includes("owner");
  if (!hasOwner && admins.length > 0) roles[admins[0]] = "owner";
  if (!hasOwner && admins.length === 0 && members.length > 0) {
    roles[members[0]] = "owner";
  }

  return roles;
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccount = require(path.resolve(args.serviceAccount));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();
  const snapshot = await db.collection("circles").get();

  let updated = 0;
  let skipped = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const circle = doc.data();
    const roles = buildRoles(circle);
    const adminUids = Object.entries(roles)
      .filter(([, role]) => role === "owner" || role === "admin")
      .map(([uid]) => uid);

    const currentRoles = JSON.stringify(circle.member_roles || {});
    const nextRoles = JSON.stringify(roles);
    const currentAdmins = JSON.stringify(circle.admin_uids || []);
    const nextAdmins = JSON.stringify(adminUids);

    if (currentRoles === nextRoles && currentAdmins === nextAdmins) {
      skipped += 1;
      continue;
    }

    updated += 1;
    if (!args.dryRun) {
      batch.update(doc.ref, {
        member_roles: roles,
        admin_uids: adminUids,
      });
      batch.set(doc.ref.collection("audit_logs").doc(), {
        actor_uid: "script:backfill_circle_roles",
        action: "circle_roles_backfilled",
        target_type: "circle",
        target_id: doc.id,
        changes: { member_roles: roles, admin_uids: adminUids },
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      batchCount += 2;
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

const path = require("path");
const admin = require("../textappkey/node_modules/firebase-admin");

function parseArgs(argv) {
  const args = {
    serviceAccount: "scripts/serviceAccountKey.json",
    email: null,
    circleId: null,
    universityId: "hokudai.ac.jp",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--service-account") args.serviceAccount = argv[++i];
    else if (arg === "--email") args.email = argv[++i];
    else if (arg === "--circle-id") args.circleId = argv[++i];
    else if (arg === "--university-id") args.universityId = argv[++i];
  }

  if (!args.email) throw new Error("--email is required");
  return args;
}

function emailCandidates(email) {
  const candidates = [email.trim().toLowerCase()];
  if (email.includes("ryunouske")) {
    candidates.push(email.replace("ryunouske", "ryunosuke").toLowerCase());
  }
  return [...new Set(candidates)];
}

async function findUserByEmail(email) {
  for (const candidate of emailCandidates(email)) {
    try {
      const user = await admin.auth().getUserByEmail(candidate);
      return { uid: user.uid, email: candidate };
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  }

  const users = await admin.firestore()
    .collection("users")
    .where("email", "in", emailCandidates(email))
    .limit(1)
    .get();
  if (!users.empty) {
    const doc = users.docs[0];
    return { uid: doc.id, email: doc.data().email || email };
  }

  throw new Error(`User not found for email: ${email}`);
}

async function findTargetCircle(args) {
  if (args.circleId) {
    const doc = await admin.firestore().collection("circles").doc(args.circleId).get();
    if (!doc.exists) throw new Error(`Circle not found: ${args.circleId}`);
    return doc;
  }

  const aliases = args.universityId === "hokudai.ac.jp" || args.universityId === "hokudai"
    ? ["hokudai.ac.jp", "hokudai"]
    : [args.universityId];

  for (const universityId of aliases) {
    const snapshot = await admin.firestore()
      .collection("circles")
      .where("universityId", "==", universityId)
      .limit(1)
      .get();
    if (!snapshot.empty) return snapshot.docs[0];
  }

  throw new Error(`No circle found for universityId: ${args.universityId}`);
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccount = require(path.resolve(args.serviceAccount));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

  const db = admin.firestore();
  const targetUser = await findUserByEmail(args.email);
  const circleDoc = await findTargetCircle(args);
  const circleRef = circleDoc.ref;
  const circle = circleDoc.data();

  const memberUids = new Set(circle.member_uids || []);
  memberUids.add(targetUser.uid);

  const roles = { ...(circle.member_roles || {}) };
  for (const [uid, role] of Object.entries(roles)) {
    if (role === "owner") roles[uid] = "admin";
  }
  roles[targetUser.uid] = "owner";

  const adminUids = Object.entries(roles)
    .filter(([, role]) => role === "owner" || role === "admin")
    .map(([uid]) => uid);

  const batch = db.batch();
  batch.update(circleRef, {
    member_uids: [...memberUids],
    member_roles: roles,
    admin_uids: adminUids,
    status: "active",
  });
  batch.set(db.collection("users").doc(targetUser.uid), {
    belonging_circle_id: circleDoc.id,
  }, { merge: true });
  batch.set(circleRef.collection("audit_logs").doc(), {
    actor_uid: "script:set_circle_owner",
    action: "member_role_updated",
    target_type: "member",
    target_id: targetUser.uid,
    changes: {
      email: targetUser.email,
      after: "owner",
      source: "scripts/set_circle_owner.js",
    },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  console.log(JSON.stringify({
    uid: targetUser.uid,
    email: targetUser.email,
    circleId: circleDoc.id,
    circleName: circle.name,
    role: "owner",
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

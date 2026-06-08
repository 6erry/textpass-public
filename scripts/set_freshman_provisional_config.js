const path = require("path");
const admin = require("../textappkey/node_modules/firebase-admin");

function parseArgs(argv) {
  const args = {
    serviceAccount: "scripts/serviceAccountKey.json",
    enabled: null,
    expiresAt: null,
    universityId: "hokudai.ac.jp",
    approvedDomains: ["hokudai.ac.jp"],
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--service-account") args.serviceAccount = argv[++i];
    else if (arg === "--enabled") args.enabled = argv[++i] === "true";
    else if (arg === "--expires-at") args.expiresAt = argv[++i];
    else if (arg === "--university-id") args.universityId = argv[++i];
    else if (arg === "--approved-domains") {
      args.approvedDomains = argv[++i]
        .split(",")
        .map((domain) => domain.trim().toLowerCase())
        .filter(Boolean);
    }
  }

  if (args.enabled === null) {
    throw new Error("--enabled true|false is required");
  }

  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccount = require(path.resolve(args.serviceAccount));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

  const data = {
    freshmanProvisionalEnabled: args.enabled,
    freshmanProvisionalUniversityId: args.universityId,
    approvedDomains: args.approvedDomains,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (args.expiresAt) {
    const date = new Date(args.expiresAt);
    if (Number.isNaN(date.getTime())) {
      throw new Error("--expires-at must be an ISO-8601 datetime");
    }
    data.freshmanProvisionalExpiresAt =
      admin.firestore.Timestamp.fromDate(date);
  } else {
    data.freshmanProvisionalExpiresAt = null;
  }

  await admin.firestore()
    .collection("app_config")
    .doc("registration")
    .set(data, { merge: true });

  console.log("Freshman provisional registration config updated:");
  console.log(JSON.stringify({
    enabled: data.freshmanProvisionalEnabled,
    expiresAt: args.expiresAt,
    universityId: data.freshmanProvisionalUniversityId,
    approvedDomains: data.approvedDomains,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

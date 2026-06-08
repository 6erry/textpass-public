// cspell:ignore OTPS firestore Millis

import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

const OTPS_COLLECTION = "otps";
const APP_CONFIG_COLLECTION = "app_config";
const REGISTRATION_CONFIG_DOC = "registration";
const DEFAULT_UNIVERSITY_ID = "hokudai.ac.jp";
const DEFAULT_APPROVED_DOMAINS = [DEFAULT_UNIVERSITY_ID];
const BUYER_SYSTEM_FEE_JPY = 100;
const SELLER_FEE_RATES: Record<string, number> = {
  book: 0.05,
  academic_supply: 0.08,
  campus_life_beta: 0.08,
};

const normalizeListingType = (value: unknown): string => {
  const listingType = typeof value === "string" ? value : "book";
  return Object.prototype.hasOwnProperty.call(SELLER_FEE_RATES, listingType) ?
    listingType :
    "book";
};

const sellerFeeRateForBook = (book: admin.firestore.DocumentData): number => {
  return SELLER_FEE_RATES[normalizeListingType(book.listingType)] ?? 0.05;
};

const calculateSingleItemFees = (book: admin.firestore.DocumentData) => {
  const itemAmount = Number(book.price);
  const feeRate = sellerFeeRateForBook(book);
  const buyerFee = BUYER_SYSTEM_FEE_JPY;
  const sellerCommission = Math.floor(itemAmount * feeRate);
  return {
    itemAmount,
    feeRate,
    buyerFee,
    sellerCommission,
    totalAmount: itemAmount + buyerFee,
    applicationFeeAmount: buyerFee + sellerCommission,
  };
};

type RegistrationConfig = {
  approvedDomains: string[];
  freshmanProvisionalEnabled: boolean;
  freshmanProvisionalExpiresAt?: admin.firestore.Timestamp;
  freshmanProvisionalUniversityId: string;
};

const readRegistrationConfig = async (): Promise<RegistrationConfig> => {
  const snapshot = await admin.firestore()
    .collection(APP_CONFIG_COLLECTION)
    .doc(REGISTRATION_CONFIG_DOC)
    .get();
  const data = snapshot.data() ?? {};

  const approvedDomains =
    Array.isArray(data.approvedDomains) && data.approvedDomains.length > 0 ?
      data.approvedDomains
        .map((domain) => String(domain).trim().toLowerCase())
        .filter((domain) => domain.length > 0) :
      DEFAULT_APPROVED_DOMAINS;

  const freshmanProvisionalUniversityId =
    typeof data.freshmanProvisionalUniversityId === "string" ?
      data.freshmanProvisionalUniversityId.trim().toLowerCase() :
      DEFAULT_UNIVERSITY_ID;

  return {
    approvedDomains,
    freshmanProvisionalEnabled:
      data.freshmanProvisionalEnabled === true,
    freshmanProvisionalExpiresAt:
      data.freshmanProvisionalExpiresAt as admin.firestore.Timestamp |
        undefined,
    freshmanProvisionalUniversityId,
  };
};

const ensureApprovedUniversityDomain = (
  universityId: string | undefined,
  config: RegistrationConfig,
) => {
  if (!universityId ||
      !config.approvedDomains.includes(universityId.trim().toLowerCase())) {
    throw new HttpsError("invalid-argument", "invalid university domain");
  }
};

const isFutureOrUnset = (
  timestamp: admin.firestore.Timestamp | undefined,
) => !timestamp || timestamp.toMillis() > admin.firestore.Timestamp.now().toMillis();

const allowedContactOrigins = new Set([
  "https://tekipa.net",
  "https://www.tekipa.net",
  "https://your-firebase-project-id.web.app",
  "https://your-firebase-project-id.firebaseapp.com",
  "http://localhost:8791",
  "http://127.0.0.1:8791",
]);

const appFunctionBaseUrl =
  process.env.APP_FUNCTION_BASE_URL ??
  "https://your-region-your-firebase-project-id.cloudfunctions.net";

const contactString = (value: unknown, maxLength: number) => {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, maxLength);
};

export const submitContactForm = onRequest(async (request, response) => {
  const origin = request.get("origin") ?? "";
  if (allowedContactOrigins.has(origin)) {
    response.set("Access-Control-Allow-Origin", origin);
    response.set("Vary", "Origin");
  }
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const body = request.body ?? {};
  if (contactString(body.website, 100)) {
    response.status(200).json({ ok: true });
    return;
  }

  const category = contactString(body.category, 40) || "general";
  const name = contactString(body.name, 80);
  const email = contactString(body.email, 160).toLowerCase();
  const organization = contactString(body.organization, 120);
  const university = contactString(body.university, 120);
  const message = contactString(body.message, 3000);
  const allowedCategories = new Set([
    "general",
    "pr",
    "bug",
    "university",
    "press",
  ]);

  if (!allowedCategories.has(category) ||
      name.length < 1 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      message.length < 10) {
    response.status(400).json({ error: "invalid_payload" });
    return;
  }

  await admin.firestore().collection("contact_submissions").add({
    category,
    name,
    email,
    organization,
    university,
    message,
    status: "open",
    source: "tekipa.net",
    userAgent: contactString(request.get("user-agent"), 500),
    ip: contactString(
      request.get("x-forwarded-for")?.split(",")[0] ?? request.ip,
      80,
    ),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  response.status(200).json({ ok: true });
});

const ROLE_OWNER = "owner";
const ROLE_ADMIN = "admin";
const ROLE_EVENT_MANAGER = "event_manager";
const ROLE_MEMBER = "member";

const roleCanManageCircle = (role: unknown) =>
  role === ROLE_OWNER || role === ROLE_ADMIN;

const roleCanManageEvents = (role: unknown) =>
  roleCanManageCircle(role) || role === ROLE_EVENT_MANAGER;

const memberRolesFromCircle = (
  circle: admin.firestore.DocumentData,
): Record<string, string> => {
  const explicitRoles = circle.member_roles;
  if (explicitRoles && typeof explicitRoles === "object") {
    return { ...explicitRoles } as Record<string, string>;
  }

  const roles: Record<string, string> = {};
  const members = Array.isArray(circle.member_uids) ?
    circle.member_uids as string[] : [];
  const admins = Array.isArray(circle.admin_uids) ?
    circle.admin_uids as string[] : [];
  members.forEach((uid) => {
    roles[uid] = ROLE_MEMBER;
  });
  admins.forEach((uid, index) => {
    roles[uid] = index === 0 ? ROLE_OWNER : ROLE_ADMIN;
  });
  return roles;
};

const assertCircleExists = (
  snapshot: admin.firestore.DocumentSnapshot,
) => {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "circle not found");
  }
};

const assertCanManageCircle = (
  circle: admin.firestore.DocumentData,
  uid: string,
) => {
  const role = memberRolesFromCircle(circle)[uid];
  if (!roleCanManageCircle(role)) {
    throw new HttpsError("permission-denied", "circle management permission required");
  }
};

const assertCanManageEvents = (
  circle: admin.firestore.DocumentData,
  uid: string,
) => {
  if (circle.status !== "active") {
    throw new HttpsError("failed-precondition", "circle is not active");
  }
  const role = memberRolesFromCircle(circle)[uid];
  if (!roleCanManageEvents(role)) {
    throw new HttpsError("permission-denied", "event management permission required");
  }
};

const auditLogData = (
  actorUid: string,
  action: string,
  targetType: string,
  targetId: string | null,
  changes: Record<string, unknown>,
) => ({
  actor_uid: actorUid,
  action,
  target_type: targetType,
  target_id: targetId,
  changes,
  created_at: admin.firestore.FieldValue.serverTimestamp(),
});

export const joinCircleByInviteCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  const inviteCode = (request.data?.inviteCode as string | undefined)
    ?.trim()
    .toUpperCase();
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!inviteCode) {
    throw new HttpsError("invalid-argument", "inviteCode is required");
  }

  const db = admin.firestore();
  const query = await db.collection("circles")
    .where("invite_code", "==", inviteCode)
    .limit(1)
    .get();
  if (query.empty) {
    throw new HttpsError("not-found", "circle not found");
  }

  const circleRef = query.docs[0].ref;
  await db.runTransaction(async (transaction) => {
    const circleDoc = await transaction.get(circleRef);
    assertCircleExists(circleDoc);
    const circle = circleDoc.data() ?? {};
    const memberUids = new Set<string>(circle.member_uids ?? []);
    const roles = memberRolesFromCircle(circle);

    if (!memberUids.has(uid)) {
      memberUids.add(uid);
      roles[uid] = ROLE_MEMBER;
    }

    const status = memberUids.size >= 3 ? "active" : circle.status;
    transaction.update(circleRef, {
      member_uids: [...memberUids],
      member_roles: roles,
      status,
    });
    transaction.set(db.collection("users").doc(uid), {
      belonging_circle_id: circleRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(circleRef.collection("audit_logs").doc(), auditLogData(
      uid,
      "member_joined",
      "member",
      uid,
      { role: ROLE_MEMBER },
    ));
  });

  return { success: true, circleId: circleRef.id };
});

export const updateCircleMemberRole = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const memberUid = (request.data?.memberUid as string | undefined)?.trim();
  const role = (request.data?.role as string | undefined)?.trim();
  const allowedRoles = [ROLE_OWNER, ROLE_ADMIN, ROLE_EVENT_MANAGER, ROLE_MEMBER];
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId || !memberUid || !role || !allowedRoles.includes(role)) {
    throw new HttpsError("invalid-argument", "invalid role update payload");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  await db.runTransaction(async (transaction) => {
    const circleDoc = await transaction.get(circleRef);
    assertCircleExists(circleDoc);
    const circle = circleDoc.data() ?? {};
    const roles = memberRolesFromCircle(circle);
    const actorRole = roles[uid];
    if (actorRole !== ROLE_OWNER) {
      throw new HttpsError("permission-denied", "owner permission required");
    }
    const memberUids = new Set<string>(circle.member_uids ?? []);
    if (!memberUids.has(memberUid)) {
      throw new HttpsError("failed-precondition", "target is not a member");
    }
    const beforeRole = roles[memberUid] ?? ROLE_MEMBER;

    if (role === ROLE_OWNER) {
      Object.entries(roles).forEach(([entryUid, entryRole]) => {
        if (entryRole === ROLE_OWNER) roles[entryUid] = ROLE_ADMIN;
      });
    }
    roles[memberUid] = role;

    const adminUids = Object.entries(roles)
      .filter(([, entryRole]) => roleCanManageCircle(entryRole))
      .map(([entryUid]) => entryUid);
    if (adminUids.length === 0) {
      throw new HttpsError("failed-precondition", "at least one admin required");
    }

    transaction.update(circleRef, {
      member_roles: roles,
      admin_uids: adminUids,
    });
    transaction.set(circleRef.collection("audit_logs").doc(), auditLogData(
      uid,
      "member_role_updated",
      "member",
      memberUid,
      { before: beforeRole, after: role },
    ));
  });

  return { success: true };
});

const sanitizeEventInput = (
  raw: Record<string, unknown>,
) => {
  const title = String(raw.title ?? "").trim();
  const location = String(raw.location ?? "").trim();
  const category = String(raw.category ?? "other").trim();
  const description = String(raw.description ?? "");
  const imageUrl = raw.imageUrl === null || raw.imageUrl === undefined ?
    null : String(raw.imageUrl);
  const isDraft = raw.isDraft === true;
  const tags = Array.isArray(raw.tags) ?
    raw.tags.map((tag) => String(tag).trim()).filter(Boolean) : [];
  const startAtMillis = Number(raw.startAtMillis);
  if (!title || !location || !Number.isFinite(startAtMillis)) {
    throw new HttpsError("invalid-argument", "invalid event payload");
  }
  return {
    title,
    location,
    category,
    description,
    image_url: imageUrl,
    is_draft: isDraft,
    tags,
    start_at: admin.firestore.Timestamp.fromMillis(startAtMillis),
  };
};

export const createCircleEvents = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const rawEvents = request.data?.events as Record<string, unknown>[] | undefined;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId || !Array.isArray(rawEvents) ||
      rawEvents.length === 0 || rawEvents.length > 30) {
    throw new HttpsError("invalid-argument", "invalid events payload");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  const circleDoc = await circleRef.get();
  assertCircleExists(circleDoc);
  const circle = circleDoc.data() ?? {};
  assertCanManageEvents(circle, uid);

  const userDoc = await db.collection("users").doc(uid).get();
  const universityId = userDoc.data()?.universityId ?? circle.universityId ?? DEFAULT_UNIVERSITY_ID;
  const batch = db.batch();
  const ids: string[] = [];
  rawEvents.forEach((rawEvent) => {
    const eventRef = db.collection("events").doc();
    const eventData = sanitizeEventInput(rawEvent);
    ids.push(eventRef.id);
    batch.set(eventRef, {
      ...eventData,
      circle_id: circleId,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      created_by: uid,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: uid,
      like_count: 0,
      universityId,
    });
    batch.set(circleRef.collection("audit_logs").doc(), auditLogData(
      uid,
      "event_created",
      "event",
      eventRef.id,
      { title: eventData.title, is_draft: eventData.is_draft },
    ));
  });
  await batch.commit();
  return { success: true, eventIds: ids };
});

export const updateCircleEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const eventId = (request.data?.eventId as string | undefined)?.trim();
  const rawEvent = request.data?.event as Record<string, unknown> | undefined;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId || !eventId || !rawEvent) {
    throw new HttpsError("invalid-argument", "invalid event update payload");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  const eventRef = db.collection("events").doc(eventId);
  const [circleDoc, eventDoc] = await Promise.all([circleRef.get(), eventRef.get()]);
  assertCircleExists(circleDoc);
  if (!eventDoc.exists || eventDoc.data()?.circle_id !== circleId) {
    throw new HttpsError("not-found", "event not found");
  }
  const circle = circleDoc.data() ?? {};
  assertCanManageEvents(circle, uid);
  const eventData = sanitizeEventInput(rawEvent);
  const before = eventDoc.data() ?? {};

  const batch = db.batch();
  batch.update(eventRef, {
    ...eventData,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_by: uid,
  });
  batch.set(circleRef.collection("audit_logs").doc(), auditLogData(
    uid,
    "event_updated",
    "event",
    eventId,
    {
      before_title: before.title ?? null,
      after_title: eventData.title,
      is_draft: eventData.is_draft,
    },
  ));
  await batch.commit();
  return { success: true };
});

export const deleteCircleEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const eventId = (request.data?.eventId as string | undefined)?.trim();
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId || !eventId) {
    throw new HttpsError("invalid-argument", "invalid event delete payload");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  const eventRef = db.collection("events").doc(eventId);
  const [circleDoc, eventDoc] = await Promise.all([circleRef.get(), eventRef.get()]);
  assertCircleExists(circleDoc);
  if (!eventDoc.exists || eventDoc.data()?.circle_id !== circleId) {
    throw new HttpsError("not-found", "event not found");
  }
  const circle = circleDoc.data() ?? {};
  assertCanManageEvents(circle, uid);

  const batch = db.batch();
  batch.delete(eventRef);
  batch.set(circleRef.collection("audit_logs").doc(), auditLogData(
    uid,
    "event_deleted",
    "event",
    eventId,
    { title: eventDoc.data()?.title ?? null },
  ));
  await batch.commit();
  return { success: true };
});

export const pinCircleEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const eventId = request.data?.eventId === null || request.data?.eventId === undefined ?
    null : String(request.data.eventId).trim();
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId) {
    throw new HttpsError("invalid-argument", "circleId is required");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  const circleDoc = await circleRef.get();
  assertCircleExists(circleDoc);
  const circle = circleDoc.data() ?? {};
  assertCanManageEvents(circle, uid);

  if (eventId) {
    const eventDoc = await db.collection("events").doc(eventId).get();
    if (!eventDoc.exists || eventDoc.data()?.circle_id !== circleId) {
      throw new HttpsError("not-found", "event not found");
    }
  }

  const batch = db.batch();
  batch.update(circleRef, { pinned_event_id: eventId });
  batch.set(circleRef.collection("audit_logs").doc(), auditLogData(
    uid,
    eventId ? "event_pinned" : "event_unpinned",
    "event",
    eventId,
    { pinned_event_id: eventId },
  ));
  await batch.commit();
  return { success: true };
});

export const updateCircleProfile = onCall(async (request) => {
  const uid = request.auth?.uid;
  const circleId = (request.data?.circleId as string | undefined)?.trim();
  const updates = request.data?.updates as Record<string, unknown> | undefined;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  if (!circleId || !updates || typeof updates !== "object") {
    throw new HttpsError("invalid-argument", "invalid profile update payload");
  }

  const allowedKeys = [
    "description",
    "activity_days",
    "place",
    "member_count",
    "gender_ratio",
    "website_url",
    "icon_url",
    "x_id",
    "instagram_id",
  ];
  const sanitized: Record<string, unknown> = {};
  Object.entries(updates).forEach(([key, value]) => {
    if (allowedKeys.includes(key)) sanitized[key] = value;
  });
  if (Object.keys(sanitized).length === 0) {
    throw new HttpsError("invalid-argument", "no valid fields to update");
  }

  const db = admin.firestore();
  const circleRef = db.collection("circles").doc(circleId);
  const circleDoc = await circleRef.get();
  assertCircleExists(circleDoc);
  const circle = circleDoc.data() ?? {};
  assertCanManageCircle(circle, uid);

  const batch = db.batch();
  batch.update(circleRef, sanitized);
  batch.set(circleRef.collection("audit_logs").doc(), auditLogData(
    uid,
    "circle_profile_updated",
    "circle",
    circleId,
    sanitized,
  ));
  await batch.commit();
  return { success: true };
});

export const sendOtp = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const email = (request.data?.email as string | undefined)
    ?.trim()
    .toLowerCase();
  const purpose = (request.data?.purpose as string | undefined) ?? "student";
  const universityId = (request.data?.universityId as string | undefined)
    ?.trim()
    .toLowerCase();
  if (!email) {
    throw new HttpsError("invalid-argument", "email is required");
  }
  if (purpose !== "student" && purpose !== "contact") {
    throw new HttpsError("invalid-argument", "invalid purpose");
  }
  if (purpose === "student" &&
      (!universityId || !email.endsWith(universityId))) {
    throw new HttpsError("invalid-argument", "invalid university email");
  }
  if (purpose === "student") {
    const config = await readRegistrationConfig();
    ensureApprovedUniversityDomain(universityId, config);
  }

  const code = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 10 * 60 * 1000),
  );

  await admin.firestore().collection(OTPS_COLLECTION).doc(`${purpose}:${email}`).set(
    {
      code,
      email,
      purpose,
      universityId: universityId ?? null,
      uid,
      expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await admin.firestore().collection("mail").add({
    to: [email],
    message: {
      subject: purpose === "contact" ?
        "【Tekipa】連絡用メールアドレス認証コード" :
        "【Tekipa】認証コードのお知らせ",
      text: `認証コードは ${code} です。\nアプリに入力して認証を完了してください。`,
      html: `<p>認証コードは <b>${code}</b> です。</p><p>アプリに入力して認証を完了してください。</p>`,
    },
  });

  logger.info("OTP generated", { email, purpose, uid });

  return { success: true };
});

export const verifyOtp = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const email = (request.data?.email as string | undefined)
    ?.trim()
    .toLowerCase();
  const code = (request.data?.code as string | undefined)?.trim();
  const purpose = (request.data?.purpose as string | undefined) ?? "student";

  if (!email || !code) {
    throw new HttpsError("invalid-argument", "email and code are required");
  }
  if (purpose !== "student" && purpose !== "contact") {
    throw new HttpsError("invalid-argument", "invalid purpose");
  }

  const docRef = admin.firestore()
    .collection(OTPS_COLLECTION)
    .doc(`${purpose}:${email}`);
  const snapshot = await docRef.get();

  if (!snapshot.exists) {
    throw new HttpsError("failed-precondition", "Invalid or expired code.");
  }

  const data = snapshot.data() as {
    code?: string;
    email?: string;
    purpose?: string;
    universityId?: string;
    uid?: string;
    expiresAt?: admin.firestore.Timestamp;
  };
  const storedCode = data.code;
  const expiresAt = data.expiresAt;

  if (!storedCode || !expiresAt || data.uid !== uid || data.email !== email) {
    await docRef.delete();
    throw new HttpsError("failed-precondition", "Invalid or expired code.");
  }

  const now = admin.firestore.Timestamp.now();
  const isExpired = expiresAt.toMillis() < now.toMillis();
  const isMismatch = storedCode !== code;

  if (isExpired || isMismatch) {
    await docRef.delete();
    throw new HttpsError("failed-precondition", "Invalid or expired code.");
  }

  await docRef.delete();
  const userRef = admin.firestore().collection("users").doc(uid);
  if (purpose === "student") {
    if (!data.universityId || !email.endsWith(data.universityId)) {
      throw new HttpsError("failed-precondition", "Invalid university email.");
    }
    await userRef.set({
      universityEmail: email,
      universityId: data.universityId,
      isStudentVerified: true,
      verificationStatus: "verified",
      isFreshmanProvisional: false,
      freshmanProvisionalConvertedAt:
        admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    const userDoc = await userRef.get();
    const contactEmail = (userDoc.data()?.contactEmail as string | undefined)
      ?.trim()
      .toLowerCase();
    if (contactEmail && contactEmail !== email) {
      throw new HttpsError("failed-precondition", "Contact email changed.");
    }
    await userRef.set({
      contactEmail: email,
      isContactEmailVerified: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  return { success: true };
});

export const createFreshmanProvisionalUser = onCall(async (request) => {
  const uid = request.auth?.uid;
  const email = (request.auth?.token.email as string | undefined)
    ?.trim()
    .toLowerCase();

  if (!uid || !email) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const config = await readRegistrationConfig();
  if (!config.freshmanProvisionalEnabled ||
      !isFutureOrUnset(config.freshmanProvisionalExpiresAt)) {
    throw new HttpsError(
      "failed-precondition",
      "freshman provisional registration is closed",
    );
  }

  const userRef = admin.firestore().collection("users").doc(uid);
  const userDoc = await userRef.get();
  const userData = userDoc.data();

  if (userData?.isStudentVerified === true) {
    return { success: true, alreadyVerified: true };
  }

  await userRef.set({
    email,
    contactEmail: email,
    universityId: config.freshmanProvisionalUniversityId,
    grade: "学部1年",
    isProfileComplete: false,
    isStudentVerified: false,
    verificationStatus: "provisional_freshman",
    isFreshmanProvisional: true,
    provisionalAccessGrantedAt:
      admin.firestore.FieldValue.serverTimestamp(),
    provisionalExpiresAt: config.freshmanProvisionalExpiresAt ?? null,
    favoriteBookIds: userData?.favoriteBookIds ?? [],
    createdAt: userData?.createdAt ??
      admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    success: true,
    expiresAtMillis:
      config.freshmanProvisionalExpiresAt?.toMillis() ?? null,
  };
});

// Stripe Configuration
import Stripe from "stripe";
import { defineSecret, defineString } from "firebase-functions/params";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripePublishableKey = defineString("STRIPE_PUBLISHABLE_KEY");
const PAYMENT_HOLD_MINUTES = 10;
const BUNDLE_REQUEST_TTL_HOURS = 48;
const BUNDLE_RESERVATION_MINUTES = 60;

const bundleBuyerFee = (count: number) => {
  if (count <= 1) return 100;
  return 100 + (count - 1) * 30;
};

const releaseReservedBundleBooks = async (
  db: admin.firestore.Firestore,
  bundleRequestId: string,
  buyerId: string,
  nextStatus: "cancelled" | "expired",
) => {
  const requestRef = db.collection("bundle_requests").doc(bundleRequestId);
  await db.runTransaction(async (transaction) => {
    const requestDoc = await transaction.get(requestRef);
    if (!requestDoc.exists) return;
    const bundle = requestDoc.data() ?? {};
    if (bundle.buyerId !== buyerId || bundle.status !== "accepted") return;
    const bookIds = Array.isArray(bundle.bookIds) ?
      bundle.bookIds.map((id: unknown) => String(id)) : [];
    const bookRefs = bookIds.map((bookId: string) =>
      db.collection("books").doc(bookId));
    const bookDocs = await Promise.all(bookRefs.map((ref) => transaction.get(ref)));

    bookDocs.forEach((bookDoc, index) => {
      const book = bookDoc.data() ?? {};
      if (
        book.status === "reserved" &&
        book.reservedBy === buyerId &&
        book.reservedBundleRequestId === bundleRequestId
      ) {
        transaction.update(bookRefs[index], {
          status: "available",
          reservedBy: admin.firestore.FieldValue.delete(),
          reservedBundleRequestId: admin.firestore.FieldValue.delete(),
          reservedAt: admin.firestore.FieldValue.delete(),
          reservedUntil: admin.firestore.FieldValue.delete(),
        });
      }
    });
    transaction.update(requestRef, {
      status: nextStatus,
      reservedUntil: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
};

const cancelBundlePaymentIntentIfOpen = async (paymentIntentId: string) => {
  if (!paymentIntentId) return;
  const stripe = getStripe();
  const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
  if (["succeeded", "canceled"].includes(paymentIntent.status)) return;
  await stripe.paymentIntents.cancel(paymentIntentId).catch((error) => {
    logger.warn("Failed to cancel bundle PaymentIntent:", error);
  });
};

const notifyUser = async (
  userId: string,
  payload: {
    title: string;
    body: string;
    type: string;
    relatedId?: string | null;
    fromUid?: string | null;
  },
) => {
  const db = admin.firestore();
  await db.collection("users").doc(userId).collection("notifications").add({
    title: payload.title,
    body: payload.body,
    type: payload.type,
    relatedId: payload.relatedId ?? null,
    fromUid: payload.fromUid ?? null,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const userDoc = await db.collection("users").doc(userId).get();
  const fcmTokens = userDoc.data()?.fcmTokens as string[] | undefined;
  if (!fcmTokens || fcmTokens.length === 0) return;

  await admin.messaging().sendEachForMulticast({
    tokens: fcmTokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: {
      type: payload.type,
      relatedId: payload.relatedId ?? "",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  }).catch((error) => {
    logger.warn("Failed to send user notification:", error);
  });
};

// Lazy initialization of Stripe to access secret at runtime
let stripeInstance: Stripe | null = null;

const getStripe = (): Stripe => {
  if (!stripeInstance) {
    stripeInstance = new Stripe(stripeSecretKey.value(), {
      apiVersion: "2025-11-17.clover", // Use latest API version
    });
  }
  return stripeInstance;
};

/**
 * Create a Stripe Connect account for the user (seller).
 * This is an Express account.
 */
export const createConnectAccount = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const email = request.auth?.token.email;

  try {
    const stripe = getStripe();

    // 1. Check if user already has a Connect Account ID in Firestore
    const userDocRef = admin.firestore().collection("users").doc(uid);
    const userDoc = await userDocRef.get();
    const userData = userDoc.data();

    const existingAccountId = userData?.stripeAccountId ||
      userData?.stripeConnectedAccountId;
    if (existingAccountId) {
      const accountId = existingAccountId;
      // Ensure capabilities are requested even for existing accounts
      const account = await stripe.accounts.retrieve(accountId);
      if (
        account.capabilities?.card_payments !== "active" ||
        account.capabilities?.transfers !== "active"
      ) {
        await stripe.accounts.update(accountId, {
          capabilities: {
            card_payments: { requested: true },
            transfers: { requested: true },
          },
        });
      }
      if (userData?.stripeAccountId !== accountId) {
        await userDocRef.set({ stripeAccountId: accountId }, { merge: true });
      }
      return { accountId: accountId };
    }

    // 2. Create a new Express account
    const account = await stripe.accounts.create({
      type: "express",
      country: "JP",
      email: email,
      business_type: "individual",
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
    });

    // 3. Save the account ID to Firestore
    await userDocRef.set(
      { stripeAccountId: account.id },
      { merge: true },
    );

    return { accountId: account.id };
  } catch (error) {
    logger.error("Error creating connect account:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Create an Account Link for onboarding.
 * The user will be redirected to this URL to complete Stripe setup.
 */
export const createAccountLink = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const accountId = request.data.accountId;
  if (!accountId) {
    throw new HttpsError("invalid-argument", "Account ID is required");
  }



  try {
    const stripe = getStripe();
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${appFunctionBaseUrl}/stripeRedirect`,
      return_url: `${appFunctionBaseUrl}/stripeRedirect`,
      type: "account_onboarding",
    });

    return { url: accountLink.url };
  } catch (error) {
    logger.error("Error creating account link:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Create a PaymentIntent for a buyer to purchase an item.
 * The funds are transferred to the seller's connected account.
 */
export const createPaymentIntent = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  try {
    const bookId = (request.data?.bookId as string | undefined)?.trim();
    const requestedConnectedAccountId =
      (request.data?.connectedAccountId as string | undefined)?.trim();
    const currency = String(request.data?.currency ?? "jpy").toLowerCase();
    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId is required");
    }
    if (currency !== "jpy") {
      throw new HttpsError("invalid-argument", "unsupported currency");
    }

    const db = admin.firestore();
    const bookDoc = await db.collection("books").doc(bookId).get();
    if (!bookDoc.exists) {
      throw new HttpsError("not-found", "book not found");
    }
    const book = bookDoc.data() ?? {};
    if (book.userId === uid) {
      throw new HttpsError("failed-precondition", "seller cannot buy own item");
    }
    if (book.status && book.status !== "available") {
      throw new HttpsError("failed-precondition", "item is not available");
    }
    if ((book.moderationStatus ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "item is not available");
    }
    if (book.prohibitedCheckConfirmed === false) {
      throw new HttpsError("failed-precondition", "item is not available");
    }
    if (book.purchaseMode === "approval_required") {
      const requestDoc = await db.collection("purchase_requests")
        .doc(`${bookId}_${uid}`)
        .get();
      const purchaseRequest = requestDoc.data() ?? {};
      if (!requestDoc.exists ||
          purchaseRequest.status !== "approved" ||
          purchaseRequest.bookId !== bookId ||
          purchaseRequest.buyerId !== uid ||
          purchaseRequest.sellerId !== book.userId ||
          (
            purchaseRequest.expiresAt &&
            (purchaseRequest.expiresAt as admin.firestore.Timestamp)
              .toMillis() <= Date.now()
          )) {
        throw new HttpsError(
          "failed-precondition",
          "purchase request approval required",
        );
      }
    }
    const amount = Number(book.price);
    if (!Number.isInteger(amount) || amount < 0) {
      throw new HttpsError("failed-precondition", "invalid item price");
    }

    const sellerUid = String(book.userId ?? "");
    if (!sellerUid) {
      throw new HttpsError("failed-precondition", "seller not found");
    }
    const sellerDoc = await db.collection("users").doc(sellerUid).get();
    const seller = sellerDoc.data() ?? {};
    const connectedAccountId = String(
      seller.stripeAccountId ?? seller.stripeConnectedAccountId ?? "",
    );
    if (!connectedAccountId) {
      throw new HttpsError("failed-precondition", "seller stripe account not found");
    }
    if (requestedConnectedAccountId &&
        requestedConnectedAccountId !== connectedAccountId) {
      throw new HttpsError("permission-denied", "seller account mismatch");
    }

    const stripe = getStripe();

    // Self-healing: Check if the connected account has 'transfers' capability
    const account = await stripe.accounts.retrieve(connectedAccountId);
    if (account.capabilities?.transfers !== "active") {
      logger.info(`Account ${connectedAccountId} missing transfers capability. Attempting to enable.`);
      await stripe.accounts.update(connectedAccountId, {
        capabilities: {
          transfers: { requested: true },
          card_payments: { requested: true },
        },
      });

      // Re-fetch to check if it became active (in test mode it should be instant)
      const updatedAccount = await stripe.accounts.retrieve(connectedAccountId);
      logger.info(`Account ${connectedAccountId} capabilities after update:`, updatedAccount.capabilities);

      if (updatedAccount.capabilities?.transfers !== "active") {
        logger.warn(`Account ${connectedAccountId} transfers still inactive. Status: ${updatedAccount.capabilities?.transfers}`);
        logger.warn(`Missing requirements: ${JSON.stringify(updatedAccount.requirements?.currently_due)}`);

        // Throw a user-friendly error with specific missing requirements
        const missing = updatedAccount.requirements?.currently_due?.join(", ") || "Unknown requirements";
        throw new HttpsError(
          "failed-precondition",
          `Seller account is not ready. Status: ${updatedAccount.capabilities?.transfers}. Missing: ${missing}. Please check Sales Dashboard.`
        );
      }
    } else {
      logger.info(`Account ${connectedAccountId} has active transfers capability.`);
    }

    const fees = calculateSingleItemFees(book);
    const systemFee = fees.buyerFee;
    const totalAmount = fees.totalAmount;
    const salesCommission = fees.sellerCommission;
    const applicationFeeAmount = fees.applicationFeeAmount;

    // Create a Customer for the buyer (optional, but good for saving cards)
    // For simplicity, we'll create a new customer or use an existing one.
    // Here we just create an ephemeral key for the current user.

    // Note: In a real app, you should store stripeCustomerId in Firestore.
    // For this MVP, we will create a customer every time.
    // But PaymentSheet needs a customer to be ephemeral.

    let customerId = request.data.customerId;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: request.auth?.token.email,
        metadata: { firebaseUid: uid },
      });
      customerId = customer.id;
    }

    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: "2025-01-27.acacia" }
    );

    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalAmount,
      currency: currency,
      customer: customerId,
      application_fee_amount: applicationFeeAmount,
      transfer_data: {
        destination: connectedAccountId,
      },
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        bookId,
        buyerUid: uid,
        sellerUid,
        itemAmount: String(amount),
        systemFee: String(systemFee),
        sellerFeeRate: String(fees.feeRate),
        salesCommission: String(salesCommission),
        listingType: normalizeListingType(book.listingType),
      },
    });

    let previousPaymentIntentId = "";
    try {
      await db.runTransaction(async (transaction) => {
        const holdRef = db.collection("purchase_holds").doc(bookId);
        const freshBookDoc = await transaction.get(bookDoc.ref);
        const holdDoc = await transaction.get(holdRef);
        if (!freshBookDoc.exists) {
          throw new HttpsError("not-found", "book not found");
        }
        const freshBook = freshBookDoc.data() ?? {};
        if (freshBook.userId !== sellerUid) {
          throw new HttpsError("failed-precondition", "seller changed");
        }
        if (freshBook.status && freshBook.status !== "available") {
          throw new HttpsError("failed-precondition", "item is not available");
        }
        if ((freshBook.moderationStatus ?? "active") !== "active") {
          throw new HttpsError("failed-precondition", "item is not available");
        }
        if (freshBook.prohibitedCheckConfirmed === false) {
          throw new HttpsError("failed-precondition", "item is not available");
        }
        if (Number(freshBook.price) !== amount) {
          throw new HttpsError("failed-precondition", "item price changed");
        }
        const freshFees = calculateSingleItemFees(freshBook);
        if (freshFees.applicationFeeAmount !== applicationFeeAmount ||
            freshFees.totalAmount !== totalAmount) {
          throw new HttpsError("failed-precondition", "item fee changed");
        }

        const hold = holdDoc.data() ?? {};
        const holdExpiresAt = hold.expiresAt as
          admin.firestore.Timestamp | undefined;
        const activePaymentIntentId = String(hold.paymentIntentId ?? "");
        const activePaymentBuyerUid = String(hold.buyerUid ?? "");
        const holdActive = activePaymentIntentId &&
          holdExpiresAt &&
          holdExpiresAt.toMillis() > Date.now();
        if (holdActive && activePaymentBuyerUid !== uid) {
          throw new HttpsError(
            "failed-precondition",
            "item is being purchased",
          );
        }

        previousPaymentIntentId = activePaymentIntentId;
        transaction.set(holdRef, {
          bookId,
          buyerUid: uid,
          paymentIntentId: paymentIntent.id,
          expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + PAYMENT_HOLD_MINUTES * 60 * 1000,
          ),
          updatedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      await stripe.paymentIntents.cancel(paymentIntent.id).catch((cancelError) => {
        logger.warn("Failed to cancel unused PaymentIntent:", cancelError);
      });
      throw error;
    }

    if (previousPaymentIntentId &&
        previousPaymentIntentId !== paymentIntent.id) {
      await stripe.paymentIntents.cancel(previousPaymentIntentId)
        .catch((cancelError) => {
          logger.warn("Failed to cancel previous PaymentIntent:", cancelError);
        });
    }

    return {
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customerId,
      publishableKey: stripePublishableKey.value(),
      connectedAccountId,
      amount: totalAmount,
    };
  } catch (error) {
    logger.error("Error creating payment intent:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Finalize a paid purchase after Stripe confirms the PaymentIntent.
 * This creates the transaction room and marks the book as sold server-side.
 */
export const completeBookPurchase = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const bookId = (request.data?.bookId as string | undefined)?.trim();
  const paymentIntentId =
    (request.data?.paymentIntentId as string | undefined)?.trim();
  if (!bookId || !paymentIntentId) {
    throw new HttpsError("invalid-argument", "bookId and paymentIntentId are required");
  }

  try {
    const stripe = getStripe();
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (paymentIntent.status !== "succeeded") {
      throw new HttpsError("failed-precondition", "payment is not completed");
    }
    if (
      paymentIntent.metadata?.bookId !== bookId ||
      paymentIntent.metadata?.buyerUid !== uid
    ) {
      throw new HttpsError("permission-denied", "payment does not match purchase");
    }
    const metadataItemAmount = Number(paymentIntent.metadata?.itemAmount);
    const metadataBuyerFee = Number(paymentIntent.metadata?.systemFee);
    const metadataSellerFeeRate = Number(paymentIntent.metadata?.sellerFeeRate);

    const db = admin.firestore();
    const chatRoomRef = db.collection("chat_rooms").doc(paymentIntentId);
    await db.runTransaction(async (transaction) => {
      const existingChat = await transaction.get(chatRoomRef);
      if (existingChat.exists) {
        const chat = existingChat.data() ?? {};
        if (chat.buyerId !== uid || chat.bookId !== bookId) {
          throw new HttpsError("permission-denied", "transaction already exists");
        }
        return;
      }

      const bookRef = db.collection("books").doc(bookId);
      const holdRef = db.collection("purchase_holds").doc(bookId);
      const bookDoc = await transaction.get(bookRef);
      const holdDoc = await transaction.get(holdRef);
      if (!bookDoc.exists) {
        throw new HttpsError("not-found", "book not found");
      }
      const book = bookDoc.data() ?? {};
      const sellerUid = String(book.userId ?? "");
      if (!sellerUid || sellerUid === uid) {
        throw new HttpsError("failed-precondition", "invalid seller");
      }
      if (book.status && book.status !== "available") {
        throw new HttpsError("failed-precondition", "item is not available");
      }
      if ((book.moderationStatus ?? "active") !== "active") {
        throw new HttpsError("failed-precondition", "item is not available");
      }
      if (book.prohibitedCheckConfirmed === false) {
        throw new HttpsError("failed-precondition", "item is not available");
      }
      if (book.purchaseMode === "approval_required") {
        const requestRef = db.collection("purchase_requests")
          .doc(`${bookId}_${uid}`);
        const requestDoc = await transaction.get(requestRef);
        const purchaseRequest = requestDoc.data() ?? {};
        if (!requestDoc.exists ||
            purchaseRequest.status !== "approved" ||
            purchaseRequest.bookId !== bookId ||
            purchaseRequest.buyerId !== uid ||
            purchaseRequest.sellerId !== sellerUid ||
            (
              purchaseRequest.expiresAt &&
              (purchaseRequest.expiresAt as admin.firestore.Timestamp)
                .toMillis() <= Date.now()
            )) {
          throw new HttpsError(
            "failed-precondition",
            "purchase request approval required",
          );
        }
        transaction.update(requestRef, {
          status: "paid",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      const hold = holdDoc.data() ?? {};
      const activePaymentIntentId = String(hold.paymentIntentId ?? "");
      const activePaymentBuyerUid = String(hold.buyerUid ?? "");
      const holdExpiresAt = hold.expiresAt as
        admin.firestore.Timestamp | undefined;
      const anotherActiveHold = activePaymentIntentId &&
        activePaymentIntentId !== paymentIntentId &&
        activePaymentBuyerUid !== uid &&
        holdExpiresAt &&
        holdExpiresAt.toMillis() > Date.now();
      if (anotherActiveHold) {
        throw new HttpsError(
          "failed-precondition",
          "item is being purchased",
        );
      }
      const settledItemAmount =
        Number.isInteger(metadataItemAmount) && metadataItemAmount >= 0 ?
          metadataItemAmount :
          Number(book.price) || 0;
      const settledBuyerFee =
        Number.isInteger(metadataBuyerFee) && metadataBuyerFee >= 0 ?
          metadataBuyerFee :
          BUYER_SYSTEM_FEE_JPY;
      const settledFeeRate =
        Number.isFinite(metadataSellerFeeRate) && metadataSellerFeeRate > 0 ?
          metadataSellerFeeRate :
          sellerFeeRateForBook(book);

      transaction.update(bookRef, {
        status: "sold",
        buyerUid: uid,
        price: settledItemAmount,
        soldAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (holdDoc.exists) {
        transaction.delete(holdRef);
      }
      transaction.set(chatRoomRef, {
        buyerId: uid,
        sellerId: sellerUid,
        bookId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        participants: [uid, sellerUid],
        participantIds: [uid, sellerUid],
        price: settledItemAmount,
        listingType: normalizeListingType(book.listingType),
        feeRate: settledFeeRate,
        buyerFee: settledBuyerFee,
        status: "paid",
        bookExists: true,
        meetingStatus: "initial",
        paymentIntentId,
      });
    });

    return { success: true, chatRoomId: chatRoomRef.id };
  } catch (error) {
    logger.error("Error completing purchase:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Release a temporary purchase hold when the buyer cancels before paying.
 */
export const releasePaymentHold = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const bookId = (request.data?.bookId as string | undefined)?.trim();
  const paymentIntentId =
    (request.data?.paymentIntentId as string | undefined)?.trim();
  if (!bookId || !paymentIntentId) {
    throw new HttpsError("invalid-argument", "bookId and paymentIntentId are required");
  }

  try {
    const db = admin.firestore();
    let released = false;
    await db.runTransaction(async (transaction) => {
      const holdRef = db.collection("purchase_holds").doc(bookId);
      const holdDoc = await transaction.get(holdRef);
      if (!holdDoc.exists) return;

      const hold = holdDoc.data() ?? {};
      if (
        hold.paymentIntentId === paymentIntentId &&
        hold.buyerUid === uid
      ) {
        released = true;
        transaction.delete(holdRef);
      }
    });

    if (released) {
      const stripe = getStripe();
      await stripe.paymentIntents.cancel(paymentIntentId)
        .catch((cancelError) => {
          logger.warn("Failed to cancel released PaymentIntent:", cancelError);
        });
    }

    return { success: true, released };
  } catch (error) {
    logger.error("Error releasing payment hold:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

export const createBundleRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const bookIds = Array.isArray(request.data?.bookIds) ?
    [...new Set((request.data.bookIds as unknown[])
      .map((id) => String(id).trim())
      .filter(Boolean))] : [];
  const buyerMessage = String(request.data?.buyerMessage ?? "").trim();
  if (bookIds.length < 2 || bookIds.length > 10) {
    throw new HttpsError("invalid-argument", "bookIds must contain 2 to 10 items");
  }

  const db = admin.firestore();
  const bookRefs = bookIds.map((id) => db.collection("books").doc(id));
  const bookDocs = await db.getAll(...bookRefs);
  if (bookDocs.some((doc) => !doc.exists)) {
    throw new HttpsError("not-found", "one or more books were not found");
  }

  const books = bookDocs.map((doc) => doc.data() ?? {});
  const sellerId = String(books[0].userId ?? "");
  if (!sellerId || sellerId === uid) {
    throw new HttpsError("failed-precondition", "invalid seller");
  }
  if (books.some((book) => String(book.userId ?? "") !== sellerId)) {
    throw new HttpsError("failed-precondition", "all books must belong to the same seller");
  }
  if (books.some((book) => book.status && book.status !== "available")) {
    throw new HttpsError("failed-precondition", "all books must be available");
  }
  if (books.some((book) => (book.moderationStatus ?? "active") !== "active")) {
    throw new HttpsError("failed-precondition", "all books must be available");
  }
  if (books.some((book) => book.prohibitedCheckConfirmed === false)) {
    throw new HttpsError("failed-precondition", "all books must be available");
  }

  const originalTotalPrice = books.reduce((sum, book) => {
    const price = Number(book.price);
    if (!Number.isInteger(price) || price < 0) {
      throw new HttpsError("failed-precondition", "invalid item price");
    }
    return sum + price;
  }, 0);
  const proposedTotalPrice = Number.isInteger(Number(request.data?.proposedTotalPrice)) ?
    Number(request.data.proposedTotalPrice) : originalTotalPrice;
  if (proposedTotalPrice < 0 || proposedTotalPrice > originalTotalPrice) {
    throw new HttpsError("invalid-argument", "invalid proposed total price");
  }

  const userDoc = await db.collection("users").doc(uid).get();
  const universityId = userDoc.data()?.universityId ??
    books[0].universityId ??
    DEFAULT_UNIVERSITY_ID;

  const requestRef = db.collection("bundle_requests").doc();
  await requestRef.set({
    buyerId: uid,
    sellerId,
    bookIds,
    originalTotalPrice,
    proposedTotalPrice,
    buyerMessage,
    sellerMessage: null,
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(
      Date.now() + BUNDLE_REQUEST_TTL_HOURS * 60 * 60 * 1000,
    ),
    chatRoomId: null,
    paymentIntentId: null,
    universityId,
  });

  await notifyUser(sellerId, {
    title: "まとめ買い依頼が届きました",
    body: `${bookIds.length}冊のまとめ買い依頼があります。承認すると商品が一時的に確保されます。`,
    type: "bundle",
    relatedId: requestRef.id,
    fromUid: uid,
  });

  return { success: true, bundleRequestId: requestRef.id };
});

export const respondBundleRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  const bundleRequestId =
    (request.data?.bundleRequestId as string | undefined)?.trim();
  const action = String(request.data?.action ?? "").trim();
  const sellerMessage = String(request.data?.sellerMessage ?? "").trim();
  const proposedTotalPrice = request.data?.proposedTotalPrice;
  if (!bundleRequestId || !["accepted", "rejected"].includes(action)) {
    throw new HttpsError("invalid-argument", "invalid bundle response");
  }

  const db = admin.firestore();
  const requestRef = db.collection("bundle_requests").doc(bundleRequestId);
  let buyerIdForNotification = "";
  let reservedUntilForNotification: admin.firestore.Timestamp | undefined;
  await db.runTransaction(async (transaction) => {
    const requestDoc = await transaction.get(requestRef);
    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "bundle request not found");
    }
    const bundle = requestDoc.data() ?? {};
    buyerIdForNotification = String(bundle.buyerId ?? "");
    if (bundle.sellerId !== uid) {
      throw new HttpsError("permission-denied", "seller permission required");
    }
    if (bundle.status !== "pending") {
      throw new HttpsError("failed-precondition", "bundle request is not pending");
    }
    const expiresAt = bundle.expiresAt as admin.firestore.Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() <= Date.now()) {
      transaction.update(requestRef, {
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("failed-precondition", "bundle request expired");
    }

    let acceptedTotal = Number(bundle.proposedTotalPrice ?? 0);
    if (action === "accepted" && proposedTotalPrice !== undefined) {
      acceptedTotal = Number(proposedTotalPrice);
      const originalTotal = Number(bundle.originalTotalPrice ?? 0);
      if (!Number.isInteger(acceptedTotal) ||
          acceptedTotal < 0 ||
          acceptedTotal > originalTotal) {
        throw new HttpsError("invalid-argument", "invalid proposed total price");
      }
    }

    const updateData: Record<string, unknown> = {
      status: action,
      proposedTotalPrice: acceptedTotal,
      sellerMessage,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (action === "accepted") {
      const bookIds = Array.isArray(bundle.bookIds) ?
        bundle.bookIds.map((id: unknown) => String(id)) : [];
      const buyerId = String(bundle.buyerId ?? "");
      if (bookIds.length < 2 || !buyerId) {
        throw new HttpsError("failed-precondition", "invalid bundle request");
      }
      const bookRefs = bookIds.map((id: string) => db.collection("books").doc(id));
      const bookDocs = await Promise.all(bookRefs.map((ref) => transaction.get(ref)));
      bookDocs.forEach((doc) => {
        if (!doc.exists) throw new HttpsError("not-found", "book not found");
        const book = doc.data() ?? {};
        if (book.userId !== uid) {
          throw new HttpsError("failed-precondition", "seller mismatch");
        }
        if (book.status && book.status !== "available") {
          throw new HttpsError(
            "failed-precondition",
            "one or more books are no longer available",
          );
        }
      });

      const reservedUntil = admin.firestore.Timestamp.fromMillis(
        Date.now() + BUNDLE_RESERVATION_MINUTES * 60 * 1000,
      );
      reservedUntilForNotification = reservedUntil;
      bookRefs.forEach((ref) => {
        transaction.update(ref, {
          status: "reserved",
          reservedBy: buyerId,
          reservedBundleRequestId: bundleRequestId,
          reservedAt: admin.firestore.FieldValue.serverTimestamp(),
          reservedUntil,
        });
      });
      updateData.reservedUntil = reservedUntil;
    } else {
      updateData.reservedUntil = admin.firestore.FieldValue.delete();
    }

    transaction.update(requestRef, updateData);
  });

  if (buyerIdForNotification) {
    const accepted = action === "accepted";
    await notifyUser(buyerIdForNotification, {
      title: accepted ? "まとめ買い依頼が承認されました" : "まとめ買い依頼が拒否されました",
      body: accepted
        ? `商品が決済用に確保されました。${reservedUntilForNotification ? "期限内に支払いを完了してください。" : "早めに支払いを完了してください。"}`
        : "出品者がまとめ買い依頼を拒否しました。",
      type: "bundle",
      relatedId: bundleRequestId,
      fromUid: uid,
    });
  }

  return { success: true };
});

export const createBundlePaymentIntent = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  const bundleRequestId =
    (request.data?.bundleRequestId as string | undefined)?.trim();
  if (!bundleRequestId) {
    throw new HttpsError("invalid-argument", "bundleRequestId is required");
  }

  const db = admin.firestore();
  const requestRef = db.collection("bundle_requests").doc(bundleRequestId);
  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new HttpsError("not-found", "bundle request not found");
  }
  const bundle = requestDoc.data() ?? {};
  if (bundle.buyerId !== uid) {
    throw new HttpsError("permission-denied", "buyer permission required");
  }
  if (bundle.status !== "accepted") {
    throw new HttpsError("failed-precondition", "bundle request is not accepted");
  }
  const expiresAt = bundle.expiresAt as admin.firestore.Timestamp | undefined;
  if (expiresAt && expiresAt.toMillis() <= Date.now()) {
    await requestRef.update({
      status: "expired",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("failed-precondition", "bundle request expired");
  }

  const bookIds = Array.isArray(bundle.bookIds) ?
    bundle.bookIds.map((id) => String(id)) : [];
  const sellerUid = String(bundle.sellerId ?? "");
  const itemAmount = Number(bundle.proposedTotalPrice);
  if (bookIds.length < 2 || !sellerUid || !Number.isInteger(itemAmount)) {
    throw new HttpsError("failed-precondition", "invalid bundle request");
  }

  const bookRefs = bookIds.map((id) => db.collection("books").doc(id));
  let reservationExpired = false;
  await db.runTransaction(async (transaction) => {
    const freshRequestDoc = await transaction.get(requestRef);
    if (!freshRequestDoc.exists) {
      throw new HttpsError("not-found", "bundle request not found");
    }
    const freshBundle = freshRequestDoc.data() ?? {};
    if (freshBundle.buyerId !== uid || freshBundle.status !== "accepted") {
      throw new HttpsError("failed-precondition", "bundle request is not accepted");
    }
    const reservedUntil =
      freshBundle.reservedUntil as admin.firestore.Timestamp | undefined;
    const docs = await Promise.all(bookRefs.map((ref) => transaction.get(ref)));
    if (!reservedUntil || reservedUntil.toMillis() <= Date.now()) {
      docs.forEach((doc, index) => {
        const book = doc.data() ?? {};
        if (
          book.status === "reserved" &&
          book.reservedBy === uid &&
          book.reservedBundleRequestId === bundleRequestId
        ) {
          transaction.update(bookRefs[index], {
            status: "available",
            reservedBy: admin.firestore.FieldValue.delete(),
            reservedBundleRequestId: admin.firestore.FieldValue.delete(),
            reservedAt: admin.firestore.FieldValue.delete(),
            reservedUntil: admin.firestore.FieldValue.delete(),
          });
        }
      });
      transaction.update(requestRef, {
        status: "expired",
        reservedUntil: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      reservationExpired = true;
      return;
    }
    docs.forEach((doc) => {
      if (!doc.exists) throw new HttpsError("not-found", "book not found");
      const book = doc.data() ?? {};
      if (book.userId !== sellerUid) {
        throw new HttpsError("failed-precondition", "seller mismatch");
      }
      const bookReservedUntil =
        book.reservedUntil as admin.firestore.Timestamp | undefined;
      if (
        book.status !== "reserved" ||
        book.reservedBy !== uid ||
        book.reservedBundleRequestId !== bundleRequestId ||
        !bookReservedUntil ||
        bookReservedUntil.toMillis() <= Date.now()
      ) {
        throw new HttpsError("failed-precondition", "bundle item is not reserved");
      }
    });
  });
  if (reservationExpired) {
    throw new HttpsError("failed-precondition", "bundle reservation expired");
  }
  const feeDocs = await db.getAll(...bookRefs);
  const salesCommissionTotal = feeDocs.reduce((sum, doc) => {
    const book = doc.data() ?? {};
    const price = Number(book.price);
    if (!Number.isInteger(price)) return sum;
    return sum + Math.floor(price * sellerFeeRateForBook(book));
  }, 0);

  let createdPaymentIntentId = "";
  try {
    const sellerDoc = await db.collection("users").doc(sellerUid).get();
    const seller = sellerDoc.data() ?? {};
    const connectedAccountId = String(
      seller.stripeAccountId ?? seller.stripeConnectedAccountId ?? "",
    );
    if (!connectedAccountId) {
      throw new HttpsError("failed-precondition", "seller stripe account not found");
    }

    const stripe = getStripe();
    const account = await stripe.accounts.retrieve(connectedAccountId);
    if (account.capabilities?.transfers !== "active") {
      throw new HttpsError("failed-precondition", "Seller account is not ready");
    }

    const buyerFee = bundleBuyerFee(bookIds.length);
    const totalAmount = itemAmount + buyerFee;
    const salesCommission = salesCommissionTotal > 0 ?
      salesCommissionTotal :
      Math.floor(itemAmount * 0.05);
    const applicationFeeAmount = buyerFee + salesCommission;
    const customer = await stripe.customers.create({
      email: request.auth?.token.email,
      metadata: { firebaseUid: uid },
    });
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: "2025-01-27.acacia" },
    );
    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalAmount,
      currency: "jpy",
      customer: customer.id,
      application_fee_amount: applicationFeeAmount,
      transfer_data: { destination: connectedAccountId },
      automatic_payment_methods: { enabled: true },
      metadata: {
        bundleRequestId,
        buyerUid: uid,
        sellerUid,
        bookIds: bookIds.join(","),
        itemAmount: String(itemAmount),
        buyerFee: String(buyerFee),
      },
    });
    createdPaymentIntentId = paymentIntent.id;

    await requestRef.update({
      paymentIntentId: paymentIntent.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customer.id,
      publishableKey: stripePublishableKey.value(),
      connectedAccountId,
      amount: totalAmount,
      buyerFee,
      itemAmount,
    };
  } catch (error) {
    await cancelBundlePaymentIntentIfOpen(createdPaymentIntentId);
    await releaseReservedBundleBooks(db, bundleRequestId, uid, "cancelled");
    throw error;
  }
});

export const completeBundlePurchase = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  const bundleRequestId =
    (request.data?.bundleRequestId as string | undefined)?.trim();
  const paymentIntentId =
    (request.data?.paymentIntentId as string | undefined)?.trim();
  if (!bundleRequestId || !paymentIntentId) {
    throw new HttpsError("invalid-argument", "bundleRequestId and paymentIntentId are required");
  }

  const stripe = getStripe();
  const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError("failed-precondition", "payment is not completed");
  }
  if (
    paymentIntent.metadata?.bundleRequestId !== bundleRequestId ||
    paymentIntent.metadata?.buyerUid !== uid
  ) {
    throw new HttpsError("permission-denied", "payment does not match bundle");
  }

  const db = admin.firestore();
  const requestRef = db.collection("bundle_requests").doc(bundleRequestId);
  const chatRoomRef = db.collection("chat_rooms").doc(paymentIntentId);
  await db.runTransaction(async (transaction) => {
    const existingChat = await transaction.get(chatRoomRef);
    if (existingChat.exists) {
      const chat = existingChat.data() ?? {};
      if (chat.buyerId !== uid || chat.bundleRequestId !== bundleRequestId) {
        throw new HttpsError("permission-denied", "transaction already exists");
      }
      return;
    }

    const requestDoc = await transaction.get(requestRef);
    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "bundle request not found");
    }
    const bundle = requestDoc.data() ?? {};
    if (bundle.buyerId !== uid || bundle.status !== "accepted") {
      throw new HttpsError("failed-precondition", "invalid bundle request");
    }
    const bookIds = Array.isArray(bundle.bookIds) ?
      bundle.bookIds.map((id) => String(id)) : [];
    const sellerUid = String(bundle.sellerId ?? "");
    const bookRefs = bookIds.map((id) => db.collection("books").doc(id));
    const bookDocs = await Promise.all(bookRefs.map((ref) => transaction.get(ref)));
    bookDocs.forEach((doc) => {
      if (!doc.exists) throw new HttpsError("not-found", "book not found");
      const book = doc.data() ?? {};
      if (book.userId !== sellerUid ||
          book.status !== "reserved" ||
          book.reservedBy !== uid ||
          book.reservedBundleRequestId !== bundleRequestId) {
        throw new HttpsError("failed-precondition", "bundle item is not reserved");
      }
    });

    bookRefs.forEach((ref) => {
      transaction.update(ref, {
        status: "sold",
        buyerUid: uid,
        soldAt: admin.firestore.FieldValue.serverTimestamp(),
        reservedBy: admin.firestore.FieldValue.delete(),
        reservedBundleRequestId: admin.firestore.FieldValue.delete(),
        reservedAt: admin.firestore.FieldValue.delete(),
        reservedUntil: admin.firestore.FieldValue.delete(),
      });
    });
    const buyerFee = bundleBuyerFee(bookIds.length);
    const totalPrice = Number(bundle.proposedTotalPrice ?? 0);
    transaction.update(requestRef, {
      status: "paid",
      chatRoomId: chatRoomRef.id,
      paymentIntentId,
      reservedUntil: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(chatRoomRef, {
      buyerId: uid,
      sellerId: sellerUid,
      bookId: bookIds[0],
      bookIds,
      isBundle: true,
      bundleRequestId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      participants: [uid, sellerUid],
      participantIds: [uid, sellerUid],
      price: totalPrice,
      totalPrice,
      platformFee: buyerFee,
      sellerPayout: totalPrice - Math.floor(totalPrice * 0.05),
      status: "paid",
      bookExists: true,
      meetingStatus: "initial",
      paymentIntentId,
    });
  });

  const paidBundleDoc = await requestRef.get();
  const paidBundle = paidBundleDoc.data() ?? {};
  const sellerUid = String(paidBundle.sellerId ?? "");
  if (sellerUid) {
    await notifyUser(sellerUid, {
      title: "まとめ買いの支払いが完了しました",
      body: "購入者の支払いが完了しました。取引チャットで受け渡しを相談してください。",
      type: "transaction",
      relatedId: chatRoomRef.id,
      fromUid: uid,
    });
  }

  return { success: true, chatRoomId: chatRoomRef.id };
});

export const releaseBundleReservation = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }
  const bundleRequestId =
    (request.data?.bundleRequestId as string | undefined)?.trim();
  if (!bundleRequestId) {
    throw new HttpsError("invalid-argument", "bundleRequestId is required");
  }
  const db = admin.firestore();
  const requestRef = db.collection("bundle_requests").doc(bundleRequestId);
  let paymentIntentToCancel = "";
  await db.runTransaction(async (transaction) => {
    const requestDoc = await transaction.get(requestRef);
    if (!requestDoc.exists || requestDoc.data()?.buyerId !== uid) {
      throw new HttpsError("permission-denied", "buyer permission required");
    }
    const bundle = requestDoc.data() ?? {};
    if (bundle.status !== "accepted") {
      return;
    }
    paymentIntentToCancel = String(bundle.paymentIntentId ?? "");
    const bookIds = Array.isArray(bundle.bookIds) ?
      bundle.bookIds.map((id: unknown) => String(id)) : [];
    const bookRefs = bookIds.map((bookId: string) =>
      db.collection("books").doc(bookId));
    const bookDocs = await Promise.all(bookRefs.map((ref) => transaction.get(ref)));
    bookDocs.forEach((bookDoc, index) => {
      const book = bookDoc.data() ?? {};
      if (
        book.status === "reserved" &&
        book.reservedBy === uid &&
        book.reservedBundleRequestId === bundleRequestId
      ) {
        transaction.update(bookRefs[index], {
          status: "available",
          reservedBy: admin.firestore.FieldValue.delete(),
          reservedBundleRequestId: admin.firestore.FieldValue.delete(),
          reservedAt: admin.firestore.FieldValue.delete(),
          reservedUntil: admin.firestore.FieldValue.delete(),
        });
      }
    });
    transaction.update(requestRef, {
      status: "cancelled",
      reservedUntil: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await cancelBundlePaymentIntentIfOpen(paymentIntentToCancel);
  return { success: true };
});

export const expireBundleReservations = onSchedule(
  {
    schedule: "every 5 minutes",
    secrets: [stripeSecretKey],
    timeZone: "Asia/Tokyo",
  },
  async () => {
    const db = admin.firestore();
    const nowMillis = Date.now();
    const snapshot = await db.collection("bundle_requests")
      .where("status", "==", "accepted")
      .limit(100)
      .get();

    for (const doc of snapshot.docs) {
      const bundle = doc.data() ?? {};
      const reservedUntil =
        bundle.reservedUntil as admin.firestore.Timestamp | undefined;
      if (!reservedUntil || reservedUntil.toMillis() > nowMillis) continue;

      const buyerId = String(bundle.buyerId ?? "");
      if (!buyerId) continue;
      await releaseReservedBundleBooks(db, doc.id, buyerId, "expired");
      await notifyUser(buyerId, {
        title: "まとめ買いの確保期限が切れました",
        body: "支払い期限を過ぎたため、商品の確保を解除しました。必要な場合は再度依頼してください。",
        type: "bundle",
        relatedId: doc.id,
      });

      const paymentIntentId = String(bundle.paymentIntentId ?? "");
      await cancelBundlePaymentIntentIfOpen(paymentIntentId);
    }
  },
);

/**
 * Create a login link for the Stripe Express Dashboard.
 * Allows sellers to view payouts and edit account details.
 */
export const createStripeLoginLink = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const stripe = getStripe();

  try {
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.data();
    const accountId = userData?.stripeAccountId ||
      userData?.stripeConnectedAccountId;

    if (!accountId) {
      throw new HttpsError("failed-precondition", "Stripe account not found");
    }

    const account = await stripe.accounts.retrieve(accountId);

    // Ensure capabilities are requested
    if (
      account.capabilities?.card_payments !== "active" ||
      account.capabilities?.transfers !== "active"
    ) {
      await stripe.accounts.update(accountId, {
        business_type: "individual",
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
      });
    }

    // If capabilities are not active, force onboarding/update flow
    if (
      account.capabilities?.transfers !== "active" ||
      account.capabilities?.card_payments !== "active" ||
      !account.details_submitted
    ) {
      logger.info(`Account ${accountId} not fully active. Redirecting to onboarding.`);
      const accountLink = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: `${appFunctionBaseUrl}/stripeRedirect`,
        return_url: `${appFunctionBaseUrl}/stripeRedirect`,
        type: "account_onboarding",
      });
      return { url: accountLink.url };
    }

    const loginLink = await stripe.accounts.createLoginLink(accountId);
    return { url: loginLink.url };
  } catch (error) {
    logger.error("Error creating login link:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Get the seller's account balance.
 */
export const getAccountBalance = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const stripe = getStripe();

  try {
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.data();
    const accountId = userData?.stripeAccountId ||
      userData?.stripeConnectedAccountId;

    if (!accountId) {
      throw new HttpsError("failed-precondition", "Stripe account not found");
    }

    const balance = await stripe.balance.retrieve({
      stripeAccount: accountId,
    });

    // Calculate available and pending amounts in JPY
    const available = balance.available.reduce((acc, bal) => {
      return bal.currency === "jpy" ? acc + bal.amount : acc;
    }, 0);

    const pending = balance.pending.reduce((acc, bal) => {
      return bal.currency === "jpy" ? acc + bal.amount : acc;
    }, 0);

    return {
      available: available,
      pending: pending,
    };
  } catch (error) {
    logger.error("Error fetching account balance:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * Approve a transaction cancellation and refund it after validating ownership.
 */
export const refundPayment = onCall({ secrets: [stripeSecretKey] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in");
  }

  const chatRoomId = (request.data?.chatRoomId as string | undefined)?.trim();
  if (!chatRoomId) {
    throw new HttpsError("invalid-argument", "chatRoomId is required");
  }

  try {
    const db = admin.firestore();
    const chatRoomRef = db.collection("chat_rooms").doc(chatRoomId);
    const chatRoomDoc = await chatRoomRef.get();
    if (!chatRoomDoc.exists) {
      throw new HttpsError("not-found", "transaction not found");
    }
    const chat = chatRoomDoc.data() ?? {};
    const participants = Array.isArray(chat.participants) ?
      chat.participants as string[] : [];
    if (chat.buyerId !== uid && chat.sellerId !== uid && !participants.includes(uid)) {
      throw new HttpsError("permission-denied", "not a transaction participant");
    }
    if (chat.status === "completed") {
      throw new HttpsError("failed-precondition", "completed transaction cannot be refunded");
    }
    if (chat.cancellationStatus === "approved") {
      return { success: true, alreadyApproved: true };
    }
    if (chat.cancellationStatus !== "requesting") {
      throw new HttpsError("failed-precondition", "cancellation is not requested");
    }
    if (chat.cancellationRequesterId === uid) {
      throw new HttpsError("permission-denied", "requester cannot approve own cancellation");
    }

    const paymentIntentId = String(chat.paymentIntentId ?? "");
    const bookId = String(chat.bookId ?? "");
    if (!paymentIntentId || !bookId) {
      throw new HttpsError("failed-precondition", "missing payment data");
    }

    const stripe = getStripe();
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
    }, {
      idempotencyKey: `refund-${chatRoomId}`,
    });

    const batch = db.batch();
    batch.update(chatRoomRef, {
      status: "cancelled",
      cancellationStatus: "approved",
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      bookExists: true,
      refundId: refund.id,
    });
    const bookIds = Array.isArray(chat.bookIds) ?
      chat.bookIds.map((id: unknown) => String(id)) :
      [bookId];
    bookIds.forEach((targetBookId: string) => {
      batch.update(db.collection("books").doc(targetBookId), {
        status: "available",
        buyerUid: admin.firestore.FieldValue.delete(),
        soldAt: admin.firestore.FieldValue.delete(),
        reservedBy: admin.firestore.FieldValue.delete(),
        reservedBundleRequestId: admin.firestore.FieldValue.delete(),
        reservedAt: admin.firestore.FieldValue.delete(),
        reservedUntil: admin.firestore.FieldValue.delete(),
      });
    });
    if (chat.bundleRequestId) {
      batch.update(db.collection("bundle_requests").doc(String(chat.bundleRequestId)), {
        status: "cancelled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    return { success: true, refundId: refund.id };
  } catch (error) {
    logger.error("Error processing refund:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", message);
  }
});

/**
 * HTTP function to redirect Stripe callbacks to the app.
 * Stripe requires an https URL, so we use this to bridge to the custom scheme.
 */
export const stripeRedirect = onRequest((req, res) => {
  res.redirect("textpass://connect-callback");
});

export const debugStripeAccount = onRequest((_req, res) => {
  res.status(404).send("Not found");
});

// Notifications
// import { onDocumentCreated } from "firebase-functions/v2/firestore"; // Moved to top

/**
 * Send a push notification when a new message is added to a chat room.
 */
export const sendChatNotification = onDocumentCreated(
  "chat_rooms/{chatId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const messageData = snapshot.data();
    const chatId = event.params.chatId;
    const senderId = messageData.senderId;
    const text = messageData.text;

    // 1. Get the chat room document to find participants
    const chatDoc = await admin.firestore().collection("chat_rooms").doc(chatId).get();
    const chatData = chatDoc.data();

    if (!chatData) {
      logger.error(`Chat room ${chatId} not found`);
      return;
    }

    const participantIds = (chatData.participants ||
      chatData.participantIds) as string[] | undefined;
    if (!participantIds || !Array.isArray(participantIds)) {
      logger.error("Participant list not found");
      return;
    }
    // Find the recipient (the one who is NOT the sender)
    const recipientId = participantIds.find((uid) => uid !== senderId);

    if (!recipientId) {
      logger.error("Recipient not found");
      return;
    }

    // 2. Get the recipient's FCM tokens
    const userDoc = await admin.firestore().collection("users").doc(recipientId).get();
    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens as string[] | undefined;

    if (!fcmTokens || fcmTokens.length === 0) {
      logger.info(`No FCM tokens for user ${recipientId}`);
      return;
    }

    // 3. Send the notification
    const payload: admin.messaging.MulticastMessage = {
      tokens: fcmTokens,
      notification: {
        title: "新着メッセージ",
        body: text.length > 50 ? text.substring(0, 50) + "..." : text,
      },
      data: {
        type: "chat",
        chatId: chatId,
      },
      android: {
        notification: {
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(payload);
      logger.info(
        `Sent notification to ${recipientId}. Success: ${response.successCount}, Failure: ${response.failureCount}`
      );

      // Cleanup invalid tokens
      if (response.failureCount > 0) {
        const failedTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            failedTokens.push(fcmTokens[idx]);
          }
        });

        if (failedTokens.length > 0) {
          await admin.firestore().collection("users").doc(recipientId).update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...failedTokens),
          });
          logger.info(`Removed ${failedTokens.length} invalid tokens`);
        }
      }
    } catch (error) {
      logger.error("Error sending notification:", error);
    }
  }
);

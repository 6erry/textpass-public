import argparse
import os
import sys

import firebase_admin
from firebase_admin import credentials, firestore

from syllabus_identity import UNIVERSITY_ID, build_class_key, parse_teacher, parse_title


BATCH_SIZE = 450


def initialize_firebase(service_account_key):
    if not os.path.exists(service_account_key):
        print(f"Error: {service_account_key} not found.")
        sys.exit(1)

    if not firebase_admin._apps:
        cred = credentials.Certificate(service_account_key)
        firebase_admin.initialize_app(cred)
    return firestore.client()


def backfill_collection(db, collection_name, *, university_id, dry_run):
    print(f"Backfilling {collection_name}...")
    docs = db.collection(collection_name).stream()
    batch = db.batch()
    pending = 0
    updated = 0

    for doc in docs:
        data = doc.to_dict() or {}
        if data.get("classKey"):
            continue

        title = parse_title(data.get("title") or data.get("name") or "")
        teacher = parse_teacher(data.get("teacher") or "")
        if not title or not teacher:
            continue

        key = build_class_key(title, teacher, university_id)
        updated += 1
        if dry_run:
            print(f"[dry-run] {collection_name}/{doc.id}: {title} / {teacher} -> {key}")
            continue

        batch.update(doc.reference, {"classKey": key, "class_key": key})
        pending += 1
        if pending >= BATCH_SIZE:
            batch.commit()
            batch = db.batch()
            pending = 0
            print(f"Updated {updated} documents...")

    if pending:
        batch.commit()

    print(f"{collection_name}: {updated} documents {'would be ' if dry_run else ''}updated.")


def main():
    parser = argparse.ArgumentParser(
        description="Backfill classKey into syllabus_master and class_reviews."
    )
    parser.add_argument("--service-account", default="serviceAccountKey.json")
    parser.add_argument("--university-id", default=UNIVERSITY_ID)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db = initialize_firebase(args.service_account)
    backfill_collection(
        db, "syllabus_master", university_id=args.university_id, dry_run=args.dry_run
    )
    backfill_collection(
        db, "class_reviews", university_id=args.university_id, dry_run=args.dry_run
    )


if __name__ == "__main__":
    main()

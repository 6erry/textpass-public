import argparse
import json
import os
import re
import sys

from syllabus_identity import (
    UNIVERSITY_ID,
    build_class_key,
    build_syllabus_doc_id,
    clean_text,
    parse_teacher,
    parse_title,
)


COLLECTION_NAME = "syllabus_master"
BATCH_SIZE = 450
firestore = None


def initialize_firebase(service_account_key):
    global firestore
    import firebase_admin
    from firebase_admin import credentials, firestore as firestore_module

    if not os.path.exists(service_account_key):
        print(f"Error: {service_account_key} not found.")
        sys.exit(1)

    if not firebase_admin._apps:
        cred = credentials.Certificate(service_account_key)
        firebase_admin.initialize_app(cred)
    firestore = firestore_module
    return firestore_module.client()


def parse_semester(raw_semester):
    if not raw_semester:
        return "1"

    first_line = clean_text(str(raw_semester).split("\n")[0])
    if "通年" in first_line or "Year" in first_line:
        return "year_round"
    if "集中" in first_line or "Intensive" in first_line:
        return "intensive"
    if "1" in first_line or "前" in first_line or "Spring" in first_line:
        return "1"
    if "2" in first_line or "後" in first_line or "Fall" in first_line:
        return "2"
    return "1"


def parse_schedule(raw_day_period):
    if not raw_day_period:
        return []

    day_map = {
        "月": "Mon",
        "火": "Tue",
        "水": "Wed",
        "木": "Thu",
        "金": "Fri",
        "土": "Sat",
        "日": "Sun",
        "Mon": "Mon",
        "Tue": "Tue",
        "Wed": "Wed",
        "Thu": "Thu",
        "Fri": "Fri",
        "Sat": "Sat",
        "Sun": "Sun",
    }

    schedule_list = []
    seen = set()

    for day, period_start, period_end in re.findall(
        r"(月|火|水|木|金|土|日|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\.?\s*(\d+)(?:\s*[-〜~]\s*(\d+))?",
        raw_day_period,
    ):
        start = int(period_start)
        end = int(period_end or period_start)
        for period in range(start, end + 1):
            item = (day_map[day], period)
            if item not in seen:
                seen.add(item)
                schedule_list.append({"day": item[0], "period": item[1]})

    return schedule_list


def delete_year_documents(db, *, year, university_id):
    from google.cloud.firestore_v1.base_query import FieldFilter

    print(f"Deleting {COLLECTION_NAME} documents for {university_id} / {year}...")
    deleted = 0
    while True:
        docs = list(
            db.collection(COLLECTION_NAME)
            .where(filter=FieldFilter("universityId", "==", university_id))
            .where(filter=FieldFilter("year", "==", year))
            .limit(400)
            .stream()
        )
        if not docs:
            break
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        deleted += len(docs)
        print(f"Deleted {deleted} documents...")
    print("Year replacement cleanup complete.")


def build_doc(entry, *, default_year, university_id):
    title = parse_title(entry.get("title", ""))
    teacher = parse_teacher(entry.get("teacher", ""))
    year = int(entry.get("year") or default_year)
    raw_schedule = entry.get("day_period") or entry.get("raw_day_period") or ""
    semester = parse_semester(entry.get("semester", ""))
    lecture_code = clean_text(entry.get("lct_cd") or entry.get("lecture_code") or "")
    faculty = clean_text(entry.get("faculty") or entry.get("faculty_name") or "")
    subject_type = clean_text(entry.get("subject_type") or entry.get("subject_sort") or "")
    schedule = parse_schedule(raw_schedule)
    class_key = entry.get("classKey") or entry.get("class_key") or build_class_key(
        title, teacher, university_id
    )
    doc_id = entry.get("id") or build_syllabus_doc_id(
        year=year,
        title=title,
        teacher=teacher,
        semester=semester,
        day_period=raw_schedule,
        lecture_code=lecture_code,
        faculty=faculty,
        subject_type=subject_type,
        university_id=university_id,
    )

    doc_data = {
        "id": doc_id,
        "title": title,
        "teacher": teacher,
        "classKey": class_key,
        "class_key": class_key,
        "year": year,
        "semester": semester,
        "schedule": schedule,
        "raw_day_period": raw_schedule,
        "classroom": clean_text(entry.get("classroom", "")),
        "textbook": clean_text(entry.get("textbook", "")),
        "universityId": university_id,
        "source": "hokudai_syllabus",
        "lecture_code": lecture_code,
        "faculty": faculty,
        "subject_type": subject_type,
        "syllabus_url": clean_text(entry.get("syllabus_url", "")),
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    return doc_id, doc_data


def process_and_upload(db, json_path, *, default_year, university_id):
    print(f"Reading {json_path}...")
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    total_count = len(data)
    print(f"Total documents to process: {total_count}")

    batch = db.batch()
    pending = 0
    uploaded = 0
    collection_ref = db.collection(COLLECTION_NAME)

    for entry in data:
        doc_id, doc_data = build_doc(
            entry, default_year=default_year, university_id=university_id
        )
        if not doc_data["title"]:
            continue

        batch.set(collection_ref.document(doc_id), doc_data, merge=True)
        pending += 1

        if pending >= BATCH_SIZE:
            batch.commit()
            uploaded += pending
            print(f"Uploaded {uploaded}/{total_count} documents...")
            batch = db.batch()
            pending = 0

    if pending:
        batch.commit()
        uploaded += pending
        print(f"Uploaded {uploaded}/{total_count} documents...")

    print("Upload complete.")


def main():
    parser = argparse.ArgumentParser(description="Import Hokkaido University syllabus JSON.")
    parser.add_argument("--input", default="hokudai_syllabus_2025_fast.json")
    parser.add_argument("--year", type=int, default=2025)
    parser.add_argument("--university-id", default=UNIVERSITY_ID)
    parser.add_argument("--service-account", default="serviceAccountKey.json")
    parser.add_argument(
        "--replace-year",
        action="store_true",
        help="Delete only the target university/year before importing.",
    )
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"Error: {args.input} not found. Aborting before any Firestore changes.")
        sys.exit(1)
    with open(args.input, "r", encoding="utf-8") as f:
        preview_data = json.load(f)
    if not preview_data:
        print(f"Error: {args.input} is empty. Aborting before any Firestore changes.")
        sys.exit(1)

    db = initialize_firebase(args.service_account)
    if args.replace_year:
        delete_year_documents(db, year=args.year, university_id=args.university_id)
    process_and_upload(
        db,
        args.input,
        default_year=args.year,
        university_id=args.university_id,
    )


if __name__ == "__main__":
    main()

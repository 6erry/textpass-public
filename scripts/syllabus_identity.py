import hashlib
import re
import unicodedata


UNIVERSITY_ID = "hokudai.ac.jp"


def clean_text(value):
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value).replace("\u3000", " ")).strip()


def _clean_lines(value):
    skip_values = {"Japanese", "English", "日本語", "英語"}
    lines = [clean_text(line) for line in str(value).split("\n")]
    lines = [line for line in lines if line and line not in skip_values]
    return lines


def _has_japanese(value):
    return bool(re.search(r"[\u3040-\u30ff\u3400-\u9fff]", value or ""))


def _dedupe_lines(lines):
    result = []
    seen = set()
    for line in lines:
        key = normalize_identity_part(line)
        if key in seen:
            continue
        seen.add(key)
        result.append(line)
    return result


def _drop_translated_second_half(lines):
    if len(lines) < 2 or len(lines) % 2 != 0:
        return lines
    half = len(lines) // 2
    first_half = lines[:half]
    second_half = lines[half:]
    if [normalize_identity_part(x) for x in first_half] == [
        normalize_identity_part(x) for x in second_half
    ]:
        return first_half
    if any(_has_japanese(line) for line in first_half) and not any(
        _has_japanese(line) for line in second_half
    ):
        return first_half
    return lines


def normalize_identity_part(value):
    value = unicodedata.normalize("NFKC", clean_text(value)).lower()
    value = re.sub(r"[‐-―ー－]", "-", value)
    value = re.sub(r"[【】「」『』]", "", value)
    return clean_text(value)


def parse_title(raw_title):
    if not raw_title:
        return ""

    lines = _drop_translated_second_half(_clean_lines(raw_title))
    if not lines:
        return ""

    course_name = lines[0]
    theme_name = ""
    if len(lines) > 1 and _has_japanese(lines[1]):
        theme_name = lines[1]

    if not theme_name and len(lines) > 1 and not _has_japanese(course_name):
        return clean_text(f"{course_name} {lines[1]}")
    return f"{course_name} ({theme_name})" if theme_name else course_name


def parse_teacher(raw_teacher):
    if not raw_teacher:
        return ""

    lines = _drop_translated_second_half(_clean_lines(raw_teacher))
    cleaned_lines = []
    for line in lines:
        cleaned = re.sub(r"\(.*?\)|（.*?）", "", line)
        cleaned = clean_text(cleaned)
        if cleaned:
            cleaned_lines.append(cleaned)
    return clean_text(" ".join(_dedupe_lines(cleaned_lines)))


def build_class_key(title, teacher, university_id=UNIVERSITY_ID):
    source = "|".join(
        [
            normalize_identity_part(university_id),
            normalize_identity_part(title),
            normalize_identity_part(teacher),
        ]
    )
    digest = hashlib.sha1(source.encode("utf-8")).hexdigest()[:20]
    prefix = re.sub(r"[^a-z0-9]+", "_", normalize_identity_part(university_id)).strip("_")
    return f"{prefix}_{digest}"


def build_syllabus_doc_id(
    *,
    year,
    title,
    teacher,
    semester="",
    day_period="",
    lecture_code="",
    faculty="",
    subject_type="",
    university_id=UNIVERSITY_ID,
):
    source = "|".join(
        [
            normalize_identity_part(university_id),
            str(year),
            normalize_identity_part(lecture_code),
            normalize_identity_part(title),
            normalize_identity_part(teacher),
            normalize_identity_part(semester),
            normalize_identity_part(day_period),
            normalize_identity_part(faculty),
            normalize_identity_part(subject_type),
        ]
    )
    return hashlib.md5(source.encode("utf-8")).hexdigest()

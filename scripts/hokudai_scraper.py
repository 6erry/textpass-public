import argparse
import json
import os
import time
import traceback
import urllib.error
import urllib.request

from urllib3.exceptions import ReadTimeoutError
from selenium import webdriver
from selenium.common.exceptions import NoSuchElementException, TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait
from webdriver_manager.chrome import ChromeDriverManager

from syllabus_identity import (
    UNIVERSITY_ID,
    build_class_key,
    build_syllabus_doc_id,
    clean_text,
    parse_teacher,
    parse_title,
)


GAKUMU_BASE_URL = "https://gakumu.academic.hokudai.ac.jp"
SEARCH_URL = f"{GAKUMU_BASE_URL}/Portal/Public/Syllabus/SearchMain.aspx"
PORTAL_URL = "https://www.elms.hokudai.ac.jp/portal/home"
RESULT_TABLE_ID = "ctl00_phContents_ucSylList_gv"


def check_search_url_reachable(timeout):
    request = urllib.request.Request(
        SEARCH_URL,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
            )
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response.read(1)
        return True
    except (TimeoutError, urllib.error.URLError, OSError) as error:
        print(f"Error: 北大シラバス検索ページに接続できませんでした: {error}")
        print("北大VPN・学内ネットワーク・別回線で接続できるか確認してください。")
        return False


def find_visible(driver, selectors):
    for selector in selectors:
        for element in driver.find_elements(By.CSS_SELECTOR, selector):
            if element.is_displayed() and element.is_enabled():
                return element
    return None


def find_visible_text_input(driver):
    return find_visible(
        driver,
        [
            "input[type='email']",
            "input[name='username']",
            "input#username_input",
            "input[type='text']",
        ],
    )


def find_visible_password_input(driver):
    return find_visible(
        driver,
        [
            "input[type='password']",
            "input[name='password']:not([type='hidden'])",
            "input#password_input:not([type='hidden'])",
        ],
    )


def is_fido_page(driver):
    url = driver.current_url.lower()
    if "u2flogin" in url or "fido" in url:
        return True
    body_text = ""
    try:
        body_text = driver.find_element(By.TAG_NAME, "body").text
    except Exception:
        pass
    return "FIDO Authentication" in body_text or "FIDO Login" in body_text


def wait_for_authenticated_page(driver, timeout):
    WebDriverWait(driver, timeout).until(
        lambda d: (
            ("portal" in d.current_url or "gakumu.academic.hokudai.ac.jp" in d.current_url)
            and not find_visible_text_input(d)
            and not find_visible_password_input(d)
        )
        or select_by_suffix(d, "ddl_year")
    )


def wait_for_interactive_auth(driver, *, timeout):
    print("ブラウザで追加認証を完了してください。完了後、自動で続行します。")
    wait_for_authenticated_page(driver, timeout)


def submit_current_form(driver):
    button = find_visible(
        driver,
        [
            "button[type='submit']",
            "input[type='submit']",
            "#login_button",
            ".login_button",
        ],
    )
    if button:
        button.click()
        return
    driver.execute_script("document.querySelector('form')?.submit();")


def login_to_elms(
    driver,
    wait,
    *,
    login_id,
    password,
    otp_wait_seconds,
    allow_interactive,
):
    if not login_id or not password:
        raise SystemExit(
            "Error: ELMS_ID と ELMS_PASSWORD を環境変数で指定してください。"
        )

    print("ELMSポータルへログインしています...")
    driver.get(PORTAL_URL)

    username_input = wait.until(lambda d: find_visible_text_input(d))
    username_input.clear()
    username_input.send_keys(login_id)
    submit_current_form(driver)

    time.sleep(1)
    if is_fido_page(driver):
        if allow_interactive:
            wait_for_interactive_auth(driver, timeout=otp_wait_seconds)
            return
        raise SystemExit(
            "Error: FIDO認証画面に進みました。--headless では通過できないため、"
            "--auth manual を --headless なしで実行してください。"
        )

    try:
        password_input = wait.until(lambda d: find_visible_password_input(d))
    except TimeoutException:
        if is_fido_page(driver):
            raise SystemExit(
                "Error: FIDO認証画面に進みました。--headless では通過できないため、"
                "--auth manual を --headless なしで実行してください。"
            )
        raise

    password_input.clear()
    password_input.send_keys(password)
    submit_current_form(driver)

    try:
        wait_for_authenticated_page(driver, 30)
    except TimeoutException:
        if is_fido_page(driver) or "otp" in driver.current_url.lower() or find_visible(
            driver, ["input[name*='otp']", "input[id*='otp']", "input[type='tel']"]
        ):
            if allow_interactive and otp_wait_seconds > 0:
                wait_for_interactive_auth(driver, timeout=otp_wait_seconds)
                return
            raise SystemExit(
                "Error: 追加認証画面に進みました。--headless では通過できないため、"
                "--auth manual を --headless なしで実行してください。"
            )
        raise


def switch_to_new_window_if_opened(driver, old_handles, timeout=20):
    try:
        WebDriverWait(driver, timeout).until(
            lambda d: len(d.window_handles) > len(old_handles)
        )
        new_handles = [handle for handle in driver.window_handles if handle not in old_handles]
        if new_handles:
            driver.switch_to.window(new_handles[-1])
            return True
    except TimeoutException:
        pass
    return False


def click_link_containing(driver, keywords):
    link = find_link_containing(driver, keywords)
    if not link:
        return None
    driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", link)
    driver.execute_script("arguments[0].click();", link)
    return link


def find_link_containing(driver, keywords):
    for link in driver.find_elements(By.CSS_SELECTOR, "a"):
        text = clean_text(link.text)
        href = link.get_attribute("href") or ""
        onclick = link.get_attribute("onclick") or ""
        haystack = f"{text} {href} {onclick}"
        if any(keyword in haystack for keyword in keywords):
            if link.is_displayed() and link.is_enabled():
                return link
    return None


def open_gakumu_from_elms_portal(driver):
    driver.get(PORTAL_URL)
    wait_for_authenticated_page(driver, 30)
    old_handles = set(driver.window_handles)
    link = click_link_containing(driver, ("学務システム", "redirect/post?site=2"))
    if not link:
        raise NoSuchElementException("ELMSポータルの注目コンテンツにある学務システムリンクを見つけられませんでした。")
    switch_to_new_window_if_opened(driver, old_handles)
    WebDriverWait(driver, 60).until(
        lambda d: "gakumu.academic.hokudai.ac.jp" in d.current_url
        or "北海道大学学務システム" in d.title
    )


def open_syllabus_from_gakumu(driver, wait):
    if select_by_suffix(driver, "ddl_year"):
        return

    old_handles = set(driver.window_handles)
    syllabus_link = click_link_containing(driver, ("シラバス検索", "Syllabus/SearchMain.aspx"))
    if syllabus_link:
        switch_to_new_window_if_opened(driver, old_handles)
        try:
            WebDriverWait(driver, 30).until(lambda d: select_by_suffix(d, "ddl_year"))
            return
        except TimeoutException:
            pass

    course_link = click_link_containing(driver, ("履修・成績情報", "Course grades"))
    if course_link:
        WebDriverWait(driver, 30).until(
            lambda d: find_link_containing(d, ("シラバス検索", "Syllabus/SearchMain.aspx"))
            or select_by_suffix(d, "ddl_year")
        )
        if select_by_suffix(driver, "ddl_year"):
            return
        old_handles = set(driver.window_handles)
        click_link_containing(driver, ("シラバス検索", "Syllabus/SearchMain.aspx"))
        switch_to_new_window_if_opened(driver, old_handles)
        try:
            WebDriverWait(driver, 30).until(lambda d: select_by_suffix(d, "ddl_year"))
            return
        except TimeoutException:
            pass

    driver.get(SEARCH_URL)
    wait.until(lambda d: select_by_suffix(d, "ddl_year"))


def open_syllabus_from_authenticated_portal(driver, wait):
    try:
        open_gakumu_from_elms_portal(driver)
        open_syllabus_from_gakumu(driver, wait)
        return
    except Exception as error:
        print(f"ELMSポータル経由の遷移に失敗しました。シラバス検索URLを直接開きます: {error}")

    open_search_page(driver, wait)


def wait_for_manual_elms_login(driver, *, timeout):
    print("ELMSポータルを開きます。ブラウザでログインを完了してください。")
    driver.get(PORTAL_URL)
    wait_for_authenticated_page(driver, timeout)


def wait_for_page_ready(driver, timeout=30):
    WebDriverWait(driver, timeout).until(
        lambda d: d.execute_script("return document.readyState") == "complete"
    )


def select_value_and_wait(driver, wait, suffix, value):
    select = wait.until(lambda d: select_by_suffix(d, suffix))
    element = select._el
    try:
        current = select.first_selected_option.get_attribute("value")
    except Exception:
        current = None
    if current == value:
        return True
    select.select_by_value(value)
    try:
        WebDriverWait(driver, 10).until(EC.staleness_of(element))
    except TimeoutException:
        pass
    wait_for_page_ready(driver)
    time.sleep(0.5)
    return True


def select_text_if_available(select, text):
    if not select or not text:
        return False
    for option in select.options:
        if clean_text(option.text) == text:
            option.click()
            return True
    return False


def open_search_page(driver, wait, *, retries=2):
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            driver.get(SEARCH_URL)
            wait.until(lambda d: select_by_suffix(d, "ddl_year"))
            return
        except (TimeoutException, ReadTimeoutError) as error:
            last_error = error
            print(f"page load timeout ({attempt}/{retries}); trying window.stop()")
            try:
                driver.execute_script("window.stop();")
                wait.until(lambda d: select_by_suffix(d, "ddl_year"))
                return
            except Exception as stopped_error:
                last_error = stopped_error
                time.sleep(3)
        except Exception as error:
            last_error = error
            time.sleep(3)
    raise last_error


def select_by_suffix(driver, suffix):
    matches = driver.find_elements(By.CSS_SELECTOR, f"select[id$='{suffix}']")
    if not matches:
        return None
    return Select(matches[0])


def click_search(driver):
    candidates = driver.find_elements(By.CSS_SELECTOR, "input[type='submit'], input[type='button']")
    for button in candidates:
        value = button.get_attribute("value") or ""
        button_id = button.get_attribute("id") or ""
        if "検索" in value or button_id.endswith("btnSearch"):
            button.click()
            return
    raise NoSuchElementException("Search button not found")


def safe_select_value(select, value):
    if not select or value is None:
        return False
    try:
        select.select_by_value(value)
        return True
    except Exception:
        return False


def safe_select_text(select, text):
    if not select or not text:
        return False
    try:
        select.select_by_visible_text(text)
        return True
    except Exception:
        return False


def option_pairs(select, include_blank=False):
    if not select:
        return [("", "")]
    pairs = []
    for option in select.options:
        value = option.get_attribute("value") or ""
        text = clean_text(option.text)
        if "ダミー" in text or "選択不可" in text:
            continue
        if include_blank or (value and value.upper() != "NULL"):
            pairs.append((value, text))
    return pairs


def set_max_result_count(driver):
    for element in driver.find_elements(By.TAG_NAME, "select"):
        try:
            select = Select(element)
            options = select.options
            if len(options) < 2:
                continue
            if not any("50" in option.text for option in options):
                continue
            all_option = next((option for option in options if "全件" in option.text), None)
            (all_option or options[-1]).click()
            time.sleep(5)
            return
        except Exception:
            continue


def cell_texts(row):
    cells = row.find_elements(By.CSS_SELECTOR, "th,td")
    return [clean_text(cell.text) for cell in cells]


def find_result_table(driver):
    if driver.find_elements(By.ID, RESULT_TABLE_ID):
        return driver.find_element(By.ID, RESULT_TABLE_ID)

    best_table = None
    best_score = 0
    for table in driver.find_elements(By.TAG_NAME, "table"):
        text = clean_text(table.text)
        score = 0
        for keyword in ("科目", "講義", "教員", "曜日", "時限", "学期"):
            if keyword in text:
                score += 1
        row_count = len(table.find_elements(By.TAG_NAME, "tr"))
        if row_count > 1 and score > best_score:
            best_table = table
            best_score = score
    return best_table if best_score >= 3 else None


def find_column_index(headers, keywords, fallback=None):
    for index, header in enumerate(headers):
        if any(keyword in header for keyword in keywords):
            return index
    return fallback


def extract_rows(driver, *, year, faculty_text="", subject_text=""):
    table = find_result_table(driver)
    if table is None:
        raise NoSuchElementException("Result table not found")
    rows = table.find_elements(By.TAG_NAME, "tr")
    courses = []
    header_index = 0
    header_texts = []
    for index, row in enumerate(rows[:5]):
        texts = cell_texts(row)
        joined = " ".join(texts)
        if "科目" in joined or "講義" in joined or "教員" in joined:
            header_index = index
            header_texts = texts
            break

    title_index = find_column_index(header_texts, ("科目", "講義題目", "授業科目"), 2)
    teacher_index = find_column_index(header_texts, ("教員", "担当"), 3)
    semester_index = find_column_index(header_texts, ("学期", "開講期"), 1)
    day_period_index = find_column_index(header_texts, ("曜日", "時限"), 4)

    for row in rows[header_index + 1:]:
        cells = row.find_elements(By.TAG_NAME, "td")
        if len(cells) <= max(title_index, teacher_index, semester_index, day_period_index):
            continue

        semester = clean_text(cells[semester_index].text)
        raw_title = cells[title_index].text
        raw_teacher = cells[teacher_index].text
        day_period = clean_text(cells[day_period_index].text)
        title = parse_title(raw_title)
        teacher = parse_teacher(raw_teacher)
        if not title:
            continue

        detail_url = ""
        for link in row.find_elements(By.TAG_NAME, "a"):
            href = link.get_attribute("href") or ""
            if href:
                detail_url = href
                break

        doc_id = build_syllabus_doc_id(
            year=year,
            title=title,
            teacher=teacher,
            semester=semester,
            day_period=day_period,
            faculty=faculty_text,
            subject_type=subject_text,
        )
        class_key = build_class_key(title, teacher, UNIVERSITY_ID)

        courses.append(
            {
                "id": doc_id,
                "year": int(year),
                "title": title,
                "teacher": teacher,
                "classKey": class_key,
                "class_key": class_key,
                "semester": semester,
                "day_period": day_period,
                "faculty": faculty_text,
                "subject_type": subject_text,
                "syllabus_url": detail_url,
                "universityId": UNIVERSITY_ID,
            }
        )

    return courses


def search_once(driver, wait, *, year, org_value, subject_text, faculty_value=None):
    if not select_by_suffix(driver, "ddl_year"):
        open_search_page(driver, wait)
    select_value_and_wait(driver, wait, "ddl_year", str(year))

    select_value_and_wait(driver, wait, "ddl_org", org_value)

    faculty_text = faculty_value or ""
    faculty_select = (
        select_by_suffix(driver, "ddl_fac")
        or select_by_suffix(driver, "ddl_faculty")
        or select_by_suffix(driver, "ddl_dept")
        or select_by_suffix(driver, "ddl_gakubu")
    )
    if faculty_select and faculty_value:
        select_value_and_wait(driver, wait, "ddl_fac", faculty_value)
        faculty_select = select_by_suffix(driver, "ddl_fac")
        faculty_text = clean_text(faculty_select.first_selected_option.text)

    subject_select = select_by_suffix(driver, "ddl_sbj_sort")
    selected_subject_text = subject_text
    if subject_text and subject_select:
        subject_element = subject_select._el
        if select_text_if_available(subject_select, subject_text):
            try:
                WebDriverWait(driver, 10).until(EC.staleness_of(subject_element))
            except TimeoutException:
                pass
            wait_for_page_ready(driver)
            time.sleep(0.5)
        else:
            print(f"科目種別が見つからないため、指定なしで検索します: {subject_text}")
            selected_subject_text = ""
    elif subject_text:
        selected_subject_text = ""

    click_search(driver)
    wait_for_page_ready(driver)
    wait.until(lambda d: find_result_table(d))
    set_max_result_count(driver)
    wait.until(lambda d: find_result_table(d))
    return extract_rows(
        driver,
        year=year,
        faculty_text=faculty_text,
        subject_text=selected_subject_text,
    )


def discover_faculty_options(driver, wait, *, year, org_value, subject_text):
    if not select_by_suffix(driver, "ddl_year"):
        open_search_page(driver, wait)
    select_value_and_wait(driver, wait, "ddl_year", str(year))
    select_value_and_wait(driver, wait, "ddl_org", org_value)
    faculty_select = (
        select_by_suffix(driver, "ddl_fac")
        or select_by_suffix(driver, "ddl_faculty")
        or select_by_suffix(driver, "ddl_dept")
        or select_by_suffix(driver, "ddl_gakubu")
    )
    return option_pairs(faculty_select)


def main():
    parser = argparse.ArgumentParser(description="Scrape Hokkaido University syllabus search results.")
    parser.add_argument("--year", default="2026")
    parser.add_argument("--output", default=None)
    parser.add_argument(
        "--auth",
        choices=["public", "elms", "manual"],
        default="public",
        help="public: direct access, elms: login with env vars, manual: finish login in browser.",
    )
    parser.add_argument(
        "--elms-id",
        default=os.environ.get("ELMS_ID") or os.environ.get("ELMS_EMAIL", ""),
        help="ELMS/SSO login ID. Defaults to ELMS_ID, with ELMS_EMAIL kept for compatibility.",
    )
    parser.add_argument("--otp-wait-seconds", type=int, default=180)
    parser.add_argument("--manual-login-timeout", type=int, default=300)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--page-load-timeout", type=int, default=45)
    parser.add_argument("--preflight-timeout", type=int, default=20)
    parser.add_argument(
        "--skip-preflight",
        action="store_true",
        help="Skip the direct connectivity check before launching Chrome.",
    )
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Exit successfully even when no courses are fetched.",
    )
    parser.add_argument(
        "--org",
        default="02",
        help="Course category value. Existing data used 02 for undergraduate/all-campus search.",
    )
    parser.add_argument(
        "--subjects",
        nargs="*",
        default=[""],
        help="Visible texts from ddl_sbj_sort to search. Defaults to no subject filter.",
    )
    parser.add_argument(
        "--all-faculties",
        action="store_true",
        help="Iterate faculty/department options when the page exposes such a select.",
    )
    args = parser.parse_args()

    if (
        args.auth == "public"
        and not args.skip_preflight
        and not check_search_url_reachable(args.preflight_timeout)
    ):
        raise SystemExit(2)
    if args.auth == "manual" and args.headless:
        raise SystemExit("Error: --auth manual は --headless なしで実行してください。")
    if args.auth == "elms" and (not args.elms_id or not os.environ.get("ELMS_PASSWORD", "")):
        raise SystemExit(
            "Error: ELMS_ID と ELMS_PASSWORD を環境変数で指定してください。"
        )

    output = args.output or f"hokudai_syllabus_{args.year}.json"
    options = webdriver.ChromeOptions()
    if args.headless:
        options.add_argument("--headless=new")
    options.add_argument("window-size=1200,900")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.page_load_strategy = "eager"

    driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)
    driver.set_page_load_timeout(args.page_load_timeout)
    wait = WebDriverWait(driver, 30)
    all_courses_by_id = {}

    try:
        if args.auth == "elms":
            login_to_elms(
                driver,
                wait,
                login_id=args.elms_id,
                password=os.environ.get("ELMS_PASSWORD", ""),
                otp_wait_seconds=args.otp_wait_seconds,
                allow_interactive=not args.headless,
            )
            open_syllabus_from_authenticated_portal(driver, wait)
        elif args.auth == "manual":
            wait_for_manual_elms_login(driver, timeout=args.manual_login_timeout)
            open_syllabus_from_authenticated_portal(driver, wait)

        print("========== 北大シラバス取得 ==========")
        subject_labels = args.subjects if any(args.subjects) else ["科目種別指定なし"]
        print(f"year={args.year}, subjects={subject_labels}, all_faculties={args.all_faculties}")

        for subject_text in args.subjects:
            faculty_options = [("", "")]
            if args.all_faculties:
                try:
                    faculty_options = discover_faculty_options(
                        driver,
                        wait,
                        year=args.year,
                        org_value=args.org,
                        subject_text=subject_text,
                    )
                except TimeoutException:
                    print(f"timeout: faculty options unavailable for {subject_text}")
                    faculty_options = []
                if not faculty_options:
                    faculty_options = [("", "")]

            for faculty_value, faculty_text in faculty_options:
                label = subject_text or "科目種別指定なし"
                if faculty_text:
                    label += f" / {faculty_text}"
                print(f"\n--- Search: {label} ---")
                try:
                    courses = search_once(
                        driver,
                        wait,
                        year=args.year,
                        org_value=args.org,
                        subject_text=subject_text,
                        faculty_value=faculty_value,
                    )
                    for course in courses:
                        all_courses_by_id[course["id"]] = course
                    print(f"found={len(courses)}, total_unique={len(all_courses_by_id)}")
                except TimeoutException:
                    print("timeout: no result table")
                except Exception:
                    traceback.print_exc()
    finally:
        driver.quit()

    all_courses = list(all_courses_by_id.values())
    with open(output, "w", encoding="utf-8") as f:
        json.dump(all_courses, f, ensure_ascii=False, indent=2)

    print(f"\n完了: {len(all_courses)} 件を保存しました: {output}")
    if not all_courses and not args.allow_empty:
        print("Error: 0 件でした。サイト接続や検索条件を確認してください。")
        raise SystemExit(2)


if __name__ == "__main__":
    main()

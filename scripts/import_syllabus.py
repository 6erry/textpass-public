import pandas as pd
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import uuid

# --- 設定 ---
JSON_PATH = 'serviceAccountKey.json'  # ダウンロードした秘密鍵のファイル名
CSV_PATH = 'hokudai_syllabus_2025.csv'
COLLECTION_NAME = 'syllabus_master'  # シラバスデータを格納するコレクション名

# --- 初期化 ---
if not firebase_admin._apps:
    cred = credentials.Certificate(JSON_PATH)
    firebase_admin.initialize_app(cred)
db = firestore.client()

# --- データ変換関数 ---
def parse_semester(sem_text):
    """CSVの学期表記をシステム用のコードに変換"""
    sem_text = str(sem_text).strip()
    if '１学期' in sem_text:
        if '春ターム' in sem_text: return 'spring'
        if '夏ターム' in sem_text: return 'summer'
        return '1' # 1学期（前期）
    elif '２学期' in sem_text:
        if '秋ターム' in sem_text: return 'fall'
        if '冬ターム' in sem_text: return 'winter'
        return '2' # 2学期（後期）
    elif sem_text == '集中':
        return 'intensive'
    return 'unknown'

def parse_day_period(dp_text):
    """'月3' などを day='Mon', period=3 に変換"""
    dp_text = str(dp_text).strip()
    
    # 曜日マッピング
    day_map = {'月': 'Mon', '火': 'Tue', '水': 'Wed', '木': 'Thu', '金': 'Fri', '土': 'Sat', '日': 'Sun'}
    
    day = 'Unknown'
    for k, v in day_map.items():
        if k in dp_text:
            day = v
            break
            
    # 時限抽出（数字を探す）
    period = 0
    import re
    match = re.search(r'\d+', dp_text)
    if match:
        period = int(match.group())
    
    return day, period

# --- メイン処理 ---
def main():
    print("CSVを読み込んでいます...")
    df = pd.read_csv(CSV_PATH)
    
    # ゴミデータの除去（ページネーションの数字などが混ざっている場合）
    # 曜日が入っていない、かつ「集中」でもない、かつ短いデータは除外
    valid_rows = []
    for _, row in df.iterrows():
        dp = str(row['day_period'])
        if any(d in dp for d in ['月','火','水','木','金','土','日']) or '集中' in dp:
            valid_rows.append(row)
    
    print(f"有効なデータ件数: {len(valid_rows)} / {len(df)}")
    
    batch = db.batch()
    count = 0
    
    for row in valid_rows:
        day, period = parse_day_period(row['day_period'])
        semester = parse_semester(row['semester'])
        
        # ドキュメントIDを生成（重複しないようにUUIDを使用、または title_instructor などでハッシュ化も可）
        doc_id = str(uuid.uuid4())
        
        doc_data = {
            'title': row['course_name'],
            'teacher': row['instructor'],
            'day': day,
            'period': period,
            'semester': semester,
            'universityId': row['universityId'],
            'textbook': '', # CSVにない場合は空
            'room': '',     # CSVにない場合は空
            'createdAt': firestore.SERVER_TIMESTAMP,
            'raw_semester': row['semester'], # 元の表記も念のため残す
            'raw_day_period': row['day_period']
        }
        
        doc_ref = db.collection(COLLECTION_NAME).document(doc_id)
        batch.set(doc_ref, doc_data)
        count += 1
        
        # 500件ごとにコミット（Firestoreの制限）
        if count % 500 == 0:
            batch.commit()
            print(f"{count}件 登録完了...")
            batch = db.batch()
            
    # 残りをコミット
    if count % 500 != 0:
        batch.commit()
        
    print(f"完了！合計 {count} 件のシラバスデータを登録しました。")

if __name__ == "__main__":
    main()
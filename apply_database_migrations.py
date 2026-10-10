import os
import sys
from pathlib import Path

import psycopg2

DB_HOST = os.getenv('PG_HOST', 'localhost')
DB_PORT = int(os.getenv('PG_PORT', '5432'))
DB_NAME = os.getenv('PG_DATABASE', 'Customs_SR_DB')
DB_USER = os.getenv('PG_USER', 'postgres')
DB_PASSWORD = os.getenv('PG_PASSWORD', 'postgres')

TARGETS = sys.argv[1:] or [
    'postgres/01_auth_and_session.sql',
    'postgres/02_schema.sql',
    'postgres/04_auth.sql',
]

conn = psycopg2.connect(
    host=DB_HOST,
    port=DB_PORT,
    dbname=DB_NAME,
    user=DB_USER,
    password=DB_PASSWORD,
)
conn.autocommit = True

try:
    with conn.cursor() as cur:
        for target in TARGETS:
            path = Path(target)
            if not path.exists():
                alt = Path('postgres') / target
                if alt.exists():
                    path = alt
                else:
                    raise FileNotFoundError(f'Could not find SQL file: {target}')

            sql = path.read_text(encoding='utf-8')
            print(f'Applying {path}...')
            cur.execute(sql)
            print(f'Applied {path}')
finally:
    conn.close()

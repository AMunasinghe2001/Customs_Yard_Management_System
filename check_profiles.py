import psycopg2

conn = psycopg2.connect(
    host='localhost',
    port=5432,
    dbname='Customs_SR_DB',
    user='postgres',
    password='postgres'
)
conn.autocommit = True

try:
    with conn.cursor() as cur:
        cur.execute(
            "select id, role from public.profiles where role not in ('admin','officer') limit 20"
        )
        rows = cur.fetchall()
        for row in rows:
            print(f"ID: {row[0]}, Role: {row[1]}")
        print(f"Total invalid roles: {len(rows)}")
finally:
    conn.close()

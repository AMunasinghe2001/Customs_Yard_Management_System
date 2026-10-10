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
        # Fix invalid roles: map old department roles to 'officer' or 'admin'
        # For now, all department-specific roles become 'officer'
        cur.execute(
            "update public.profiles set role = 'officer' where role in ('executive', 'ict', 'appeal', 'valuation', 'disposal')"
        )
        print("Fixed invalid profile roles")
finally:
    conn.close()

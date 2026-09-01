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
        # Check which accounts have passwords
        cur.execute("""
            select email, encrypted_password is not null as has_password
            from auth.users
            order by email
        """)
        rows = cur.fetchall()
        print(f"Account password status:")
        for email, has_pw in rows:
            status = "✓ HAS PASSWORD" if has_pw else "✗ NO PASSWORD"
            print(f"  {email}: {status}")
        
        # Count accounts without passwords
        cur.execute("""
            select count(*) from auth.users where encrypted_password is null
        """)
        no_pw_count = cur.fetchone()[0]
        print(f"\nAccounts without password: {no_pw_count} / {len(rows)}")
finally:
    conn.close()

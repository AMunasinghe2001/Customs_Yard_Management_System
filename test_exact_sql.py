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
        # This is the EXACT SQL syntax the app uses
        print("Testing exact SQL syntax from pg_auth.dart:")
        print("SQL: select id, email, meta, email_confirmed_at from auth.sign_in(?, ?)")
        print("Params: ('anushangamunasinghe@gmail.com', password)")
        
        try:
            cur.execute(
                "select id, email, meta, email_confirmed_at from auth.sign_in(%s, %s)",
                ('anushangamunasinghe@gmail.com', 'test123')
            )
            result = cur.fetchall()
            print(f"Success: {result}")
        except psycopg2.Error as e:
            print(f"Error: {e.pgerror if hasattr(e, 'pgerror') else e}")
            print(f"Error code: {e.pgcode if hasattr(e, 'pgcode') else 'N/A'}")

finally:
    conn.close()

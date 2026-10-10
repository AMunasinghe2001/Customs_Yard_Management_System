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
        # Try calling auth.sign_in with known credentials
        test_email = 'anushanga@gmail.com'
        test_password = 'test-password'
        
        print(f"Testing auth.sign_in('{test_email}', '****')")
        try:
            cur.execute(
                "select * from auth.sign_in(%s, %s)",
                (test_email, test_password)
            )
            result = cur.fetchone()
            print(f"Result: {result}")
        except Exception as e:
            print(f"Error: {type(e).__name__}: {e}")
            
        # Try a simpler query
        print("\nTesting direct auth.users query:")
        try:
            cur.execute("select id, email from auth.users limit 1")
            result = cur.fetchone()
            print(f"Result: {result}")
        except Exception as e:
            print(f"Error: {type(e).__name__}: {e}")
finally:
    conn.close()

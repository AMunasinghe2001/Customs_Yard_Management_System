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
        # Check the default search_path
        cur.execute("SHOW search_path")
        search_path = cur.fetchone()[0]
        print(f"Default search_path: {search_path}")
        
        # Test 1: Call sign_in without explicit schema (might fail)
        print("\n1. SELECT from auth.sign_in() without setting search_path:")
        try:
            cur.execute("SELECT * FROM auth.sign_in(%s, %s)", ('deepal@gmail.com', 'test123'))
            result = cur.fetchall()
            print(f"   Success: {result}")
        except psycopg2.Error as e:
            print(f"   Error: {e.pgerror if hasattr(e, 'pgerror') else e}")
        
        # Test 2: Set search_path first
        print("\n2. Set search_path to 'auth, public' then call sign_in():")
        try:
            cur.execute("SET search_path TO auth, public")
            cur.execute("SELECT * FROM auth.sign_in(%s, %s)", ('deepal@gmail.com', 'test123'))
            result = cur.fetchall()
            print(f"   Success: {result}")
        except psycopg2.Error as e:
            print(f"   Error: {e.pgerror if hasattr(e, 'pgerror') else e}")
        
        # Test 3: Reset and try with explicit schema in FROM
        cur.execute("RESET search_path")
        print("\n3. Reset search_path and call auth.sign_in() with explicit schema:")
        try:
            cur.execute("SELECT * FROM auth.sign_in(%s, %s)", ('deepal@gmail.com', 'test123'))
            result = cur.fetchall()
            print(f"   Success: {result}")
        except psycopg2.Error as e:
            print(f"   Error: {e.pgerror if hasattr(e, 'pgerror') else e}")

finally:
    conn.close()

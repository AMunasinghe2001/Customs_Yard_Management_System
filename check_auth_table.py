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
        # Check if auth schema exists
        cur.execute("select schema_name from information_schema.schemata where schema_name='auth'")
        auth_exists = cur.fetchone() is not None
        print(f"Auth schema exists: {auth_exists}")
        
        # Check if auth.users table exists
        cur.execute("""
            select table_name from information_schema.tables 
            where table_schema='auth' and table_name='users'
        """)
        users_exists = cur.fetchone() is not None
        print(f"Auth.users table exists: {users_exists}")
        
        # List all tables in auth schema
        cur.execute("""
            select table_name from information_schema.tables 
            where table_schema='auth' order by table_name
        """)
        tables = [row[0] for row in cur.fetchall()]
        print(f"Auth tables: {tables}")
        
        if not users_exists:
            print("\nERROR: auth.users table is missing!")
            print("Need to run 01_auth_and_session.sql")
finally:
    conn.close()

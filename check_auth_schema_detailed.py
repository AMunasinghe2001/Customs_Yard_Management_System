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
        cur.execute("""
            select exists(select 1 from information_schema.schemata where schema_name = 'auth')
        """)
        auth_schema_exists = cur.fetchone()[0]
        print(f"Auth schema exists: {auth_schema_exists}")
        
        # List all tables in auth schema
        cur.execute("""
            select table_name from information_schema.tables where table_schema = 'auth'
        """)
        tables = cur.fetchall()
        print(f"\nTables in auth schema: {len(tables)}")
        for (table_name,) in tables:
            print(f"  - {table_name}")
        
        # List all functions in auth schema
        cur.execute("""
            select proname, oid from pg_proc 
            where pronamespace = (select oid from pg_namespace where nspname = 'auth')
            order by proname
        """)
        functions = cur.fetchall()
        print(f"\nFunctions in auth schema: {len(functions)}")
        for proname, oid in functions:
            print(f"  - {proname} (oid={oid})")
        
        # Test calling sign_in with a valid call
        print("\nTesting auth.sign_in('deepal@gmail.com', 'test123'):")
        try:
            cur.execute("""
                select id, email from auth.sign_in(%s, %s)
            """, ('deepal@gmail.com', 'test123'))
            result = cur.fetchall()
            print(f"  Result: {result}")
        except Exception as e:
            print(f"  Error: {e}")
        
        # Try selecting directly from auth.users
        print("\nTesting direct select from auth.users:")
        try:
            cur.execute("select count(*) from auth.users")
            count = cur.fetchone()[0]
            print(f"  Count: {count}")
        except Exception as e:
            print(f"  Error: {e}")

finally:
    conn.close()

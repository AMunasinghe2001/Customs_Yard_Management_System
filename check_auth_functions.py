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
        # Check auth functions
        cur.execute("""
            select routine_name, routine_type 
            from information_schema.routines 
            where routine_schema='auth'
            order by routine_name
        """)
        funcs = cur.fetchall()
        print(f"Auth functions: {len(funcs)}")
        for name, rtype in funcs:
            print(f"  - {name} ({rtype})")
        
        # Check if sign_in function exists specifically
        cur.execute("""
            select count(*) from information_schema.routines 
            where routine_schema='auth' and routine_name='sign_in'
        """)
        sign_in_exists = cur.fetchone()[0] > 0
        print(f"\nauth.sign_in() exists: {sign_in_exists}")
        
        # Check auth.users columns
        cur.execute("""
            select column_name, data_type 
            from information_schema.columns 
            where table_schema='auth' and table_name='users'
            order by ordinal_position
        """)
        cols = cur.fetchall()
        print(f"\nauth.users columns: {len(cols)}")
        for name, dtype in cols:
            print(f"  - {name}: {dtype}")
        
        # Check if there are any users
        cur.execute("select count(*) from auth.users")
        user_count = cur.fetchone()[0]
        print(f"\nUsers in auth.users: {user_count}")
        
        if user_count > 0:
            cur.execute("select id, email from auth.users limit 5")
            for uid, email in cur.fetchall():
                print(f"  - {email} (ID: {uid})")
finally:
    conn.close()

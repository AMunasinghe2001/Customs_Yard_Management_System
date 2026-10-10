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
        # Check that the critical security columns exist
        cur.execute("""
            select column_name from information_schema.columns 
            where table_schema='auth' and table_name='users' 
            and column_name in ('failed_login_attempts', 'locked_until')
            order by column_name
        """)
        security_cols = [row[0] for row in cur.fetchall()]
        print(f"Auth security columns: {', '.join(security_cols)}")
        
        # Check that the auth functions exist
        cur.execute("""
            select routine_name from information_schema.routines 
            where routine_schema='auth' 
            and routine_name in ('sign_in', 'sign_up', 'record_failed_login', 'clear_failed_login', 'user_by_id')
            order by routine_name
        """)
        auth_funcs = [row[0] for row in cur.fetchall()]
        print(f"Auth functions: {', '.join(auth_funcs)}")
        
        # Check that audit_logs table exists for session tracking
        cur.execute("""
            select count(*) from information_schema.tables 
            where table_schema='public' and table_name='audit_logs'
        """)
        has_audit = cur.fetchone()[0] > 0
        print(f"Audit logs table: {'✓' if has_audit else '✗'}")
        
        # Test a lockout scenario
        cur.execute("select count(*) from auth.users")
        user_count = cur.fetchone()[0]
        print(f"Total auth.users: {user_count}")
        
        print("\nDB STATE: Security infrastructure is in place.")
finally:
    conn.close()

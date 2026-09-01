import psycopg2
import bcrypt
from datetime import datetime, timezone

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
        # Let me test signing in with a known account
        # First, let's set a known password for a test account
        test_email = 'deepal@gmail.com'
        test_password = 'Test@1234'
        
        print(f"Setting password for {test_email} to '{test_password}'")
        
        # Use auth.sign_up to create/update the account with a known password
        cur.execute("""
            select * from auth.sign_up(%s, %s, %s)
        """, (test_email, test_password, '{}'))
        
        result = cur.fetchall()
        print(f"Sign up result: {result}")
        
        # Now test signing in with that password
        print(f"\nNow trying to sign in with {test_email} and password...")
        cur.execute("""
            select id, email from auth.sign_in(%s, %s)
        """, (test_email, test_password))
        
        result = cur.fetchall()
        if result:
            print(f"SUCCESS: Logged in! User ID: {result[0][0]}")
        else:
            print("FAILED: No match (wrong password)")

finally:
    conn.close()

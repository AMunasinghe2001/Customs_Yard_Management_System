# admin-officers — setup

Edge Function that lets an **admin** create officer accounts without losing
their own session. It generates a random username + password and emails the
credentials to the officer (via [Resend](https://resend.com)).

Flow (from Admin → Officers → **Add Officer**):

1. `request-otp` — emails a 6-digit code to the officer's email.
2. `verify-create` — verifies the code, creates the auth user with the
   service-role key, writes the profile, and emails the username + password.

## 1. Run the SQL migration

In the Supabase SQL editor, run:

```
db/migrations/20260609_officer_username_auth.sql
```

This adds `profiles.username`, the `officer_signup_otps` table, and the
`email_for_login(identifier)` RPC used for **username-or-email login**.

> Run order overall: `db/schema.sql` → `db/migrations/*.sql`
> (including this one) → `migrations/001_multi_yard.sql` →
> `migrations/002_strict_yard_isolation.sql`.

## 2. Set the email secrets

Create a Resend account, verify a sending domain/address, then:

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxxxx
supabase secrets set RESEND_FROM="SL Customs <noreply@yourdomain.lk>"
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically — do **not** set them.

> If `RESEND_API_KEY` is missing, the OTP step fails. After the account is
> created, if the credential email fails the app shows the username/password
> on screen so the admin can hand them over manually.

## 3. Deploy

```bash
supabase functions deploy admin-officers
```

The function requires the caller to be an authenticated **admin** (it checks
`profiles.role = 'admin'` from the caller's JWT) and uses the calling admin's
`yard` for the new officer.

## Notes

- SMS OTP is intentionally not used — verification is email-only.
- The TypeScript "Cannot find Deno / esm.sh" editor errors are expected; this
  code runs on the Supabase Deno runtime, not Node.

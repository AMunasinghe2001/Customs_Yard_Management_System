# Email OTP code (not a Magic Link)

Admin sign-up uses Supabase's built-in email OTP (`signInWithOtp`). By default
Supabase emails a **Magic Link** (a clickable "Log In" link) instead of a
6-digit code. The link vs. code is decided entirely by the **email template**,
which is dashboard config — it cannot be changed from app code.

## Make Supabase send a 6-digit code

Supabase Dashboard → **Authentication → Email Templates**. Edit the **Magic Link**
template (and, to be safe, **Confirm signup**) and make sure the body contains
the token `{{ .Token }}` instead of the link `{{ .ConfirmationURL }}`:

```html
<h2>Your sign-in code</h2>
<p>Enter this 6-digit code to continue:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>This code expires shortly. If you didn't request it, ignore this email.</p>
```

Save. New emails will now show the code (e.g. `123456`) instead of a link.

> The app verifies the code with `OtpType.email` and falls back to
> `signup`/`magiclink`, so it works regardless of which template fires.

## (Optional) Match the 2-minute window

The Admin Sign-Up screen shows a 2-minute countdown and a "Resend" button
(2 resends, then a 2-hour lock). To make the **actual** code expire in 2 minutes,
set Supabase Dashboard → **Authentication → Providers → Email → Email OTP
Expiration** to `120` seconds. (Leaving the default just means the code stays
valid a bit longer than the on-screen timer — harmless.)

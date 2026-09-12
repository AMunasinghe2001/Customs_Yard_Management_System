// ============================================================================
//  admin-officers  —  Supabase Edge Function (service_role)
//
//  Lets an authenticated ADMIN create officer accounts without losing their own
//  session. Two actions:
//
//    1. "request-otp"   { email, fullName, mobileNumber, badgeNumber }
//         → generates a 6-digit code, stores the pending officer in
//           officer_signup_otps, and emails the code to the officer.
//
//    2. "verify-create" { email, otp }
//         → verifies the code, creates the auth user with a random password,
//           generates a unique username, writes the profile and emails the
//           username + password to the officer.
//
//  Required secrets (Project Settings → Edge Functions → Secrets):
//    RESEND_API_KEY   — Resend API key (https://resend.com)
//    RESEND_FROM      — verified sender, e.g. "SL Customs <noreply@yourdomain>"
//  SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
//  Deploy:  supabase functions deploy admin-officers
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM = Deno.env.get("RESEND_FROM") ?? "SL Customs <onboarding@resend.dev>";

const OTP_TTL_MINUTES = 10;
const MAX_OTP_ATTEMPTS = 5;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function randomOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function randomPassword(len = 12): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnpqrstuvwxyz";
  const digits = "23456789";
  const symbols = "@#%&*!?";
  const all = upper + lower + digits + symbols;
  const pick = (set: string) => set[Math.floor(Math.random() * set.length)];
  // Guarantee at least one of each class, then fill the rest.
  let pw = pick(upper) + pick(lower) + pick(digits) + pick(symbols);
  for (let i = pw.length; i < len; i++) pw += pick(all);
  // Shuffle
  return pw.split("").sort(() => Math.random() - 0.5).join("");
}

function slug(s: string): string {
  return (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) {
    throw new Error("Email service not configured (RESEND_API_KEY missing).");
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: RESEND_FROM, to, subject, html }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Email send failed: ${res.status} ${detail}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // ── Authenticate caller and require admin ─────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "Not authenticated" }, 401);
  }
  const { data: adminProfile } = await service
    .from("profiles")
    .select("role, yard")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!adminProfile || adminProfile.role !== "admin") {
    return json({ error: "Only admins can create officers." }, 403);
  }
  const officerYard: string | null = adminProfile.yard ?? null;

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const action = String(payload.action ?? "");

  // ── Action: request-otp ───────────────────────────────────────────────────
  if (action === "request-otp") {
    const email = String(payload.email ?? "").trim().toLowerCase();
    const fullName = String(payload.fullName ?? "").trim();
    const mobileNumber = String(payload.mobileNumber ?? "").trim();
    const badgeNumber = String(payload.badgeNumber ?? "").trim();

    if (!email || !email.includes("@")) {
      return json({ error: "A valid email is required." }, 400);
    }
    if (!fullName) return json({ error: "Full name is required." }, 400);

    // Note: duplicate-email is enforced at createUser time (verify-create).
    const otp = randomOtp();
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000)
      .toISOString();

    const { error: upsertErr } = await service
      .from("officer_signup_otps")
      .upsert({
        email,
        otp,
        full_name: fullName,
        badge_number: badgeNumber || null,
        mobile_number: mobileNumber || null,
        yard: officerYard,
        attempts: 0,
        expires_at: expiresAt,
        created_at: new Date().toISOString(),
      });
    if (upsertErr) return json({ error: upsertErr.message }, 500);

    try {
      await sendEmail(
        email,
        "Your SL Customs verification code",
        `<div style="font-family:Arial,sans-serif">
           <h2>Sri Lanka Customs — SR Management System</h2>
           <p>Hello ${fullName},</p>
           <p>Your verification code is:</p>
           <p style="font-size:28px;font-weight:bold;letter-spacing:4px">${otp}</p>
           <p>This code expires in ${OTP_TTL_MINUTES} minutes.</p>
         </div>`,
      );
    } catch (e) {
      return json({ error: String((e as Error).message) }, 502);
    }

    return json({ ok: true });
  }

  // ── Action: verify-create ─────────────────────────────────────────────────
  if (action === "verify-create") {
    const email = String(payload.email ?? "").trim().toLowerCase();
    const otp = String(payload.otp ?? "").trim();
    if (!email || !otp) return json({ error: "Email and OTP are required." }, 400);

    const { data: row } = await service
      .from("officer_signup_otps")
      .select("*")
      .eq("email", email)
      .maybeSingle();

    if (!row) return json({ error: "No pending request for this email." }, 404);
    if (new Date(row.expires_at).getTime() < Date.now()) {
      await service.from("officer_signup_otps").delete().eq("email", email);
      return json({ error: "The code has expired. Please resend." }, 400);
    }
    if ((row.attempts ?? 0) >= MAX_OTP_ATTEMPTS) {
      await service.from("officer_signup_otps").delete().eq("email", email);
      return json({ error: "Too many attempts. Please resend a new code." }, 400);
    }
    if (row.otp !== otp) {
      await service
        .from("officer_signup_otps")
        .update({ attempts: (row.attempts ?? 0) + 1 })
        .eq("email", email);
      return json({ error: "Invalid code. Please try again." }, 400);
    }

    // ── Generate a unique username ──────────────────────────────────────────
    const parts = String(row.full_name).trim().split(/\s+/);
    const base = (slug(parts[0]) + (parts[1] ? "." + slug(parts[1]) : "")) ||
      "officer";
    let username = "";
    for (let i = 0; i < 12; i++) {
      const candidate = i === 0
        ? `${base}${Math.floor(100 + Math.random() * 900)}`
        : `${base}${Math.floor(1000 + Math.random() * 9000)}`;
      const { data: clash } = await service
        .from("profiles")
        .select("id")
        .ilike("username", candidate)
        .maybeSingle();
      if (!clash) {
        username = candidate;
        break;
      }
    }
    if (!username) username = `officer${Date.now()}`;

    const password = randomPassword();

    // ── Create the auth user (service_role; admin keeps their own session) ──
    const { data: created, error: createErr } = await service.auth.admin
      .createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: row.full_name,
          role: "officer",
          badge_number: row.badge_number,
          mobile_number: row.mobile_number,
          yard: row.yard,
          username,
        },
      });
    if (createErr || !created?.user) {
      const msg = createErr?.message ?? "Could not create user.";
      if (msg.toLowerCase().includes("already")) {
        return json({ error: "This email is already registered." }, 409);
      }
      return json({ error: msg }, 500);
    }

    // ── Write/Upsert the profile row ────────────────────────────────────────
    const { error: profileErr } = await service.from("profiles").upsert({
      id: created.user.id,
      full_name: row.full_name,
      username,
      badge_number: row.badge_number,
      mobile_number: row.mobile_number,
      role: "officer",
      is_active: true,
      yard: row.yard,
    });
    if (profileErr) {
      // Roll back the auth user so the admin can retry cleanly.
      await service.auth.admin.deleteUser(created.user.id);
      return json({ error: profileErr.message }, 500);
    }

    // ── Email the credentials ───────────────────────────────────────────────
    try {
      await sendEmail(
        email,
        "Your SL Customs account is ready",
        `<div style="font-family:Arial,sans-serif">
           <h2>Sri Lanka Customs — SR Management System</h2>
           <p>Hello ${row.full_name},</p>
           <p>An administrator has created your officer account. Use these
              credentials to sign in:</p>
           <table style="border-collapse:collapse;margin:12px 0">
             <tr><td style="padding:4px 12px"><b>Username</b></td>
                 <td style="padding:4px 12px">${username}</td></tr>
             <tr><td style="padding:4px 12px"><b>Password</b></td>
                 <td style="padding:4px 12px">${password}</td></tr>
           </table>
           <p>You can sign in with your <b>username or email</b>. Please change
              your username and password from <b>Edit Profile</b> after your
              first login.</p>
         </div>`,
      );
    } catch (e) {
      // Account exists but the email failed — surface so the admin can relay
      // the credentials manually. Include them in the response for that case.
      return json({
        ok: true,
        emailed: false,
        username,
        password,
        warning: String((e as Error).message),
      });
    }

    await service.from("officer_signup_otps").delete().eq("email", email);
    return json({ ok: true, emailed: true, username });
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});

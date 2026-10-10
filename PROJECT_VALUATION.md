# SR Management System — What to Ask Customs For

*A pricing estimate built from the repository itself, not from receipts. Read the disclaimer before you use any number here.*

---

## Read this first

These are estimate ranges from analysing the repository (commit history, lines of code, migration count, schema size) and the facts you gave me about how this project came about — not a quote, invoice audit, or legal valuation. I don't know your actual out-of-pocket costs, and I don't know Customs' procurement rules, any prior budget figure, or a ceiling — no one has stated any of those directly. Use this as your **opening negotiating position**, and adjust once Customs responds with a number or a process of their own.

---

## 1 · How this project actually happened

This matters more than anything else in the pricing, because it changes what you're really selling: not a speculative build, but a solution to a problem Customs already knew it had and had already set money aside to fix.

**A known problem, with budget already behind it.**
The workflow this system now runs — seizure, warehousing, appeal, valuation, tender, disposal — had been a standing operational pain point at Customs for a long time. Money had reportedly already been allocated toward solving it, and no solution had been delivered.

**You started small, for one yard.**
On one officer's encouragement, you built a first version scoped to a single yard's own work — no directorate portals, just making that yard's day-to-day easier.

**A second officer said the narrow version wasn't enough.**
Shown the yard-only build, another senior officer judged it wouldn't actually solve the problem at that scale — the whole seizure-to-disposal process needed to be in one system, not just one yard's slice of it.

**The full system is what got built.**
What exists today — all seven portals, the tender/committee workflow, the security hardening — is the result of that push: the complete process, not the original narrow scope.

---

## 2 · The numbers behind the estimate

| Metric | Value |
|---|---|
| Lines of Dart | ~118,000 |
| Commits | 445 |
| Development span | 6.5 months (Mar – Sep 2026) |
| Portals / roles | 7 |
| Database migrations | 48 |
| Row-Level Security policies | 153 |

Context that shapes the price, not just the code:

- No company — this is you, personally.
- No written agreement yet.
- Solving a known, previously-budgeted problem.
- Scope grew on a second officer's push, not speculative feature creep.
- An independent audit already found the system works well.

---

## 3 · Why this changes the number

**Customs already valued this problem.**
If budget was previously set aside to solve this and never delivered, that figure is itself a reference point — you're not introducing a new cost, you're finally fulfilling a spend they already planned for.

**No contract exists yet.**
Nothing was signed committing you to a price, timeline, or scope. **You set the opening number** — Customs is responding to your first offer, not negotiating you down from an existing one.

**You're the only person who can maintain it.**
RLS policies, trigger logic, the tender/committee workflow — none of it is documented for a stranger to pick up cold. Whoever inherits this without you spends months just reading it before touching it.

**Officially it's informal.**
No purchase order, no procurement trail, no signed IP assignment. Get terms in writing before handover, not after — even though two officers already backed the full build.

---

## 4 · What it would have cost Customs to commission this

Not what you spent — what a vendor would have charged Customs to build the same scope from a blank repository. This is your **ceiling reference**, not your ask.

**Method A — Effort × market day-rate: ≈ LKR 2.1M – 4.2M**
~130 working days of visible commit activity across 6.5 months, at a freelance/small-shop Flutter+PostgreSQL rate for this skill level (RLS design, trigger-based workflow engines, and financial calculations are senior work, not junior CRUD) — roughly LKR 16,000–32,000/day equivalent.

**Method B — Comparable government-scale system: ≈ LKR 3.5M – 7M**
Multi-role workflow software with a custom backend and this level of security hardening (RLS + audit trail + device gating) typically tenders in this band from a small Sri Lankan dev shop, before any agency markup. This project sits upper-middle of that band on line count and security surface alone.

> **What a vendor would have billed Customs: LKR 3,000,000 – 6,000,000**
> This is the market ceiling, not your number — see §5 for what to actually ask.

---

## 5 · What to actually ask for

You said LKR 3M–6M "felt too big" — that instinct is about your comfort asking a Customs officer for a large number, not about whether the software is worth it. Given a real, budgeted problem finally solved, it is worth it.

### Recommendation — IP ownership

Do a **full, clean transfer of ownership** to Customs, priced into the upfront fee, rather than holding a licence over a government system indefinitely. A department can't easily run compliance-grade software on code it doesn't own outright — audits, future contractors, and procurement all want clear title. Transfer it, and charge properly for the transfer itself.

### Recommendation — who maintains it

Try to stay on as maintainer yourself, on a monthly or annual retainer. You already hold months of undocumented context a new IT hire would have to rebuild from scratch. That knowledge is a second product on top of the code — sell it separately, don't give it away inside the handover fee.

### Suggested pricing structure

| Component | What it covers | Suggested range (LKR) |
|---|---|---|
| **Handover fee — full IP transfer** | Complete ownership transfer, source + database schema, install on the office server, training across all 7 portals, first device-approval rollout, a short written agreement covering the transfer itself. | **3,000,000 – 5,500,000** |
| **Monthly maintenance retainer** | Bug fixes, minor changes, backups & monitoring, being reachable for the office, security patching. | **45,000 – 85,000 / mo** |
| **Annual support contract** (alt. to monthly) | Same scope, paid yearly — easier for a government budget cycle to approve as one line item. | **450,000 – 850,000 / yr** |
| **Major feature work** | New portals, new report types, integration with another government system — scoped and quoted per request, outside the retainer. | Quoted per feature |

> **Opening ask — handover fee: LKR 4,000,000**
> Anchor here. It sits inside the market range in §4, leaves room to negotiate down toward 3M if pushed, and reflects that you're the only person who can support what you built.

---

## 6 · How to run the conversation

**Get something in writing first.**
Even a one-page letter of intent or a written approval from the two officers who backed this, before you name a final figure. It converts an informal effort into a recognised engagement and protects you either way.

**Lead with the problem and the audit, not the code.**
Frame it as: "this is the fix for the problem you'd already budgeted for, and an independent audit confirmed it works." That sentence moves a procurement or finance decision — your repository does not.

**Separate "done" from "supported".**
Be explicit that the handover fee buys the system as it stands today, including the gaps in §7 below — ongoing support is a different line item they're choosing separately, not something bundled in for free.

**Anchor high, flex on cash flow.**
Government budget cycles resist new monthly commitments more than one-time capital spend. If they push back on the retainer, offer to lower the monthly number in exchange for a firmer handover fee — not the other way around.

---

## 7 · Know the gaps before you quote

From your own `PROJECT_OVERVIEW.md` — say these out loud in the conversation rather than let Customs find them later. Naming them yourself is part of why the audit trusts the work.

| Gap | Why it matters |
|---|---|
| Installer unsigned | Windows SmartScreen warns on first run — needs a code-signing certificate, a procurement item for Customs, not a coding fix. |
| Migrations 021–033 not on the office server | Written and self-verified locally, but not yet applied where it counts. |
| No automated backup | The single biggest operational risk right now — worth raising before anything else in the handover conversation. |
| Device-approval enforcement is off | Built and working, but empty by design until every office PC is approved in one sitting. |

---

## Bottom line

| | |
|---|---|
| **Opening ask (handover fee)** | **LKR 4,000,000** |
| Handover fee range | LKR 3,000,000 – 5,500,000 |
| Monthly maintenance | LKR 45,000 – 85,000 |
| Annual maintenance (alternative) | LKR 450,000 – 850,000 |
| IP approach | Full transfer, priced into the handover fee |
| Maintenance role | Stay on as maintainer yourself, on retainer |

---

*Figures are ranges built from repository metrics and general Sri Lankan custom-software market pricing, combined with how this project actually came about. They are not a contract, a legal opinion, or a guarantee Customs will agree — treat them as a starting position to adjust once you hear back.*

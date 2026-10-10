<div align="center">

  <img src="Sri_Lanka_Customs_logo.svg" alt="Sri Lanka Customs Emblem" width="160" height="160" />

  # Sri Lanka Customs — Yard & SR Management System
  
  **An Enterprise Windows Desktop Platform for Seizure Report (SR) Operations, Multi-Yard Warehouse Inventory, Accrued Storage Tariffs, Valuation Workflows, 5-Round Public Tenders, and Executive Disposal Management.**

  [![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
  [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
  [![Platform](https://img.shields.io/badge/Platform-Windows_x64-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows)
  [![Architecture](https://img.shields.io/badge/Architecture-Direct_DB_over_TLS-512BD4?style=for-the-badge&logo=databricks&logoColor=white)](https://github.com)
  [![Security](https://img.shields.io/badge/Security-RLS_%2B_bcrypt_%2B_2FA_%2B_DPAPI-2ea44f?style=for-the-badge&logo=shield)](https://github.com)
  [![Tests](https://img.shields.io/badge/Test_Suites-146_Files_Passing-brightgreen?style=for-the-badge)](https://github.com)
  [![License](https://img.shields.io/badge/License-Proprietary_/_SL_Customs-red?style=for-the-badge)](LICENSE)

</div>

---

## 📑 Table of Contents

- [1. Executive Overview \& Problem Context](#1-executive-overview--problem-context)
- [2. System Architecture \& Core Philosophy](#2-system-architecture--core-philosophy)
- [3. The 7 Directorate Portals](#3-the-7-directorate-portals)
- [4. The End-to-End Seizure Lifecycle](#4-the-end-to-end-seizure-lifecycle)
- [5. Detailed Screen \& Functional Capabilities](#5-detailed-screen--functional-capabilities)
- [6. Database Architecture \& Schema Deep-Dive](#6-database-architecture--schema-deep-dive)
- [7. Enterprise Security \& Hardening Framework](#7-enterprise-security--hardening-framework)
- [8. Performance Engineering \& Optimizations](#8-performance-engineering--optimizations)
- [9. Hardware, Barcodes \& Report Generation](#9-hardware-barcodes--report-generation)
- [10. UI/UX Design System \& Theme Palette](#10-uiux-design-system--theme-palette)
- [11. Testing \& Quality Assurance Suite](#11-testing--quality-assurance-suite)
- [12. Disaster Recovery, Backups \& Maintenance](#12-disaster-recovery-backups--maintenance)
- [13. Project Structure](#13-project-structure)
- [14. Installation, Configuration \& Deployment](#14-installation-configuration--deployment)
- [15. Architectural FAQs \& Design Rationales](#15-architectural-faqs--design-rationales)
- [16. Author \& Legal Notice](#16-author--legal-notice)

---

## 1. Executive Overview & Problem Context

When **Sri Lanka Customs** seizes undeclared, misdeclared, or prohibited consignments at maritime ports (Colombo Port, JCT, RCT, BQ, CTV), border checkpoints, or inland container depots (Grayline 1, Grayline 2, NNR), an official **Seizure Report (SR)** is registered. 

From that exact moment, the goods generate complex legal and fiscal obligations:
1. **Warehouse Space Allocation**: Goods occupy bonded storage space, accruing daily storage charges under tiered statutory tariffs.
2. **Mandatory 30-Day Legal Appeal Window**: Importers/consignees hold the statutory right to appeal before forfeiture.
3. **Appraisal & Valuation**: Goods must be appraised item-by-item by the Valuation Directorate prior to public tender.
4. **Structured Multi-Round Tenders**: Up to 4 progressive public tender rounds; if unsold, an Executive Valuation Committee is constituted for a 5th round.
5. **Final Dispositions**: Ultimate settlement via Public Auction, Destruction, Allocation to State Agencies, Re-export, or Owner Release.

### The Problem It Solves
Historically, this complex lifecycle was managed across fragmented paper ledger registers, manual logbooks, and disconnected spreadsheets maintained in silos by each yard and directorate. No single officer or Director General could instantly answer:
> *"Where is SR #2025-047 located right now, what are its accumulated storage costs to date, what bids were placed during Tender Round 2, and which officer authorized its destruction?"*

The **Customs Yard & SR Management System** solves this permanently. It provides an enterprise, tamper-proof desktop application designed for ~100+ concurrent officers across all customs yards and head office directorates.

---

## 2. System Architecture & Core Philosophy

The system is built as a **Hardened Thin Windows Desktop Client communicating directly with an On-Premise PostgreSQL 18 Cluster over TLS**.

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    Windows Desktop Client (Flutter / Dart)                │
│   • Scoped Riverpod State Containers   • Hardware Barcode / Thermal Print │
│   • Background Isolate Data Parsing    • Frame Watchdog Latency Logger    │
│   • DPAPI Windows Credential Store     • Machine GUID Device Validator    │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │ Direct Pure-Dart Socket Connection
                                      │ TLS / SSL Mode Parameterized SQL
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                     PostgreSQL 18 Enterprise Database                     │
│  ├── 🛡️ 153 Row-Level Security Policies (24 RESTRICTIVE Policies)          │
│  ├── 🔐 SECURITY DEFINER Stored Functions (Protected Workflow Execution)   │
│  ├── 📜 74 Database Triggers (Immutable Audit Trails & Tariff Math)       │
│  ├── 👁️ 23/24 Security Invoker Views (Zero RLS Bypass)                   │
│  ├── 🔑 bcrypt Password Hashing (pgcrypto) & 90-Day Forced Rotation       │
│  ├── ✉️ Two-Factor Authentication (Email OTP via SMTP Engine)             │
│  ├── 🖥️ Hardware Device Whitelist Table (Machine GUID Verification)       │
│  └── 🚫 Dedicated 'yard_app' Non-Superuser Role                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Core Design Philosophy: *"Database Enforces, UI Merely Reflects"*
- A validation rule in Dart only protects users of this specific app.
- A rule enforced directly in **PostgreSQL 18** protects state integrity from *any* client, future web/mobile integration, batch script, or direct `psql` connection.
- There is no intermediary web API server or Node/Python middleware to patch, configure, or expose to web vulnerabilities (No CORS, No CSRF, No JWT replay).

---

## 3. The 7 Directorate Portals

The application implements a strict Role-Based Access Control (RBAC) architecture. Each directorate signs in to its dedicated portal with distinct visual styling and color themes:

```
                                  ┌──────────────────────────────────────────────┐
                                  │    Sri Lanka Customs SR Management System    │
                                  └──────────────────────┬───────────────────────┘
                                                         │
         ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐
         │                                               │                                               │
         ▼                                               ▼                                               ▼
┌──────────────────┐                           ┌───────────────────┐                           ┌──────────────────┐
│  Yard Operations │                           │  Head Office      │                           │  Administration  │
├──────────────────┤                           ├───────────────────┤                           ├──────────────────┤
│ 1. Yard Officers │                           │ 3. Valuation Dir. │                           │ 6. Top Management│
│ 2. Yard Admin    │                           │ 4. Disposal Dir.  │                           │ 7. ICT Systems   │
│                  │                           │ 5. Appeal Board   │                           │    Directorate   │
└──────────────────┘                           └───────────────────┘                           └──────────────────┘
```

| Portal | Target Officer Roles | Primary Responsibilities & UI Features |
|:---|:---|:---|
| 🏢 **Yard Operations** | `SC`, `DSC`, `ASC` (Superintendent, Dep. & Asst. Sup.) | Register incoming SR packages, log container/consignee details, allocate warehouse zones, track detentions/abandonments, print barcode thermal stickers, handle release upon settlement. |
| 🛡️ **Yard Administration** | `SDDC`, `DDC` (Senior Dep. Director & Dep. Director) | Manage yard operational quotas, review warehouse transfers, authorize yard-level disposals, issue formal **Disposal Requests** to Central Disposal. |
| 💎 **Valuation Directorate** | Valuation Officers & Appraisers | Appraise seized goods item-by-item, determine statutory reserve values before Tender Round 1, re-price unsold lots between tender iterations. |
| 🔨 **Central Disposal** | Disposal Officers & Auctioneers | Manage incoming disposal requests, publish tender notices, record bidder deposits & bids, conduct public tender rounds, record destruction workflows, manage disposal expense ledgers. |
| ⚖️ **Appeal Directorate** | Legal Officers & Appeal Board | Hear legal appeals from owners, place statutory **APPEAL HOLD** freezes on packages, enter final legal rulings (Release, Sell, Destroy, Re-export). |
| 👑 **Top Management** | `DGC`, `ADGC`, `SDC`, `DC` (Director General & Deputies) | Appoint 5-member Valuation Committees for 4-time failed tender items, review committee pricing, rule on unsold lots, monitor real-time revenue and customs analytics. |
| ⚙️ **ICT Directorate** | System Administrators | User account provisioning, RBAC role assignment, yard/directorate configuration, daily storage rate tariff matrix, approved hardware machine whitelisting, immutable audit log inspections. |

---

## 4. The End-to-End Seizure Lifecycle

```
    [Consignment Intercepted & SR Raised in Yard] (GL1, GL2, RCT, BQ, JCT, NNR, CTV)
             │
             ├──► Perishable Goods? ─────────────────► [Fast-Track Immediate Disposal]
             │
             ▼
    [Admitted to Warehouse Zone] ───────────────────► [Storage Tariffs Accrue Daily]
             │
             ▼
    [30-Day Mandatory Appeal Window] ───────────────► [Appeal Directorate HOLD]
             │                                                │
             │                                                ▼
             │                                     Ruling: Release / Sell / Destroy / Re-Export
             ▼
    [Yard Admin (SDDC/DDC) Submits Disposal Request]
             │
             ▼
    [Valuation Directorate Prices Consignment]
             │
             ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  Round 1: Valuation Tender (Reserve Price Appraisal)       │
    │  Round 2: Tender 1   ──┐                                    │
    │  Round 3: Tender 2     ├── Reserve dynamically calculated   │
    │  Round 4: Tender 3   ──┘   from highest unsold bids         │
    └─────────────────────────────────────────────────────────────┘
             │
             ▼ (If unsold after Round 4)
    [Top Management Appoints 5-Member Committee]
             │
             ▼
    [Round 5: Committee Valuation & Decision] (Takes no bids — Executive decision)
             │
             ▼ (If still unsold)
    [Director General (DG) Final Outcome Determination]
```

---

## 5. Detailed Screen & Functional Capabilities

### 5.1 Yard Portals (`lib/screens/inspection/`, `warehouses/`, `packages/`)
- **SR Intake Register**: Dynamic form with input validation, HS Code lookup, container numbers, consignee details, and multi-package support.
- **Warehouse Zone Manager**: Visual grid of warehouse capacity with occupancy percentages, rack/bay identifiers, and movement history.
- **Storage Charge Estimator**: Real-time closed-form computation of storage costs based on active dates and applicable rate periods.
- **Release Verification**: Gate pass generation with QR code validation and payment receipt tracking.

### 5.2 Valuation Directorate (`lib/screens/valuation/`)
- **Pending Appraisals Queue**: Filterable inventory of packages forwarded by yard admins awaiting valuation.
- **Itemized Breakdown**: Per-item assessment forms, condition scoring, market value comparison, and statutory tax calculation.
- **Tender Re-Pricing**: Re-valuation interface triggered when items fail tender rounds.

### 5.3 Central Disposal Directorate (`lib/screens/disposal/`)
- **Tender Sales Manager**: Multi-round scheduling, tender catalog generation, bidder registration, and deposit logging.
- **Bid Evaluation**: Side-by-side bid comparison, reserve price verification, and winning bidder designation.
- **Disposal Expense Ledger**: Complete bookkeeping of expenses (advertising, labor, transport, auctioneer fees, destruction costs, and refunds).
- **Destruction Logging**: Multi-witness verification, environmental compliance certificate attachment, and supervisor sign-off.

### 5.4 Appeal Directorate (`lib/screens/appeal/`)
- **Appeals Register**: Active legal cases, court case cross-references, petitioner details, and hearing logs.
- **Active Hold Engine**: One-click freeze preventing any yard release, tender inclusion, or destruction while under appeal.

### 5.5 Top Management & Executive (`lib/screens/executive/`)
- **Committee Constitution**: Appoint 5 certified customs officers to Valuation Committees.
- **Macro Analytics**: Real-time FL Chart graphs showing revenue breakdown, yard occupancy distribution, and average liquidation turnaround.

### 5.6 ICT Directorate (`lib/screens/ict/`)
- **User Provisioning**: Account creation, role assignment, password policy enforcement, and 2FA reset.
- **Storage Tariffs & Taxes**: Editable rate tables with historical validity ranges.
- **Hardware Whitelist**: Machine GUID approval interface for endpoint locking.

---

## 6. Database Architecture & Schema Deep-Dive

The database consists of **33 tables, 24 views, 169 stored functions, and 74 triggers** running on PostgreSQL 18.

### 6.1 Core Tables

```
packages ───────────────┬────────► warehouse_entries
   │                    │                 │
   │                    ├────────► seizure_reports
   │                    │                 │
   ▼                    ├────────► disposal_requests
valuations              │                 │
   │                    ├────────► appeal_cases
   ▼                    │                 │
tenders ──► bids        └────────► disposal_expenses
```

- `packages`: Master register of all detained, seized, abandoned, and forfeited goods.
- `warehouse_entries`: Physical warehouse zone admission, transfers, and exits.
- `storage_rates`: Historical tiered daily storage rates per yard and cubic measurement.
- `valuations`: Appraisal values per item and tender round.
- `tenders`: Multi-round tender schedules, dates, and statuses.
- `bids`: Bidder registrations, deposit receipts, and bid amounts.
- `committees` & `committee_members`: Executive valuation committees for Round 5 items.
- `appeal_cases`: Appeal board submissions, holds, and verdicts.
- `audit_logs`: Immutable, append-only security log table.
- `approved_devices`: Registry of authorized client hardware machine GUIDs.

### 6.2 Row-Level Security (RLS) Matrix
Every table in the `public` schema has RLS enabled (verified by automated tests):
- **153 Total Policies**: 129 Permissive and **24 RESTRICTIVE** policies.
- **Yard Isolation**: Yard officers physically cannot query packages from other yards (`WHERE yard = current_officer_yard()`).
- **Administrative Restrictions**: Only `SDDC` and `DDC` roles have policy clearance to insert into `disposal_requests`.
- **Reference Data Protection**: Tables like `storage_rates` and `hold_reasons` are globally readable by officers, but writable only by ICT.
- **Security Invoker Views**: 23 of 24 views use `WITH (security_invoker = true)`, preventing views from bypassing RLS.

### 6.3 Immutable Append-Only Audit Logging
- The `audit_logs` table has database triggers that reject all `UPDATE`, `DELETE`, and `TRUNCATE` operations.
- Captures: `actor_id`, `actor_role_snapshot` (the exact role held at that moment), `target_yard`, `action`, `table_name`, `record_id`, `ip_address`, and `payload_diff`.
- Refused connection and failed login attempts log autonomously via `dblink` over an isolated transaction so rollbacks cannot erase security audit rows.

---

## 7. Enterprise Security & Hardening Framework

| Security Control | Implementation & Enforcement Mechanism |
|:---|:---|
| **Password Storage** | `bcrypt` hashing with salt via `pgcrypto` in `auth.users`. Passwords never stored in plaintext. |
| **Password Complexity** | 12–24 characters: upper, lower, digits, symbols, dictionary check (Dart & SQL mirrored). |
| **Password Rotation** | Mandatory 90-day rotation. Expired accounts are blocked by DB functions from executing queries. |
| **Password History** | Rejection of the last 5 previous passwords on change. |
| **Brute-Force Lockout** | 5 consecutive failed login attempts locks the account for 15 minutes. |
| **Two-Factor Authentication** | 6-digit email OTP generated on sign-in, valid for 5 minutes. |
| **Workstation Idle Lock** | UI automatically enters secure lock screen after 5 minutes of inactivity (`lib/core/idle_lock.dart`). |
| **Account Dormancy** | Accounts unused for 30 consecutive days are automatically marked dormant. |
| **Approved Device Whitelisting**| Windows Machine GUID extracted, hashed, and validated against `approved_devices` table. |
| **Credential Storage** | Windows Credential Manager (DPAPI encryption) via `flutter_secure_storage`. |
| **SQL Injection Defense** | 100% parameter-bound queries via `Sql.named()` — zero string concatenation. |
| **DB Role Principle** | App runs under unprivileged role `yard_app` (never runs as `postgres` superuser). |

---

## 8. Performance Engineering & Optimizations

### 8.1 Closed-Form Storage Tariff Engine $O(1)$
Previously, calculating storage fees for an entry 500 days old looped across each day and queried rate changes, taking **~1.5 seconds** per package on the UI thread.
- **Optimization**: Implemented an analytical closed-form summation across rate validity periods.
- **Result**: Reduced from $O(N)$ daily loops to $O(K)$ period multiplications (<1ms runtime). Equivalence verified over 500 randomized spans against legacy math.

### 8.2 Background Isolate Hydration
Parsing large lists of complex model instances blocks the single-threaded Flutter UI event loop, causing dropped frames.
- Heavy dataset conversions are delegated to background worker isolates using Dart's `compute()` / `Isolate.run()`.
- Keeps the UI thread running at a smooth 60 FPS even during bulk operations.

### 8.3 Server-Side SQL Paging
- Replaced client-side array paging with strict `LIMIT` and `OFFSET` SQL queries combined with `COUNT(*) OVER()`.
- Only 20 rows are transferred over the network per page view.

### 8.4 Frame Watchdog Monitor (`lib/core/frame_watch.dart`)
- A permanent frame watchdog measures Flutter rendering times.
- Any frame taking longer than **250ms** is automatically logged to `frame_watch.log` with memory metrics and timestamp for proactive debugging.

---

## 9. Hardware, Barcodes & Report Generation

### 9.1 Barcode & Label Generation (`lib/core/` & `lib/widgets/`)
- **Code 128 & QR Code Generation**: Generates high-resolution barcodes for Package IDs, SR Numbers, and Warehouse Bay locations using the `barcode` package.
- **Direct Thermal Printing**: Supports standard Windows print spoolers and direct ESC/POS thermal receipt and label printers (2" x 1" and 4" x 6" label stocks).

### 9.2 Official PDF & Excel Document Exports
- Built with `pdf`, `printing`, and `excel` libraries:
  - 📄 **Seizure Report Certificates**: Formal documentation with Customs watermark and officer signatures.
  - 📄 **Warehouse Gate Passes**: Barcode-validated gate release passes for security checkpoint guards.
  - 📄 **Tender Auction Catalogs**: Formatted public auction catalogs with lot numbers and specifications.
  - 📊 **Treasury & Auditor Excel Workbooks**: Complete data register extractions for external audits.

---

## 10. UI/UX Design System & Theme Palette

The UI utilizes **Material Design 3** styled with custom design tokens tailored for high-intensity, daylight and warehouse desktop environments:

```
├── Typography: Google Fonts Outfit (Headings) & Inter (Data & Numbers)
├── Design Tokens: Card border radiuses, subtle elevation shadows, glassmorphism appbars
└── Directorate Colors:
    ├── Yard Operations: Emerald Green (#00875A)
    ├── Yard Administration: Slate Blue (#2C3E50)
    ├── Valuation Directorate: Sapphire Blue (#0052CC)
    ├── Central Disposal: Warm Amber / Bronze (#B78103)
    ├── Appeal Directorate: Royal Purple (#5243AA)
    ├── Top Management: Imperial Burgundy / Gold (#8B0000)
    └── ICT Systems: Cyber Slate (#172B4D)
```

---

## 11. Testing & Quality Assurance Suite

The codebase includes **146 comprehensive test suites**:

```
test/
├── core/                              # Routing, security, and encryption tests
├── equivalence/                       # Closed-form storage fee equivalence tests
├── models/                            # JSON serialization and model integrity tests
├── rls/                               # Database-level Row-Level Security verification
├── screens/                           # Widget and navigation tests
├── services/                          # SQL query building and service layer tests
└── validation/                        # Password rules, HS codes, and input validators
```

### Key Testing Paradigms
- **SQL Migration Verification**: Migrations self-test upon application, ensuring constraints and policies are active before committing.
- **Equivalence Testing**: Verified numerical parity between closed-form calculation algorithms and historical day-by-day calculations.
- **Security Hardening Tests**: Validates that non-admin sessions fail authorization on admin endpoints.

---

## 12. Disaster Recovery, Backups & Maintenance

### 12.1 Automated Database Backups
- Scheduled via PowerShell: `.\tool\backup_database.ps1`.
- Performs full `pg_dump` with custom compression format and sha256 checksum generation.
- Automated 30-day rolling retention and off-site synchronization.

### 12.2 Point-In-Time Recovery (PITR)
- Write-Ahead Logging (WAL) archiving enabled in `postgresql.conf`.
- Allows restoration of the database to any exact minute in case of hardware failure or human error.

---

## 13. Project Structure

```text
lib/
├── main.dart                          # App initialization, window manager, crash capture
├── core/
│   ├── app_env.dart                   # Environment loader (.env / dart-define)
│   ├── app_session.dart               # Active officer session & role states
│   ├── db/                            # PostgreSQL connection pool & SQL query builders
│   ├── device_id.dart                 # Machine GUID extraction & hashing
│   ├── directorates.dart              # Directorate metadata & routing guards
│   ├── error_handling.dart            # Global error boundaries & logging
│   ├── frame_watch.dart               # Rendering performance watchdog
│   ├── holidays.dart                  # Statutory customs holiday calendar
│   ├── idle_lock.dart                 # 5-minute auto workstation lock
│   ├── providers.dart                 # Global Riverpod state providers
│   ├── router.dart                    # GoRouter configuration & authorization guards
│   ├── theme.dart                     # Customs color palettes & typography tokens
│   ├── windows_credential_store.dart  # DPAPI-encrypted credential store
│   └── yards.dart                     # Yard definitions and codes
├── models/
│   └── models.dart                    # Data models (Package, SR, Warehouse, Tender, User, etc.)
├── screens/
│   ├── admin/                         # Yard Administration portals (SDDC/DDC)
│   ├── appeal/                        # Appeal Directorate dispute & hold screens
│   ├── auth/                          # Authentication, Password Reset, OTP verification
│   ├── disposal/                      # Central Disposal tenders, sales, auctions, destruction
│   ├── executive/                     # Top Management committee & executive decision portal
│   ├── forfeited_packages/            # Forfeited goods & disposal request workflows
│   ├── ict/                           # ICT Directorate user provisioning & audit logs
│   ├── inspection/                    # SR intake, inspection & goods categorization
│   ├── lock/                          # Idle workstation lock screen
│   ├── login/                         # Directorate-specific login screens
│   ├── packages/                      # Package register, details & editing
│   ├── profile/                       # User profile management & password change
│   ├── reports/                       # Statistical reports, registers & PDF/Excel exports
│   ├── valuation/                     # Valuation Directorate pricing workflows
│   └── warehouses/                    # Yard warehouse zones & occupancy tracking
├── services/                          # Business logic services & SQL data layers
└── widgets/                           # Reusable UI components, dialogs, badges & filters
```

---

## 14. Installation, Configuration & Deployment

### 14.1 Prerequisites
- **Flutter SDK**: `3.24.0` or higher (Flutter 3.41 recommended)
- **Dart SDK**: `3.5.0` or higher
- **PostgreSQL**: `15.x` - `18.x`
- **Build Tools**: Visual Studio 2022 with "Desktop development with C++" workload
- **Inno Setup**: Version 6.x (for building the Windows installer)

### 14.2 Local Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/AMunasinghe2001/Customs_Yard_Management_System.git
   cd Customs_Yard_Management_System
   ```

2. **Configure Environment Variables**:
   Copy `.env.example` to `.env` in the project root:
   ```bash
   copy .env.example .env
   ```
   Edit `.env` with your database credentials:
   ```ini
   PG_HOST=127.0.0.1
   PG_PORT=5432
   PG_DATABASE=customs_sr_system
   PG_USER=yard_app
   PG_PASSWORD=YourSecurePasswordHere
   PG_SSL=false
   ```

3. **Apply Database Migrations**:
   ```bash
   python apply_database_migrations.py
   ```

4. **Install Dependencies & Run**:
   ```bash
   flutter pub get
   flutter run -d windows
   ```

### 14.3 Production Build & Obfuscation

To build a secure, obfuscated release binary:

```powershell
.\tool\build_release.ps1
```

Or execute manually via Flutter CLI:

```bash
flutter build windows --release --obfuscate --split-debug-info=build/symbols/v1.6.3
```

> [!IMPORTANT]
> Always archive `build/symbols/<version>/` alongside every production release. Stack traces from obfuscated release builds can be decoded using:
> ```bash
> flutter symbolize -i crash.txt -d build/symbols/v1.6.3/app.windows-x64.symbols
> ```

### 14.4 Compiling the Inno Setup Windows Installer

```bash
iscc windows_installer_script.iss
```
The output installer is generated in `installer/Output/Customs_Yard_Management_Setup.exe`.

---

## 15. Architectural FAQs & Design Rationales

### Q1: Why build a native Windows Desktop application instead of a Web App?
1. **Existing Infrastructure**: Customs yards and port gates are already equipped with Windows workstations connected to thermal label printers and barcode scanners.
2. **Zero Attack Surface from Browsers**: Completely eliminates Web-based vulnerabilities like session cookie theft, XSS, CSRF, and malicious browser extensions.
3. **No Intermediate Web Gateway**: Connects directly to the on-premise database over encrypted TLS, removing middle-tier maintenance overhead.

### Q2: Why enforce business rules in PostgreSQL instead of Dart?
Enforcing rules in the database ensures data integrity across all contexts. Even if an officer attempts to execute direct SQL queries using `psql`, the database triggers, RLS policies, and stored procedures guarantee that unauthorized operations are blocked.

### Q3: How is data isolated between different customs yards?
Yard isolation is enforced via PostgreSQL Row-Level Security (RLS). When an officer signs in, their yard assignment is stored in the session context (`auth.begin_session`). The database automatically applies `WHERE yard = current_setting('app.current_yard')` to all queries, making cross-yard data leaks mathematically impossible.

---

## 16. Author & Legal Notice

### 👤 Author & Lead Architect
**Anushanga Munasinghe**
- GitHub: [@AMunasinghe2001](https://github.com/AMunasinghe2001)
- Role: Lead Systems Architect & Developer

### ⚖️ Legal & Confidentiality Notice
This software, database schemas, and documentation are proprietary and confidential assets developed for **Sri Lanka Customs**. All rights reserved. Unauthorized copying, distribution, decompilation, or transmission in any form without explicit written authorization from the Director General of Customs is strictly prohibited.

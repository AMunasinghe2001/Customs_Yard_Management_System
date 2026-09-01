# Security Hardening - Remaining Tasks

**Status**: Phase 2 (Database & Session Control) ✓ Complete  
**Target**: Phase 3 (Application-level & Operational Security)

---

## Completed Security Controls ✓

### Phase 1: Credential Protection
- [x] Encrypted credential storage (AES encryption for saved passwords)
- [x] Plaintext password elimination from SharedPreferences
- [x] Secure password hashing (bcrypt in auth.users.encrypted_password)

### Phase 2: Database & Session Control
- [x] Login lockout (5 attempts → 15-minute lock, DB-enforced)
- [x] Session timeout (30-minute idle with heartbeat refresh)
- [x] Audit logging (all auth, package, and status-change events)
- [x] Row-level security policies (73 RLS policies enforcing officer/admin access)
- [x] Database authorization checks (auth.uid() session validation)
- [x] Test coverage (test/security_hardening_test.dart - all 4 tests passing)

---

## Phase 3: Application-Level Security (To Do)

### A. Input Validation & Injection Prevention

#### A1. CSRF Protection (POST/PUT/DELETE)
**Risk**: Cross-site request forgery attacks on state-changing operations  
**Status**: Not implemented  
**Action Items**:
- [ ] Implement CSRF token generation in the app's session
- [ ] Validate CSRF tokens on all POST/PUT/DELETE requests to the backend
- [ ] Add token refresh logic after each state change
- [ ] Document CSRF token handling in `lib/core/` README

**Files to Modify**:
- `lib/core/db/pg_client.dart` - Add CSRF token to request headers
- `lib/services/services.dart` - Validate tokens before state-changing operations
- `postgres/02_schema.sql` - Add CSRF token storage (if persisted)

#### A2. SQL Injection Prevention
**Risk**: Malicious SQL in string parameters  
**Status**: Mitigated (using parameterized queries)  
**Verification Needed**:
- [ ] Audit all `PgQuery` and `Sql.named()` calls to confirm parameter binding
- [ ] Review any dynamic SQL generation in `lib/core/db/pg_query.dart`
- [ ] Add input validation rules in `lib/core/validators.dart`
- [ ] Document parameterized query patterns in code comments

**Files to Review**:
- `lib/core/db/pg_query.dart` - Verify all dynamic WHERE/ORDER BY clauses are parameterized
- `lib/core/db/pg_client.dart` - Confirm RPC calls use parameter binding
- `lib/models/models.dart` - Check any custom query builders

#### A3. XSS Prevention (Output Encoding)
**Risk**: Malicious scripts injected through package descriptions, notes, or user input  
**Status**: Partially mitigated (Flutter is HTML-agnostic, but user-controlled text still rendered)  
**Action Items**:
- [ ] Sanitize all user-controlled text inputs before storage
- [ ] Validate and strip HTML/script tags from package descriptions and notes
- [ ] Implement input validation rules for all text fields
- [ ] Add length limits to prevent buffer overflow attacks

**Files to Modify**:
- `lib/core/validators.dart` - Add sanitization functions for description, notes, and metadata
- `lib/models/models.dart` - Add validation in model constructors
- `lib/screens/packages/packages_screen.dart` - Validate input before update
- `lib/screens/inspection/inspection_screen.dart` - Validate SR entry data before save

#### A4. Path Traversal Prevention
**Risk**: Malicious file paths in document upload / report generation  
**Status**: Not implemented  
**Action Items**:
- [ ] Validate file paths are within allowed directories
- [ ] Reject paths containing `..` or absolute paths
- [ ] Use UUID for uploaded file names (not user-controlled)
- [ ] Store file references in database, not as paths

**Files to Modify**:
- `lib/services/services.dart` - Add file upload validation
- `lib/screens/disposal/expenses_tab.dart` - Validate file picks
- `lib/screens/profile/edit_profile_screen.dart` - Sanitize avatar uploads

---

### B. Transport Security

#### B1. TLS/SSL Enforcement
**Risk**: Unencrypted communication between app and database  
**Status**: Partially implemented (local network assumed safe)  
**Action Items**:
- [ ] Enable SSL for PostgreSQL connections in production
- [ ] Configure `PgConfig.settings` to require SSL mode (not disable)
- [ ] Use certificate pinning for the production database server
- [ ] Document SSL setup in `postgres/README.md`

**Files to Modify**:
- `lib/core/db/pg_connection.dart` - Change `SslMode.disable` to `SslMode.require` for production
- `.env` - Add `PG_SSL=require` configuration option
- `postgres/README.md` - Add SSL setup instructions

#### B2. HTTP Security Headers (If Web Frontend Added)
**Risk**: Clickjacking, MIME-type sniffing, cache poisoning  
**Status**: N/A (Desktop app only)  
**Action Items**:
- [ ] Reserve for future web dashboard: X-Frame-Options, Content-Security-Policy, etc.

---

### C. Authentication & Authorization

#### C1. Multi-Factor Authentication (MFA)
**Risk**: Password-only authentication is single point of failure  
**Status**: OTP-based login for Disposal Directorate (partial)  
**Action Items**:
- [ ] Extend OTP to all directorates (not just Disposal)
- [ ] Add TOTP (time-based OTP) as second factor option
- [ ] Implement backup recovery codes
- [ ] Document MFA recovery process

**Files to Review/Modify**:
- `lib/services/services.dart` - OTP logic in `startOtpLogin()` and `finishOtpLogin()`
- `lib/screens/disposal/disposal_login_screen.dart` - Extend OTP UI to other roles
- `lib/core/otp_service.dart` - Review OTP implementation and add TOTP support

#### C2. Password Policy Enforcement
**Risk**: Weak passwords accepted on account creation  
**Status**: Minimum 6 characters only  
**Action Items**:
- [ ] Enforce minimum 12 characters
- [ ] Require uppercase, lowercase, numbers, and symbols
- [ ] Prevent password reuse (last 5 passwords)
- [ ] Enforce password expiry (90 days) with warning at 80 days
- [ ] Prevent common passwords (check against public lists)

**Files to Modify**:
- `lib/core/security_policy.dart` - Add `PasswordPolicy` class with validation rules
- `postgres/04_auth.sql` - Add password strength validation in `auth.sign_up()` and `auth.change_password()`
- `lib/screens/login/login_screen.dart` - Show password strength indicator
- `lib/screens/disposal/disposal_login_screen.dart` - Validate on password set

#### C3. Account Lockout on Admin Deactivation
**Risk**: Deactivated accounts can still sign in if session hijacked  
**Status**: Profile checks for `is_active` but auth.users can still sign in  
**Action Items**:
- [ ] Sync `profiles.is_active` state to `auth.users.is_active`
- [ ] Add trigger to mirror profile deactivation in auth schema
- [ ] Update `auth.sign_in()` to check both profile and auth.users status
- [ ] Document deactivation workflow

**Files to Modify**:
- `postgres/02_schema.sql` - Add `auth.users.is_active` column and sync trigger
- `postgres/04_auth.sql` - Update `auth.sign_in()` to check is_active
- `lib/screens/admin/admin_screen.dart` - Confirm deactivation flow

---

### D. Monitoring & Audit

#### D1. Failed Login Alerts
**Risk**: Repeated failed logins not surfaced to admins  
**Status**: Logged but not alerted  
**Action Items**:
- [ ] Query `audit_logs` for failed login patterns
- [ ] Alert admin if 3+ failed logins in 30 minutes
- [ ] Create admin dashboard panel showing suspicious activity
- [ ] Log IP address (if available from connection metadata)

**Files to Create/Modify**:
- `lib/services/services.dart` - Add `AuditLogService.checkSuspiciousActivity()`
- `lib/screens/admin/admin_screen.dart` - Add "Security Alerts" panel
- `postgres/02_schema.sql` - Add view for recent failed logins

#### D2. Audit Log Retention & Rotation
**Risk**: Unbounded audit_logs table growth  
**Status**: No retention policy  
**Action Items**:
- [ ] Archive audit logs older than 90 days to separate table
- [ ] Implement nightly cleanup job to move old logs
- [ ] Create backup export before cleanup
- [ ] Document retention policy

**Files to Create/Modify**:
- `postgres/02_schema.sql` - Add audit_logs_archive table and migration script
- `tool/archive_audit_logs.dart` - Create scheduled job
- `postgres/README.md` - Document retention policy

#### D3. Security Event Reporting
**Risk**: No visibility into security events for compliance  
**Status**: Data exists but no reports  
**Action Items**:
- [ ] Create admin report: "Failed Logins by User (Last 30 Days)"
- [ ] Create admin report: "Account Status Changes (Last 30 Days)"
- [ ] Create admin report: "Session Timeouts (Last 7 Days)"
- [ ] Create admin report: "Unauthorized Access Attempts (RLS Denials)"
- [ ] Export reports to CSV for compliance audit

**Files to Create/Modify**:
- `lib/screens/admin/security_reports_tab.dart` - New reports screen
- `lib/services/services.dart` - Add report query methods
- `postgres/02_schema.sql` - Add helpful views for report queries

---

### E. Dependency & Vulnerability Management

#### E1. Dependency Scanning
**Risk**: Vulnerable dependencies (postgres driver, Flutter plugins)  
**Status**: Not scanned  
**Action Items**:
- [ ] Run `flutter pub outdated` and `flutter pub audit`
- [ ] Update all packages to latest stable versions
- [ ] Review breaking changes and test thoroughly
- [ ] Set up automated dependency scanning (CI/CD)

**Files to Check**:
- `pubspec.yaml` - Review version pinning and update strategy
- `.github/workflows/` - Add dependency scanning workflow (if using GitHub Actions)

#### E2. Secrets Management
**Risk**: Database credentials in `.env` or code  
**Status**: Configured via `.env` (good) but no rotation policy  
**Action Items**:
- [ ] Document `.env` as never committed (verify `.gitignore`)
- [ ] Implement database credential rotation quarterly
- [ ] Use environment-specific credentials (dev ≠ prod)
- [ ] Store prod credentials in secure vault (not `.env`)

**Files to Review**:
- `.gitignore` - Confirm `.env` is ignored
- `lib/core/db/pg_connection.dart` - Document credential hierarchy
- `postgres/README.md` - Add credential rotation procedure

---

## Phase 4: Operational Security (To Do)

### A. Deployment Security
- [ ] Code signing for Windows EXE distribution
- [ ] Installer verification (sign the .iss installer script)
- [ ] Rollback procedure for bad deployments
- [ ] Staged rollout (test group → pilot → all)

### B. Infrastructure Security
- [ ] PostgreSQL server hardening (disable unnecessary services, limit connections)
- [ ] Firewall rules (restrict DB access to app machine only)
- [ ] Database backups with encryption at rest
- [ ] Backup restoration testing (quarterly)

### C. Incident Response
- [ ] Document breach notification procedure
- [ ] Create incident response runbook (compromise, data loss, DoS)
- [ ] Contact list for security incidents
- [ ] Post-incident review process

---

## Priority Matrix

| Task | Impact | Effort | Priority | Target |
|------|--------|--------|----------|--------|
| CSRF Protection | High | Medium | P1 | Sprint 1 |
| Password Policy | High | Medium | P1 | Sprint 1 |
| SQL Injection Audit | High | Low | P1 | Sprint 1 |
| TLS Enforcement | High | Low | P2 | Sprint 2 |
| MFA Extension | Medium | High | P2 | Sprint 2 |
| Failed Login Alerts | Medium | Medium | P2 | Sprint 2 |
| Account Lockout Sync | Medium | Low | P2 | Sprint 2 |
| Audit Log Rotation | Medium | Medium | P3 | Sprint 3 |
| Security Reports | Low | High | P3 | Sprint 3 |
| Dependency Scanning | Medium | Low | P3 | Ongoing |

---

## Verification Checklist

After implementing each task, verify:
- [ ] Unit tests added for new security logic
- [ ] Integration tests confirm enforcement (e.g., CSRF token required)
- [ ] Security test suite still passes
- [ ] No new compiler warnings or lint errors
- [ ] Code reviewed by another team member
- [ ] Documentation updated in code comments and README files
- [ ] Audit log entries created for tracking implementation

---

## Reference Documentation

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Flutter Security Guidelines](https://flutter.dev/docs/testing/security-testing)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/sql-syntax.html#SQL-SYNTAX-LEXICAL-STRINGS)
- [Dart Security Best Practices](https://dart.dev/guides/security)

---

## Sign-Off

**Completed By**: GitHub Copilot  
**Date**: 2026-09-01  
**Status**: Ready for Phase 3 Implementation  
**Next Step**: Assign P1 tasks to sprint backlog and begin CSRF + Password Policy implementation

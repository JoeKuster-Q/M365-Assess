# Security & Privacy Assessment

**Repository:** JoeKuster-Q/M365-Assess
**Date:** 2026-04-13
**Scope:** Full codebase audit for telemetry, data exfiltration, privacy issues, and general security posture.

---

## Executive Summary

M365-Assess is a **read-only** PowerShell assessment tool. It collects configuration data from Microsoft 365 services and writes reports **locally only**. The module does **not** transmit assessed tenant data to any third-party endpoint. All outbound network calls are to legitimate Microsoft services required for the assessment.

However, the audit identified several areas of concern documented below, ranging from an external Google Fonts dependency in generated reports to a client secret handling pattern in the Power BI child process flow.

---

## 1. Telemetry & Outbound Network Calls

### 1.1 No Telemetry Found

The module contains **no analytics, telemetry, or usage-tracking code**. There are no calls to Application Insights, Google Analytics, Mixpanel, or any custom telemetry endpoint. No phone-home behavior exists.

### 1.2 Outbound Network Calls — Complete Inventory

| # | Destination | File | Purpose | Data Sent | Risk |
|---|-------------|------|---------|-----------|------|
| 1 | `graph.microsoft.com` | Multiple collectors | Microsoft Graph API (read-only `Get-*` calls) | Auth tokens (MSAL-managed) | **Expected** — core functionality |
| 2 | `outlook.office365.com` | Exchange Online collectors | EXO PowerShell remoting | Auth tokens (MSAL-managed) | **Expected** — core functionality |
| 3 | `login.microsoftonline.com` / `.us` | `Orchestrator/Resolve-M365Environment.ps1:26` | OpenID Connect discovery (unauthenticated) | Tenant ID only (public info) | **Low** |
| 4 | `download.microsoft.com` | `Entra/Get-LicenseReport.ps1:69` | Download Microsoft SKU friendly-name CSV | No assessment data (simple GET) | **Low** |
| 5 | `fonts.googleapis.com` / `fonts.gstatic.com` | `Common/Get-ReportTemplate.ps1:41-43` | Google Fonts loaded when HTML report is opened in browser | Browser IP, referrer, user-agent | **Medium** — see §2.1 |
| 6 | `assets/Update-SkuCsv.ps1:24` | `download.microsoft.com` | Offline refresh of SKU CSV (developer utility, not called at runtime) | None | **Info** |

**Key finding:** No assessed tenant data (user lists, policies, configurations, security findings) is ever transmitted to any external endpoint. All data stays on the local filesystem.

---

## 2. Privacy Issues

### 2.1 Google Fonts in Generated HTML Reports — MEDIUM

**Files:** `src/M365-Assess/Common/Get-ReportTemplate.ps1` (lines 41-43), `src/M365-Assess/Common/Export-FrameworkCatalog.ps1` (lines 431-433)

**Issue:** The generated HTML reports include `<link>` tags that load the Inter font family from `fonts.googleapis.com`. When a user opens the report in a browser, the browser makes requests to Google's servers, exposing:
- The viewer's IP address
- Browser user-agent string
- Referrer header (typically `file:///` for local reports)

**Impact:** Google can observe that someone at a given IP address opened an M365 assessment report. No tenant data is transmitted, but for privacy-sensitive organizations (government, defense, regulated industries), any external request from a security report may violate policy.

**Mitigation options:**
- Self-host the Inter font and embed it as base64 data URI in the report
- Fall back to system fonts (`-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`)
- The report already works without the font (CSS specifies fallbacks)

### 2.2 PII in Assessment Output Files — LOW (By Design)

Assessment CSV, HTML, and XLSX output files contain tenant data that may include PII:

| Data Type | Files | Sensitivity |
|-----------|-------|-------------|
| User principal names / email addresses | MFA Report, User Summary, Inactive Users, Mailbox Summary | **High** |
| Display names | Admin Role Report, MFA Report | **High** |
| Domain names, tenant ID | Tenant Info, DNS Authentication | **Medium** |
| Security policy names and configurations | Conditional Access, Defender, DLP, Transport Rules | **Medium** |
| IP address ranges (from CA policies) | Conditional Access Report | **Medium** |
| License assignments | License Summary | **Low** |

**This is by design** — the tool's purpose is to report on these items. Users should treat all output folders as confidential. The existing `SECURITY.md` correctly notes this.

### 2.3 Assessment Log File Content — LOW (By Design)

The `_Assessment-Log_<tenant>.txt` file records tenant ID, cloud environment, section timings, and error messages. Error messages from Microsoft APIs could contain UPNs or resource names. This is standard diagnostic logging.

---

## 3. Security Issues

### 3.1 Client Secret in Temporary Script File — HIGH

**File:** `src/M365-Assess/Invoke-M365Assessment.ps1` (lines 866-887)

**Issue:** When Power BI assessment uses client secret authentication, the secret is converted from `SecureString` to plaintext and written to a temporary `.ps1` file for the child process:

```powershell
$plainSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
$scriptLines.Add("`$connectParams['ClientSecret'] = (ConvertTo-SecureString '$plainSecret' -AsPlainText -Force)")
# ...
Set-Content -Path $childScriptFile -Value ($scriptLines -join "`n") -Encoding UTF8
```

**Concerns:**
1. **Plaintext secret on disk** — The temp file at `$env:TEMP\m365assess_pbi_*.ps1` contains the client secret in plaintext. On multi-user systems, default file permissions may allow other local users to read it.
2. **No string escaping** — If `$plainSecret`, `$ClientId`, or `$TenantId` contain single quotes or special characters, the generated script will have syntax errors or could be susceptible to injection.
3. **Cleanup race condition** — The `finally` block (line 944-948) removes the temp file, but if the PowerShell process is killed externally (e.g., `taskkill`), the file may remain on disk indefinitely.

**Recommendation:** Pass secrets via secure environment variables or stdin rather than temp files. Validate/escape all interpolated values. Set restrictive ACLs on the temp file immediately after creation.

### 3.2 Custom Branding XSS — MEDIUM

**Files:** `src/M365-Assess/Common/Export-AssessmentReport.ps1` (lines 266-271), `src/M365-Assess/Common/Get-ReportTemplate.ps1` (lines 27-32)

**Issue:** The `CustomBranding.CompanyName` parameter is inserted into the HTML report **without HTML encoding**:

```powershell
# Export-AssessmentReport.ps1 line 267
$brandName = $CustomBranding.CompanyName  # Not encoded

# Get-ReportTemplate.ps1 line 29
"<div class='cover-logo-text'>$brandName</div>"  # Direct insertion
```

A malicious `CompanyName` value like `"><script>alert(1)</script>` would execute JavaScript when the report is opened.

Similarly, `AccentColor` (line 32) is injected into a `<style>` tag without validation and could break out of the CSS context.

**Impact:** Low in practice since users provide their own branding parameters, but this is a defense-in-depth gap. Any automation that passes unsanitized input to `-CustomBranding` could be exploited.

**Recommendation:** Apply `ConvertTo-HtmlSafe` to `$brandName`. Validate `$accentColor` matches `^#[0-9A-Fa-f]{3,8}$` before insertion.

### 3.3 CSV Formula Injection — LOW

**Files:** All collectors using `Export-Csv` (~27 locations)

**Issue:** PowerShell's `Export-Csv` does not sanitize cell values that begin with `=`, `+`, `-`, or `@`. If tenant data (e.g., a display name set to `=CMD|'/C calc'!A0`) is exported to CSV and the file is opened in Excel, it could trigger formula execution.

**Impact:** Low — requires a malicious actor to have already set a crafted display name or policy name in the target tenant, and the report consumer must open the CSV directly in Excel (not the HTML report).

**Recommendation:** Consider prefixing cells starting with `=`, `+`, `-`, `@` with a single quote (`'`) during export, or document the risk and recommend opening CSVs as text imports.

### 3.4 Connection Profile Storage — LOW (By Design)

**File:** `src/M365-Assess/Setup/Save-M365ConnectionProfile.ps1`

The `.m365assess.json` file stores tenant ID, client ID, certificate thumbprint, and auth method in plaintext. **Client secrets are NOT stored** — this is correct.

The `.gitignore` correctly includes `.m365assess.json` (line 26), preventing accidental commits.

Client IDs and certificate thumbprints are not secrets (they are application identifiers and public key references), so plaintext storage is acceptable.

---

## 4. API Permissions Model

All Microsoft Graph permissions are **read-only** (`*.Read.All`). The complete list from `src/M365-Assess/Setup/PermissionDefinitions.ps1`:

| Permission | Purpose |
|-----------|---------|
| Organization.Read.All | Tenant details, domains |
| Domain.Read.All | Registered domains |
| Group.Read.All | Group enumeration |
| User.Read.All | User profiles, sign-in activity |
| AuditLog.Read.All | Sign-in and audit logs |
| UserAuthenticationMethod.Read.All | MFA methods |
| RoleManagement.Read.Directory | Admin role assignments |
| Policy.Read.All | CA, auth, password policies |
| Application.Read.All | App registrations, service principals |
| Directory.Read.All | Devices, admin units |
| DeviceManagementManagedDevices.Read.All | Intune devices |
| DeviceManagementConfiguration.Read.All | Intune profiles |
| DeviceManagementRBAC.Read.All | Intune RBAC |
| DeviceManagementApps.Read.All | Intune app audit events |
| SecurityEvents.Read.All | Secure Score, alerts |
| SharePointTenantSettings.Read.All | SPO/OD settings |
| TeamSettings.Read.All | Teams policies |
| TeamworkAppSettings.Read.All | Teams app policies |
| OrgSettings-Forms.Read.All | Forms settings |
| MailboxSettings.Read | Mailbox settings |
| Team.ReadBasic.All | Teams enumeration |
| TeamMember.Read.All | Teams membership |
| Channel.ReadBasic.All | Teams channels |
| Reports.Read.All | Usage reports |
| Sites.Read.All | SharePoint sites |

**Assessment:** No write, delete, or modification permissions are requested. The tool cannot alter tenant configuration.

---

## 5. Other Observations

### 5.1 No Dynamic Code Execution

- **No `Invoke-Expression` / `iex` usage** anywhere in the module (verified by PSScriptAnalyzer rule and grep)
- **No `Add-Type` with compiled C#** or P/Invoke
- **No dynamic assembly loading** or DLL imports beyond standard PowerShell modules
- **No external script downloads** at runtime

### 5.2 Code Signing

Module scripts are **not code-signed**. This is standard for open-source PowerShell modules distributed via Git. Users on `AllSigned` execution policy must either sign the scripts or use `Unblock-File` after download.

### 5.3 CI/CD Workflows

GitHub Actions workflows (`.github/workflows/ci.yml`, `release.yml`) use only `${{ github.token }}` — no hardcoded secrets. No third-party actions with elevated permissions.

### 5.4 .gitignore Coverage

The `.gitignore` correctly excludes:
- `.m365assess.json` (connection profiles)
- `.env` / `.env.*` (environment files)
- `*.pfx`, `*.pem`, `*.key`, `*.p12`, `*.cer` (certificates)
- `secrets.json`, `credentials.json`
- `M365-Assessment/` (output directories)

---

## 6. Summary

| Finding | Severity | Category | Status |
|---------|----------|----------|--------|
| No telemetry or data exfiltration | — | Telemetry | ✅ **Clean** |
| All API calls read-only to Microsoft endpoints | — | Permissions | ✅ **Clean** |
| Google Fonts loaded when HTML report opened in browser | **Medium** | Privacy | ⚠️ Consider self-hosting or system fonts |
| Client secret written to temp file for Power BI child process | **High** | Security | ⚠️ Recommend passing via env var or stdin |
| Custom branding company name not HTML-encoded | **Medium** | Security | ⚠️ Apply `ConvertTo-HtmlSafe` |
| CSV formula injection not mitigated | **Low** | Security | ⚠️ Document risk or add prefix sanitization |
| PII in assessment output files | **Low** | Privacy | ℹ️ By design — document handling requirements |
| Connection profiles store client ID in plaintext | **Low** | Security | ℹ️ By design — client IDs are not secrets |
| No code signing | **Low** | Security | ℹ️ Standard for open-source modules |

### Bottom Line

**M365-Assess does NOT send assessed data anywhere other than the local computer.** All outbound network calls are to Microsoft cloud services for data collection, plus one Google Fonts reference in generated HTML reports. The module requests only read-only permissions and cannot modify tenant configuration.

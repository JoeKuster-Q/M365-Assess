# Functional Requirements & Feature Requirements

This document defines the functional requirements (FR) and feature requirements for M365-Assess. It serves as the authoritative specification for what the tool does, the constraints it operates under, and the capabilities it provides.

> **Version:** 1.9.0 | **Last Updated:** 2026-04-14

---

## Table of Contents

1. [Scope & Purpose](#scope--purpose)
2. [Core Functional Requirements](#core-functional-requirements)
3. [Assessment Engine Requirements](#assessment-engine-requirements)
4. [Authentication & Connection Requirements](#authentication--connection-requirements)
5. [Reporting Requirements](#reporting-requirements)
6. [Compliance Framework Requirements](#compliance-framework-requirements)
7. [Security & Privacy Requirements](#security--privacy-requirements)
8. [Platform & Environment Requirements](#platform--environment-requirements)
9. [Extensibility Requirements](#extensibility-requirements)
10. [Feature Requirements by Section](#feature-requirements-by-section)

---

## Scope & Purpose

M365-Assess is a **read-only** Microsoft 365 security assessment tool for IT consultants, security administrators, compliance officers, and auditors. It collects configuration data from M365 services via Microsoft APIs, evaluates the data against security benchmarks, and produces actionable reports with remediation guidance.

**The tool MUST NOT modify any tenant configuration.** All API operations use read-only permissions (`Get-*` cmdlets and `*.Read.All` Graph scopes).

---

## Core Functional Requirements

### FR-001: Single-Command Assessment Execution

The tool SHALL execute a complete security assessment from a single PowerShell command (`Invoke-M365Assessment`), handling service connections, data collection, evaluation, and report generation automatically.

### FR-002: Section-Based Modular Assessment

The tool SHALL support modular assessment via a `-Section` parameter that allows users to run any combination of assessment sections independently. Default sections SHALL run without opt-in. Opt-in sections SHALL require explicit selection.

**Default sections:** Tenant, Identity, Licensing, Email, Intune, Security, Collaboration, PowerBI, Hybrid

**Opt-in sections:** Inventory, ActiveDirectory, SOC2, ValueOpportunity

### FR-003: Graceful Degradation on Service Failure

When a service connection fails (e.g., Exchange Online, Purview), the tool SHALL:
- Record the failure with a descriptive error message
- Skip only the collectors dependent on the failed service
- Continue with all other sections and collectors
- Report the failure in the console summary and issue log

### FR-004: Interactive Wizard Mode

When invoked without connection parameters, the tool SHALL launch an interactive wizard that guides users through:
- Section selection
- Tenant ID entry
- Authentication method selection
- Report customization options
- Output folder configuration

Any parameter provided on the command line SHALL skip the corresponding wizard step.

### FR-005: Non-Interactive / Headless Mode

The tool SHALL support fully non-interactive execution via `-NonInteractive` for CI/CD pipelines, scheduled tasks, and headless environments. In this mode:
- Missing required modules SHALL cause an immediate exit with logged fix commands
- Missing optional modules SHALL cause dependent sections to be skipped with a warning
- No user prompts SHALL be displayed

### FR-006: Dry Run Preview

The tool SHALL support a `-DryRun` mode that previews sections, required services, Graph scopes, and check counts without connecting to any service or collecting data.

### FR-007: Quick Scan Mode

The tool SHALL support a `-QuickScan` mode that runs only Critical and High severity checks, enabling faster CI/CD scans and daily monitoring. Collectors with no qualifying checks SHALL be skipped entirely.

---

## Assessment Engine Requirements

### FR-010: Automated Security Check Evaluation

The tool SHALL evaluate **214+ automated security checks** across all assessment sections. Each check SHALL produce one of five statuses:

| Status | Definition |
|--------|-----------|
| **Pass** | Meets the benchmark requirement |
| **Fail** | Violates the benchmark — requires remediation |
| **Warning** | Degraded security posture — suboptimal but not a hard violation |
| **Review** | Cannot determine automatically — requires manual verification |
| **Info** | Informational data point — no pass/fail determination |

### FR-011: CheckId System

Every security check SHALL have a unique identifier following the `{COLLECTOR}-{AREA}-{NNN}` naming convention. CheckIds SHALL be framework-agnostic and stable across releases.

### FR-012: Control Registry

All checks SHALL be registered in `controls/registry.json` with:
- Unique CheckId
- Human-readable name and description
- Collector assignment
- Category classification
- Framework mappings to all applicable compliance standards
- Licensing requirements (service plan gating)
- Automation status (automated vs. manual)

### FR-013: License-Aware Check Gating

The tool SHALL detect tenant service plans via `Get-MgSubscribedSku` and automatically skip checks that require service plans not present in the tenant (e.g., PIM checks on E3-only tenants). Skipped checks SHALL be reported as "Not Licensed" in the report.

### FR-014: Graph Permission Validation

After the first Graph connection, the tool SHALL validate granted scopes against required scopes and warn about missing permissions, grouped by affected section. App-only auth (where scopes show `.default`) SHALL skip validation gracefully.

### FR-015: Remediation Guidance

Every Fail and Warning finding SHALL include actionable remediation guidance with:
- Specific portal navigation path (e.g., Entra admin center > Security > ...)
- PowerShell command alternative where applicable
- Copy-to-clipboard button in the HTML report

### FR-016: Collector Progress Display

The tool SHALL display real-time streaming progress during execution showing:
- Current section and collector name
- Individual check status as they complete (color-coded)
- Running totals (complete, skipped, failed)

---

## Authentication & Connection Requirements

### FR-020: Multiple Authentication Methods

The tool SHALL support the following authentication methods:

| Method | Description |
|--------|-------------|
| Interactive (browser) | Default browser-based OAuth flow |
| Interactive with UPN | Browser flow with WAM bypass via `-UserPrincipalName` |
| Device code | Code + URL flow for headless environments (`-UseDeviceCode`) |
| Certificate-based | App-only auth with `-ClientId` + `-CertificateThumbprint` |
| Client secret | App-only auth with `-ClientId` + `-ClientSecret` (Graph + PowerBI only) |
| Managed identity | Azure VM/Functions auth (`-ManagedIdentity`) |
| Pre-existing | Skip connections with `-SkipConnection` |

### FR-021: Cloud Environment Support

The tool SHALL support four Microsoft 365 cloud environments:
- Commercial (default)
- GCC (Government Community Cloud)
- GCC High (sovereign endpoints)
- DoD (Department of Defense, sovereign endpoints)

Cloud environment SHALL be auto-detectable from tenant metadata via the public OpenID Connect discovery endpoint.

### FR-022: Lazy Service Connections

Services SHALL be connected only when their first dependent section runs. The connection map:

| Service | Required By |
|---------|-------------|
| Microsoft Graph | Tenant, Identity, Licensing, Intune, Security, Collaboration, Hybrid, Inventory, SOC2, ValueOpportunity |
| Exchange Online | Email, Security, Inventory |
| Purview | Security (DLP), SOC2 |
| Power BI | PowerBI (isolated child process) |

### FR-023: EXO/Purview Mutual Exclusion

Exchange Online and Purview share the `ExchangeOnlineManagement` module and SHALL NOT be connected simultaneously. The orchestrator SHALL automatically disconnect one before connecting the other.

### FR-024: Connection Profiles

The tool SHALL support saved connection profiles (`.m365assess.json`) that store tenant ID, client ID, certificate thumbprint, auth method, and environment. Profiles SHALL be managed via `New-M365ConnectionProfile`, `Get-M365ConnectionProfile`, `Set-M365ConnectionProfile`, and `Remove-M365ConnectionProfile`.

### FR-025: Consent Helper

The tool SHALL provide a `Grant-M365AssessConsent` function that provisions all required Graph permissions, EXO role groups, and compliance directory roles in a single interactive command.

---

## Reporting Requirements

### FR-030: Self-Contained HTML Report

The tool SHALL generate a self-contained HTML report (`_Assessment-Report_<tenant>.html`) that:
- Requires no external assets, CDN, or server to view
- Base64-encodes all images and embeds all CSS/JS inline
- Works in any modern browser (Chrome, Edge, Firefox, Safari)
- Supports light/dark mode with automatic OS detection and manual toggle
- Is print-friendly with automatic page breaks and repeated table headers

### FR-031: Report Sections

The HTML report SHALL include:
- Cover page with branding (optional)
- Organization profile card
- Executive summary with section/collector stat cards
- Identity KPI cards (users, MFA adoption, SSPR enrollment, guests)
- Section-by-section data tables with executive descriptions
- Security config donut charts per domain
- Color-coded status badges with row-level tinting
- Status filter buttons
- Microsoft Secure Score visualization
- Compliance overview with framework selector
- Issues and recommendations with severity badges
- Checks-run appendix for audit trail

### FR-032: Paginated Navigation

The report SHALL provide paginated navigation with:
- Sidebar navigation with section list and status badges
- Hash-based routing for browser back/forward support
- Keyboard arrow navigation
- "Show All" toggle for full-document view
- Mobile hamburger menu

### FR-033: CSV Data Export

Each collector SHALL export raw data as a numbered CSV file. CSV files SHALL use UTF-8 encoding and standard `Export-Csv` format.

### FR-034: XLSX Compliance Matrix

The tool SHALL generate an Excel workbook (`_Compliance-Matrix_<tenant>.xlsx`) with:
- Compliance Matrix sheet: one row per finding with all framework mapping columns
- Summary sheet: pass/fail counts and pass rate per framework

XLSX export requires the optional `ImportExcel` module. The tool SHALL warn and skip XLSX generation if the module is not installed.

### FR-035: Custom Branding / White-Label

The tool SHALL support white-label report generation via:
- `-CustomBranding @{ CompanyName; LogoPath; AccentColor }` for custom branding
- `-NoBranding` for clean reports without M365 Assess branding
- `-SkipCoverPage`, `-SkipExecutiveSummary`, `-SkipComplianceOverview` for layout control

### FR-036: Standalone Report Regeneration

The tool SHALL support regenerating the HTML report from existing CSV data without re-running the assessment, via `Export-AssessmentReport.ps1`.

### FR-037: Framework Catalog Export

The tool SHALL support generating standalone per-framework HTML catalog files via `-FrameworkExport`.

---

## Compliance Framework Requirements

### FR-040: Multi-Framework Mapping

Every automated check SHALL map to one or more controls across the following 15 compliance frameworks:

| # | Framework | Registry Key |
|---|-----------|-------------|
| 1 | CIS M365 v6.0.1 (E3-L1, E3-L2, E5-L1, E5-L2) | `cis-m365-v6` |
| 2 | NIST 800-53 Rev 5 | `nist-800-53` |
| 3 | NIST CSF 2.0 | `nist-csf` |
| 4 | ISO 27001:2022 | `iso-27001` |
| 5 | DISA STIG | `stig` |
| 6 | PCI DSS v4.0.1 | `pci-dss` |
| 7 | CMMC 2.0 | `cmmc` |
| 8 | HIPAA Security Rule | `hipaa` |
| 9 | CISA SCuBA | `cisa-scuba` |
| 10 | SOC 2 TSC | `soc2` |
| 11 | FedRAMP | `fedramp` |
| 12 | Essential Eight | `essential-eight` |
| 13 | CIS Controls v8 | `cis-controls-v8` |
| 14 | MITRE ATT&CK | `mitre-attack` |
| 15 | Entra ID STIG V1R1 | `entra-id-stig` |

### FR-041: CIS Benchmark Scoring

CIS framework profiles (E3-L1, E3-L2, E5-L1, E5-L2) SHALL calculate a compliance score (pass rate) against benchmarked controls. Other frameworks SHALL show coverage mapping.

### FR-042: Framework Filtering

The tool SHALL support limiting the compliance overview to specific framework families via `-FrameworkFilter`.

---

## Security & Privacy Requirements

### FR-050: Read-Only Operations

ALL API operations SHALL use read-only permissions. No write, delete, or modification permissions SHALL be requested or used. The tool SHALL NOT be capable of altering tenant configuration.

### FR-051: No Telemetry

The tool SHALL NOT include analytics, telemetry, usage tracking, or phone-home behavior of any kind.

### FR-052: Local-Only Data Storage

All assessment output (CSV, HTML, XLSX, logs) SHALL be written to the local filesystem only. No assessed tenant data SHALL be transmitted to any third-party endpoint.

### FR-053: No Dynamic Code Execution

The tool SHALL NOT use `Invoke-Expression`, `Add-Type` with compiled C#, dynamic assembly loading, or external script downloads at runtime.

### FR-054: Sensitive Data Handling

- Client secrets SHALL be accepted only as `[SecureString]` parameters
- Connection profiles SHALL NOT store client secrets
- The `.gitignore` SHALL exclude connection profiles, certificates, environment files, and assessment output

---

## Platform & Environment Requirements

### FR-060: PowerShell Version

The tool SHALL require PowerShell 7.0+ (`pwsh`). PowerShell 5.1 is NOT supported.

### FR-061: Required Modules

| Module | Minimum Version | Purpose |
|--------|----------------|---------|
| Microsoft.Graph.Authentication | 2.36.0 | Graph API connectivity |
| ExchangeOnlineManagement | 3.5.0 | Exchange Online and Purview connectivity |

### FR-062: Optional Modules

| Module | Purpose |
|--------|---------|
| ImportExcel | XLSX compliance matrix export |
| MicrosoftPowerBIMgmt | Power BI section |
| ActiveDirectory (RSAT) | Active Directory section |

### FR-063: Module Helper

The tool SHALL detect missing or incompatible modules before connecting to any service, with section-aware detection. Interactive mode SHALL offer repair prompts. Non-interactive mode SHALL log fix commands and exit.

### FR-064: Blocked Script Detection

On Windows, the tool SHALL detect NTFS Zone.Identifier alternate data streams on downloaded files and offer to unblock them (interactive) or log the command (non-interactive).

### FR-065: Platform Support

| Platform | Status |
|----------|--------|
| Windows | Fully tested, primary platform |
| macOS | Experimental |
| Linux | Experimental |

---

## Extensibility Requirements

### FR-070: Standalone Collector Execution

Individual security collectors SHALL be executable standalone after importing the module and connecting to the required service. The module SHALL export 15+ public cmdlets (e.g., `Get-M365EntraSecurityConfig`, `Get-M365ExoSecurityConfig`).

### FR-071: SecurityConfigHelper Contract

All security config collectors SHALL use the shared `SecurityConfigHelper` contract (`Initialize-SecurityConfig`, `Add-SecuritySetting`, `Export-SecurityConfigReport`) for consistent output formatting and status validation.

### FR-072: CIS Benchmark Versioning

The tool SHALL support benchmark version selection via `-CisBenchmarkVersion` to enable future CIS version upgrades (e.g., v7) without breaking existing workflows.

---

## Feature Requirements by Section

### Tenant Section

| Feature | Description |
|---------|-------------|
| Organization profile | Display name, tenant ID, creation date, verified domains |
| Security defaults status | Whether security defaults are enabled or disabled |
| Verified domain enumeration | All domains registered in the tenant |

### Identity Section

| Feature | Description |
|---------|-------------|
| User summary | Total users, licensed, guests, disabled, inactive |
| MFA report | Per-user MFA registration status with method details and strength classification |
| Admin role report | Privileged role assignments including PIM eligibility |
| Conditional Access | CA policy inventory with scope and grant controls |
| CA policy evaluator | 5 automated CA security checks (report-only, named locations, sessions, risk, role coverage) |
| App registrations | App inventory with credential expiry and permission grants |
| Enterprise app security | 21 checks covering dangerous permissions, consent, credentials, reply URIs |
| Password policy | Organization password policies and banned password lists |
| Entra security config | 14+ automated Entra ID security checks |

### Licensing Section

| Feature | Description |
|---------|-------------|
| SKU summary | License allocation, assignment counts, available units |
| Friendly name resolution | Microsoft SKU GUIDs resolved to human-readable names |

### Email Section

| Feature | Description |
|---------|-------------|
| Mailbox summary | Mailbox types, sizes, last logon, forwarding status |
| Mail flow | Transport rules, connectors, accepted domains |
| Email security | Anti-spam, anti-phishing, modern auth, external sender tagging |
| EXO security config | Automated Exchange Online security checks |
| DNS authentication | SPF, DKIM, DMARC, MTA-STS, TLS-RPT validation per domain |
| Mailbox permissions | FullAccess, SendAs, SendOnBehalf delegation audit |

### Intune Section

| Feature | Description |
|---------|-------------|
| Device summary | Managed device inventory with OS, compliance state |
| Compliance policies | Policy inventory with assignment targets |
| Config profiles | Configuration profile inventory |
| Intune security config | Enrollment restrictions, compliance policy checks |

### Security Section

| Feature | Description |
|---------|-------------|
| Secure Score | Current score, max score, M365 global average comparison |
| Improvement actions | Prioritized security recommendations from Microsoft |
| Defender policies | Anti-phishing, anti-spam, anti-malware, Safe Links, Safe Attachments |
| Defender security config | Automated Defender for Office 365 checks with preset policy detection |
| DLP policies | Data loss prevention policy inventory (requires Purview) |
| Compliance security config | Purview compliance configuration checks |
| Purview retention config | Retention policy and label evaluation |
| Stryker incident readiness | 9 incident-readiness checks (stale admins, CA exclusions, break-glass, device wipe audit) |

### Collaboration Section

| Feature | Description |
|---------|-------------|
| SharePoint & OneDrive | Sharing settings, external access, sync restrictions |
| SharePoint security config | 6+ automated sharing, access, and versioning checks |
| Teams access | Meeting policies, guest access, external access |
| Teams security config | 8+ automated Teams configuration checks |
| Forms security config | Phishing protection, data sharing settings |

### PowerBI Section (opt-in)

| Feature | Description |
|---------|-------------|
| Power BI security config | 11 CIS 9.1.x tenant setting checks: guest access, external sharing, publish to web, sensitivity labels |

### Hybrid Section

| Feature | Description |
|---------|-------------|
| Hybrid sync | Microsoft Entra Connect sync status, domain configuration, health |

### Inventory Section (opt-in)

| Feature | Description |
|---------|-------------|
| Mailbox inventory | Per-mailbox detail for M&A due diligence |
| Group inventory | Distribution lists, M365 groups, security groups |
| Teams inventory | Team membership, channels, settings |
| SharePoint inventory | Site collections with storage, sharing, activity |
| OneDrive inventory | Per-user OneDrive accounts with storage usage |

### ActiveDirectory Section (opt-in)

| Feature | Description |
|---------|-------------|
| AD domain & forest | Domain/forest topology, functional levels |
| AD DC health | Domain controller health via dcdiag |
| AD replication | Replication partners and lag |
| AD security | Password policies, privileged group membership |

### SOC2 Section (opt-in)

| Feature | Description |
|---------|-------------|
| Security controls | SOC 2 Trust Services Criteria security control assessment |
| Confidentiality controls | Data confidentiality control evaluation |
| Audit evidence | 30-day audit log evidence collection |
| Readiness checklist | Non-automatable criteria organizational readiness (CC1-CC5, CC8-CC9) |

### ValueOpportunity Section (opt-in)

| Feature | Description |
|---------|-------------|
| License utilization | Identifies features paid for but not used |
| Feature adoption | Measures adoption rates across M365 workloads |
| Feature readiness | Adoption roadmap with quick wins |

---

## See Also

- [User Stories](USER-STORIES.md) — personas and usage scenarios
- [Roadmap](ROADMAP.md) — future enhancements and feature backlog
- [Changelog](../CHANGELOG.md) — release history
- [Authentication](../AUTHENTICATION.md) — auth method details
- [Compliance](../COMPLIANCE.md) — framework mapping details

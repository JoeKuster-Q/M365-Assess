# User Stories

User stories for M365-Assess organized by persona. Each story follows the format: *As a [persona], I want [capability] so that [benefit].*

> **Version:** 1.9.0 | **Last Updated:** 2026-04-14

---

## Table of Contents

1. [Security Administrator](#security-administrator)
2. [Compliance Officer / Auditor](#compliance-officer--auditor)
3. [IT Consultant / vCISO](#it-consultant--vciso)
4. [DevOps / Platform Engineer](#devops--platform-engineer)
5. [IT Manager / Director](#it-manager--director)
6. [M&A Due Diligence Analyst](#ma-due-diligence-analyst)
7. [SOC Analyst / Incident Responder](#soc-analyst--incident-responder)

---

## Security Administrator

### US-SEC-001: Run a Full Security Assessment

**As a** security administrator, **I want** to run a comprehensive security assessment of my M365 tenant with a single command **so that** I can identify configuration gaps and misconfigurations across all M365 services without manually checking each admin portal.

**Acceptance Criteria:**
- Run `Invoke-M365Assessment -TenantId 'contoso.onmicrosoft.com'`
- Assessment covers identity, email, devices, security, collaboration, and hybrid sync
- Output includes CSV data files, an HTML report, and an XLSX compliance matrix
- Total runtime under 10 minutes for a typical SMB tenant

### US-SEC-002: Evaluate MFA Coverage

**As a** security administrator, **I want** to see per-user MFA registration status with method strength classification **so that** I can identify users without MFA and prioritize enrollment of phishing-resistant methods for privileged accounts.

**Acceptance Criteria:**
- MFA report shows registration status, methods, and strength (Phishing-Resistant/Standard/Weak/None)
- Global admin accounts lacking phishing-resistant MFA are flagged as Fail
- Report includes Identity KPI cards showing MFA adoption percentage

### US-SEC-003: Assess Conditional Access Policies

**As a** security administrator, **I want** to evaluate my Conditional Access policies against CIS benchmarks **so that** I can identify gaps in authentication policy coverage, including report-only policies that provide no protection.

**Acceptance Criteria:**
- CA policy inventory with scope, grant controls, and state
- 5 automated CA checks: report-only detection, named location risks, session persistence, risk policy anti-patterns, Tier-0 role coverage gaps
- Findings mapped to CIS, NIST, and CISA SCuBA frameworks

### US-SEC-004: Quick Daily Health Check

**As a** security administrator, **I want** to run a quick scan that evaluates only Critical and High severity checks **so that** I can perform daily posture monitoring without waiting for a full assessment.

**Acceptance Criteria:**
- `-QuickScan` runs only Critical and High severity checks
- Collectors with no qualifying checks are skipped entirely
- Report shows "Quick Scan Mode" banner
- Runtime significantly reduced compared to full scan

### US-SEC-005: Review Defender for Office 365 Configuration

**As a** security administrator, **I want** to evaluate my Defender anti-phishing, anti-spam, anti-malware, Safe Links, and Safe Attachments policies **so that** I can verify all email protection controls are properly configured, including detection of preset security policy coverage.

**Acceptance Criteria:**
- Defender policy inventory with all protection policy details
- Automated checks detect preset security policy (Standard/Strict) coverage
- Preset-managed policies reported as Pass (not false Fail)
- Remediation guidance includes specific portal paths

### US-SEC-006: Audit Enterprise Application Permissions

**As a** security administrator, **I want** to audit enterprise application permissions, consent grants, and credential hygiene **so that** I can identify applications with dangerous Tier-0 permissions that represent attack paths.

**Acceptance Criteria:**
- 21 enterprise app security checks covering dangerous permissions (49 patterns), consent, credentials, reply URIs
- Tier-0 permission classification with attack path analysis
- Verified publisher enforcement checks
- Findings mapped to MITRE ATT&CK techniques

### US-SEC-007: Incident Readiness Evaluation

**As a** security administrator, **I want** to evaluate my tenant's readiness for a ransomware-style attack **so that** I can proactively address the same vectors exploited in real-world incidents (e.g., Stryker Corporation attack).

**Acceptance Criteria:**
- 9 incident readiness checks: stale admins, synced admin accounts, CA exclusions, unprotected role groups, dangerous app permissions, Multi-Admin Approval, RBAC scope tags, break-glass accounts, mass device wipe detection
- Findings mapped to MITRE ATT&CK, NIST, and CISA frameworks

---

## Compliance Officer / Auditor

### US-COMP-001: Multi-Framework Compliance Mapping

**As a** compliance officer, **I want** every security finding mapped to controls across 15 compliance frameworks simultaneously **so that** I can demonstrate compliance posture to auditors without manually cross-referencing each standard.

**Acceptance Criteria:**
- Every automated check maps to applicable controls in CIS, NIST 800-53, NIST CSF, ISO 27001, STIG, PCI DSS, CMMC, HIPAA, CISA SCuBA, SOC 2, FedRAMP, Essential Eight, CIS Controls v8, MITRE ATT&CK, and Entra ID STIG
- CIS profiles show compliance scores (pass rates)
- Other frameworks show coverage mapping
- Interactive framework selector in HTML report

### US-COMP-002: XLSX Compliance Matrix for Auditors

**As an** auditor, **I want** to export an Excel compliance matrix with per-control framework alignment evidence **so that** I can provide a structured evidence artifact to external audit firms.

**Acceptance Criteria:**
- `_Compliance-Matrix_<tenant>.xlsx` generated with ImportExcel module
- Sheet 1: one row per finding with all 15 framework mapping columns
- Sheet 2: pass/fail counts and pass rate per framework
- Color-coded status cells
- RiskSeverity column (Critical/High/Medium/Low)

### US-COMP-003: SOC 2 Readiness Assessment

**As a** compliance officer, **I want** to run a SOC 2 Trust Services Criteria assessment **so that** I can evaluate our security and confidentiality controls, collect audit evidence, and identify gaps in organizational readiness before a formal SOC 2 audit.

**Acceptance Criteria:**
- Security controls assessment against TSC criteria
- Confidentiality controls evaluation
- 30-day audit log evidence collection
- Readiness checklist for non-automatable criteria (CC1-CC5, CC8-CC9)

### US-COMP-004: Framework-Filtered Reports

**As a** compliance officer, **I want** to generate a report filtered to specific frameworks (e.g., only HIPAA, only PCI DSS) **so that** I can produce focused compliance evidence for a specific regulatory requirement.

**Acceptance Criteria:**
- `-FrameworkFilter HIPAA` limits compliance overview to HIPAA controls
- Standalone framework catalog HTML export via `-FrameworkExport`
- Per-framework coverage cards with pass rates

### US-COMP-005: Audit Trail of Checks Executed

**As an** auditor, **I want** a complete list of every security check that was executed during the assessment **so that** I can verify the scope and completeness of the evaluation.

**Acceptance Criteria:**
- Checks-run appendix at end of HTML report
- Lists every check with CheckId, Setting, Category, Status, and Section
- Assessment summary CSV with per-collector status

---

## IT Consultant / vCISO

### US-CONSULT-001: Branded Client Reports

**As an** IT consultant, **I want** to generate white-label assessment reports with my company's branding **so that** I can deliver professional, branded deliverables to clients without post-processing.

**Acceptance Criteria:**
- `-CustomBranding @{ CompanyName = '...'; LogoPath = '...'; AccentColor = '#...' }`
- Company name appears on cover page and report headers
- Custom logo replaces M365 Assess logo
- Accent color applied to UI elements throughout
- `-NoBranding` removes all third-party branding

### US-CONSULT-002: Multi-Tenant Workflow

**As a** vCISO managing multiple clients, **I want** to save connection profiles per tenant **so that** I can quickly switch between client environments without re-entering credentials.

**Acceptance Criteria:**
- `New-M365ConnectionProfile -ProfileName 'ClientA' -TenantId '...' -AuthMethod Certificate -ClientId '...' -CertificateThumbprint '...'`
- `Invoke-M365Assessment -ConnectionProfile 'ClientA'`
- Profiles stored in `.m365assess.json` (excluded from git)
- CRUD operations: New, Get, Set, Remove

### US-CONSULT-003: Section-Specific Assessments

**As an** IT consultant, **I want** to run only specific sections relevant to a client engagement **so that** I can deliver focused assessments (e.g., email security only) without running unnecessary collectors.

**Acceptance Criteria:**
- `-Section Identity,Email` runs only those sections
- Service connections are lazy — only required services connect
- Report includes only the selected sections

### US-CONSULT-004: Regenerate Reports from Existing Data

**As an** IT consultant, **I want** to regenerate the HTML report from existing CSV data **so that** I can apply branding changes or test report layout without re-running the full assessment.

**Acceptance Criteria:**
- `Export-AssessmentReport.ps1 -AssessmentFolder '.\Assessment_...'` regenerates the report
- Works offline — no M365 connection needed
- Applies current branding settings

---

## DevOps / Platform Engineer

### US-DEVOPS-001: Automated Pipeline Assessment

**As a** DevOps engineer, **I want** to run M365 security assessments in a CI/CD pipeline **so that** I can continuously monitor posture and detect configuration drift.

**Acceptance Criteria:**
- Certificate-based auth with `-NonInteractive` for zero-prompt execution
- Managed identity support for Azure-hosted runners
- Exit code indicates success/failure for pipeline gating
- Assessment log captures all details for pipeline artifact storage

### US-DEVOPS-002: Pre-Flight Validation

**As a** DevOps engineer, **I want** to validate my pipeline setup before running a full assessment **so that** I can catch module, permission, and connectivity issues early.

**Acceptance Criteria:**
- `-DryRun` previews sections, services, scopes, and check counts
- Module helper detects missing/incompatible modules before connecting
- Graph permission validation warns about missing scopes after connection

### US-DEVOPS-003: GCC High / DoD Deployment

**As a** platform engineer in a government environment, **I want** to run assessments against GCC High and DoD tenants **so that** I can assess sovereign cloud environments with correct endpoint routing.

**Acceptance Criteria:**
- `-M365Environment gcchigh` routes all connections to sovereign endpoints
- Auto-detection via OpenID Connect discovery
- Graph, Exchange Online, and Purview all use correct sovereign URLs

---

## IT Manager / Director

### US-MGR-001: Executive Summary Dashboard

**As an** IT manager, **I want** an executive summary with key metrics and visual charts **so that** I can quickly understand our security posture without reading detailed technical findings.

**Acceptance Criteria:**
- Executive summary with section/collector stat cards
- Identity KPIs: total users, MFA adoption %, SSPR enrollment %, guest count
- Service-area breakdown chart (pass/fail/warning/review per area)
- Microsoft Secure Score with global average comparison
- Organization profile card

### US-MGR-002: Secure Score Tracking

**As an** IT manager, **I want** to see our Microsoft Secure Score with comparison to the M365 global average **so that** I can benchmark our security posture against peers.

**Acceptance Criteria:**
- Current score, max score, and percentage displayed
- Visual progress bar
- M365 global average comparison
- Improvement actions prioritized by impact

### US-MGR-003: License Utilization Visibility

**As an** IT manager, **I want** to understand which M365 features we pay for but don't use **so that** I can optimize license spend and drive adoption of underutilized capabilities.

**Acceptance Criteria:**
- License utilization analysis showing paid vs. used features
- Feature adoption rates across M365 workloads
- Adoption roadmap with quick wins
- Value opportunity report section in HTML output

---

## M&A Due Diligence Analyst

### US-MA-001: Per-Object Inventory Export

**As an** M&A analyst, **I want** detailed per-object inventory of mailboxes, groups, Teams, SharePoint sites, and OneDrive accounts **so that** I can assess the scope and complexity of a target organization's M365 footprint.

**Acceptance Criteria:**
- `-Section Inventory` enables inventory collectors
- Per-mailbox, per-group, per-team, per-site, per-OneDrive CSV exports
- Includes storage usage, activity dates, membership counts
- Data suitable for migration planning tools

---

## SOC Analyst / Incident Responder

### US-SOC-001: Detect Compromised Configuration Indicators

**As a** SOC analyst, **I want** to identify configuration indicators of compromise **so that** I can detect whether an attacker has modified tenant settings during an incident.

**Acceptance Criteria:**
- Hidden mailbox detection (hidden from GAL — MITRE T1564)
- Stale admin account detection (inactive >90 days)
- On-prem synced admin account detection (compromise path)
- Mass device wipe activity detection
- Unprotected groups in privileged role assignments

### US-SOC-002: Audit Log Evidence Collection

**As an** incident responder, **I want** to collect 30 days of audit log evidence **so that** I can investigate security incidents with historical data.

**Acceptance Criteria:**
- SOC2 section collects audit log evidence
- 30-day evidence window
- Structured export for forensic analysis

---

## See Also

- [Requirements](REQUIREMENTS.md) — functional and feature requirements
- [Roadmap](ROADMAP.md) — future enhancements and feature backlog
- [Changelog](../CHANGELOG.md) — release history

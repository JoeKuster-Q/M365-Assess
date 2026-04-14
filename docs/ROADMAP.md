# Roadmap & Future Enhancements

This document tracks planned enhancements, feature requests, and the long-term vision for M365-Assess. Items are organized by priority tier and feature area.

> **Last Updated:** 2026-04-14 | **Current Version:** 1.9.0

---

## Table of Contents

1. [Completed (Current Release)](#completed-current-release)
2. [Tier 1 — Near-Term Enhancements](#tier-1--near-term-enhancements)
3. [Tier 2 — Medium-Term Features](#tier-2--medium-term-features)
4. [Tier 3 — Long-Term Vision](#tier-3--long-term-vision)
5. [Feature Requests](#feature-requests)
6. [Change Log Summary](#change-log-summary)

---

## Completed (Current Release)

Items shipped in v1.9.0 and earlier. See [CHANGELOG.md](../CHANGELOG.md) for full details.

- [x] 214 automated security checks across 15 compliance frameworks
- [x] 13 assessment sections (9 default + 4 opt-in)
- [x] Self-contained HTML report with light/dark mode, paginated navigation, and donut charts
- [x] XLSX compliance matrix with per-framework pass rates
- [x] 6 authentication methods (interactive, device code, certificate, client secret, managed identity, pre-existing)
- [x] 4 cloud environments (commercial, GCC, GCC High, DoD)
- [x] Interactive wizard with section selection, auth method, and report options
- [x] Connection profiles for multi-tenant workflows
- [x] QuickScan mode for CI/CD (Critical + High only)
- [x] DryRun preview mode
- [x] License-aware check gating via service plan detection
- [x] Graph permission validation after connection
- [x] Custom branding / white-label reports
- [x] SecurityConfigHelper contract across all 15 collectors
- [x] 21 enterprise app security checks with Tier-0 permission classification
- [x] Stryker incident readiness checks (9 attack-vector checks)
- [x] SOC 2 Trust Services Criteria assessment with audit evidence collection
- [x] Value Opportunity analysis (license utilization, feature adoption)
- [x] Module helper with interactive repair and non-interactive logging
- [x] Connection retry with exponential back-off (up to 6 attempts)
- [x] Verbose diagnostic logging for connection failures
- [x] Standalone collector cmdlets (15 exported functions)
- [x] Power BI child-process isolation (MSAL conflict avoidance)
- [x] DNS prefetch in background thread jobs
- [x] Comprehensive troubleshooting guide including connection failure debugging

---

## Tier 1 — Near-Term Enhancements

High-impact items for the next 1–2 releases.

### T1-001: CIS Benchmark v7.0 Support

- [ ] Update `controls/registry.json` with CIS M365 v7.0 control mappings when released
- [ ] Add new automated checks for any new v7.0 controls
- [ ] `-CisBenchmarkVersion v7` parameter already wired — activate mappings
- [ ] Dual-version scoring: allow running v6 and v7 simultaneously for transition period

### T1-002: PDF Report Generation Improvements

- [ ] Evaluate Playwright/Chromium-based PDF rendering as alternative to wkhtmltopdf
- [ ] Improve page break logic for security config tables that span multiple pages
- [ ] Add PDF-specific cover page layout optimized for A4/Letter

### T1-003: Remediation Script Generation

- [ ] Generate per-finding PowerShell remediation scripts (not just copy-to-clipboard snippets)
- [ ] Export a consolidated `Remediation-Runbook.ps1` with all Fail findings
- [ ] Include `-WhatIf` mode and confirmation prompts for safety
- [ ] Map remediation scripts to Entra admin center portal paths as fallback

### T1-004: Enhanced Progress Display

- [ ] Add estimated time remaining based on historical section timing
- [ ] Show percentage completion in terminal title bar
- [ ] Support `-Verbose` flag propagation to all collectors for detailed diagnostic output

### T1-005: macOS and Linux Hardening

- [ ] Expand cross-platform CI testing to cover all collectors on macOS and Linux
- [ ] Handle platform-specific MSAL/broker differences (WAM is Windows-only)
- [ ] Validate DNS resolution helpers on all platforms

---

## Tier 2 — Medium-Term Features

Features requiring architectural work, planned for 2–4 releases out.

### T2-001: App Registration Automation & Scheduled Daily Assessments

- [ ] **Interactive vs. App Registration selection** — on launch, prompt user to either run with their interactive login permissions or select/create a dedicated app registration
- [ ] **Guided app registration setup** — step-by-step wizard that:
  - Creates the Entra ID app registration with a descriptive name (e.g., `M365-Assess-DailyMonitor`)
  - Assigns all required Graph application permissions from `PermissionDefinitions.ps1`
  - Assigns Exchange Online role group membership (`View-Only Organization Management`)
  - Assigns compliance directory roles (`Compliance Administrator`, `Security Reader`, `Global Reader`)
  - Grants admin consent programmatically
  - Generates a self-signed certificate or client secret
  - Stores credentials securely (Windows: DPAPI/Certificate Store; Linux/macOS: encrypted file with OS keychain)
- [ ] **Credential storage documentation** — comprehensive guide covering:
  - Creating the app registration in the Entra admin center (manual path)
  - Generating and rotating client secrets with expiry warnings
  - Certificate-based auth setup (self-signed and CA-issued)
  - Storing secrets securely: Windows Certificate Store, Azure Key Vault, environment variables
  - Secret rotation best practices and expiry monitoring
- [ ] **Scheduled daily execution** — automate recurring assessments:
  - Windows Task Scheduler integration (`Register-ScheduledTask` wrapper)
  - Linux/macOS cron job generation
  - Azure Automation runbook template
  - GitHub Actions workflow template for cloud-hosted scheduling
  - Pre-flight validation before each scheduled run (module check, certificate expiry, connectivity)
- [ ] **Configuration drift detection** — compare today's scan against the previous baseline:
  - Delta report highlighting settings that changed since last run
  - Severity classification of drift (e.g., MFA disabled for a Global Admin = Critical)
  - Email/webhook notification on drift detection
  - Configurable drift thresholds (alert only on Fail → Pass or Pass → Fail transitions)

### T2-002: Aggregate Reports & Configuration Change Tracking

- [ ] **Multi-run comparison** — generate a report that overlays results from two or more assessment runs:
  - Side-by-side status comparison per CheckId across runs
  - Trend visualization: pass rate over time as line/area charts
  - Regression detection: checks that went from Pass to Fail
  - Improvement tracking: checks that went from Fail to Pass
- [ ] **Trend dashboard** — HTML report page (or standalone) showing:
  - Secure Score trend line over time
  - Per-framework compliance score trend
  - Per-section pass rate trend
  - New findings vs. resolved findings per run
- [ ] **CSV/JSON diff export** — machine-readable delta between any two runs for integration with:
  - SIEM systems (Splunk, Sentinel, Elastic)
  - ITSM platforms (ServiceNow, Jira) for automated ticket creation
  - Custom dashboards and alerting pipelines
- [ ] **Baseline snapshot** — save a "golden" baseline configuration and compare all future runs against it:
  - `Save-M365AssessBaseline -AssessmentFolder ./Assessment_...` to snapshot
  - `Compare-M365AssessBaseline -Current ./Assessment_new -Baseline ./Baseline_...` to diff

### T2-003: SQLite Local Data Store

- [ ] **Local SQLite database** — write all assessment results into a SQLite database for long-term tracking:
  - Auto-create database on first run (`M365-Assess.db` alongside output folder, or configurable path)
  - Schema: `Runs` table (RunId, TenantId, Timestamp, Sections, Version), `Findings` table (RunId, CheckId, Status, Setting, Value, Remediation), `Scores` table (RunId, Framework, PassCount, FailCount, PassRate)
  - Each assessment run inserts a new row set — historical data accumulates automatically
  - `-SqlitePath` parameter on `Invoke-M365Assessment` to specify database location
  - No additional module dependency — use `System.Data.SQLite` or `Microsoft.Data.Sqlite` via .NET (ships with PowerShell 7)
- [ ] **Query interface** — helper cmdlets for common lookups:
  - `Get-M365AssessHistory -TenantId ... -Last 30` — list recent runs
  - `Get-M365AssessTrend -CheckId 'ENTRA-ADMIN-001' -Last 90` — status history for a check
  - `Compare-M365AssessRuns -RunId1 ... -RunId2 ...` — diff two runs
  - `Export-M365AssessTimeline -TenantId ... -Format CSV|JSON` — export trend data
- [ ] **Data retention** — configurable retention policy:
  - Default: keep all runs indefinitely
  - `-RetentionDays 365` to auto-prune runs older than N days
  - Manual cleanup: `Remove-M365AssessRun -RunId ...`

### T2-004: Power BI Report on SQLite Data

- [ ] **Power BI template** — `.pbit` template file that connects to the local SQLite database:
  - Pre-built data model with relationships between Runs, Findings, and Scores tables
  - Dashboard pages: Executive Summary, Compliance Trend, Drift Detection, Per-Section Deep Dive
  - Parameterized connection: user points to their `M365-Assess.db` file on first open
  - Slicers for tenant, date range, framework, section, and severity
- [ ] **Visualizations** included:
  - Compliance score trend line per framework over time
  - Heat map: CheckId × Run Date with color-coded status
  - Regression waterfall: net new Fails vs. resolved Fails per run
  - Secure Score trend with M365 global average benchmark line
  - Top 10 most frequently failing checks across all runs
  - Drift alert table: findings that changed status since previous run
- [ ] **Refresh workflow** — after each assessment run, Power BI Desktop can refresh from the updated SQLite file; document the refresh process and any gateway requirements for Power BI Service publishing
- [ ] **Export to Power BI Service** — optional: publish the report to Power BI Service for team-wide access with scheduled refresh via on-premises data gateway pointing at the local SQLite file

### T2-005: Webhook & Notification Integration

- [ ] Send assessment summary via email (SMTP or Graph Mail.Send)
- [ ] Webhook support for Microsoft Teams, Slack, and generic HTTP endpoints
- [ ] Configurable notification triggers (any failure, new regressions only, score drop below threshold)

### T2-006: Multi-Tenant Aggregate View

- [ ] Run assessments across multiple tenants in sequence
- [ ] Generate a cross-tenant comparison report
- [ ] Connection profile batch execution (`Invoke-M365Assessment -ConnectionProfile 'Client1','Client2','Client3'`)

---

## Tier 3 — Long-Term Vision

Exploratory features that may require significant architecture changes.

### T3-001: Web Dashboard

- [ ] Lightweight web UI (single-page app) for browsing assessment results
- [ ] Read from SQLite database or JSON export
- [ ] Real-time assessment progress via WebSocket
- [ ] No server dependency — runs locally via `pwsh -Command Start-M365AssessDashboard`

### T3-002: Azure-Native Deployment

- [ ] Azure Function App template for serverless scheduled assessments
- [ ] Azure Automation runbook with managed identity
- [ ] Results stored in Azure Table Storage or Cosmos DB
- [ ] Azure Monitor alerts for compliance drift

### T3-003: Plugin Architecture

- [ ] Allow third-party collector plugins (e.g., custom checks for org-specific policies)
- [ ] Plugin discovery via a `plugins/` directory
- [ ] Plugin manifest format for registry integration and framework mapping

### T3-004: AI-Powered Remediation Guidance

- [ ] Integrate with Azure OpenAI or local LLM for contextual remediation explanations
- [ ] Natural language risk summaries for executive audiences
- [ ] Priority scoring based on tenant-specific risk factors (user count, industry, compliance requirements)

### T3-005: Incremental / Differential Scans

- [ ] Track which settings changed since last scan and only re-evaluate those
- [ ] Dramatically reduce scan time for daily monitoring (seconds instead of minutes)
- [ ] Requires SQLite or baseline snapshot to detect changes

---

## Feature Requests

Community and internal feature requests pending triage.

| # | Request | Source | Status |
|---|---------|--------|--------|
| FR-001 | App registration guided setup with secure credential storage | Internal | Planned → T2-001 |
| FR-002 | Automated daily scheduled assessments for configuration drift tracking | Internal | Planned → T2-001 |
| FR-003 | Aggregate reports to track configuration changes over time | Internal | Planned → T2-002 |
| FR-004 | SQLite local database for long-term scan result storage and comparison | Internal | Planned → T2-003 |
| FR-005 | Power BI report template scanning SQLite database for trend analysis | Internal | Planned → T2-004 |
| FR-006 | CIS v7.0 benchmark support | Community | Planned → T1-001 |
| FR-007 | SCIM-based user inventory | Community | Backlog |
| FR-008 | Microsoft Sentinel integration for real-time alerting | Community | Backlog |
| FR-009 | Entra ID Governance checks (access reviews, entitlement management) | Community | Backlog |
| FR-010 | Microsoft Purview Information Protection (sensitivity labels) checks | Community | Backlog |
| FR-011 | Cross-platform binary distribution (no git clone required) | Community | Backlog |

---

## Change Log Summary

Key milestones in the project's evolution. See [CHANGELOG.md](../CHANGELOG.md) for the complete release history.

| Version | Date | Highlights |
|---------|------|------------|
| **1.9.0** | 2026-04-07 | QuickScan triage report format, DNS false-positive fix for .onmicrosoft.com |
| **1.8.0** | 2026-04-07 | 6 new SharePoint checks, device code token expiry detection |
| **1.7.0** | 2026-04-06 | DryRun switch, 5 new CA checks, license-skipped check details |
| **1.6.0** | 2026-04-03 | Value Opportunity integration, SKU feature map with real service plan IDs |
| **1.5.0** | 2026-04-03 | License-aware check gating, QuickScan, Security Defaults gap analysis, 21 app security checks, Entra ID STIG |
| **1.2.0** | 2026-04-02 | Admin MFA strength, paginated report, service-area chart, inline callouts |
| **1.1.0** | 2026-04-01 | SecurityConfigHelper contract, 13 public cmdlets, Graph scope validation, mailbox delegation audit |
| **1.0.0** | 2026-03-30 | First public release, module structure, 37 Pester tests, accessibility improvements |
| **0.9.9** | 2026-03-29 | Repo restructure to `src/M365-Assess/`, orchestrator decomposition |
| **0.9.8** | 2026-03-20 | Stryker Incident Readiness (9 checks), MITRE ATT&CK mappings |
| **0.9.0** | 2026-03-14 | Power BI section, managed identity, client secret auth |
| **0.8.0** | 2026-03-14 | CA evaluator, DNS security, Intune security, Defender checks |
| **0.6.0** | 2026-03-11 | Multi-framework scanner, SOC 2, XLSX compliance matrix |
| **0.3.0** | 2026-03-08 | Initial release — 8 sections, HTML report, interactive wizard |

---

## See Also

- [Requirements](REQUIREMENTS.md) — functional and feature requirements specification
- [User Stories](USER-STORIES.md) — personas and usage scenarios
- [Changelog](../CHANGELOG.md) — complete release history with per-version details
- [Contributing](../CONTRIBUTING.md) — how to submit enhancements and bug fixes

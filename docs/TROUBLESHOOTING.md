# Troubleshooting Guide

Common issues when running M365-Assess and how to resolve them.

> **Tip:** Most issues stem from module version conflicts or missing permissions.
> If you are new to M365-Assess, start with the [Quickstart Guide](QUICKSTART.md).

---

## Table of Contents

1. [Graph Permission Errors](#1-graph-permission-errors)
2. [EXO MSAL Assembly Conflicts](#2-exo-msal-assembly-conflicts)
3. [Execution Policy / Blocked Scripts](#3-execution-policy--blocked-scripts)
4. [Module Version Conflicts](#4-module-version-conflicts)
5. [Non-Interactive Mode Failures](#5-non-interactive-mode-failures)
6. [Power BI Connection Issues](#6-power-bi-connection-issues)
7. [Connection Failed Errors (ExchangeOnline / Purview)](#7-connection-failed-errors-exchangeonline--purview)

---

## 1. Graph Permission Errors

[Back to top](#table-of-contents)

### Symptom

- HTTP 401 (Unauthorized) or 403 (Forbidden) errors during assessment
- Messages like `Insufficient privileges to complete the operation`
- Collectors return empty results for sections that should have data

### Cause

The app registration (or delegated session) does not have the required Microsoft Graph scopes, or an admin has not granted tenant-wide consent for the requested permissions.

### Resolution

**Option A -- Use the consent helper (recommended):**

```powershell
Grant-M365AssessConsent
```

This opens an interactive consent prompt for all scopes the assessment requires. A Global Administrator must approve the consent.

**Option B -- Grant permissions manually in the Entra admin center:**

1. Go to **Entra admin center** > **App registrations** > your app > **API permissions**
2. Add all Microsoft Graph application permissions listed in [AUTHENTICATION.md](../AUTHENTICATION.md)
3. Click **Grant admin consent for \<tenant\>**
4. Wait 1--2 minutes for propagation, then retry the assessment

**Verify permissions are applied:**

```powershell
# List the scopes your current session holds
(Get-MgContext).Scopes | Sort-Object
```

---

## 2. EXO MSAL Assembly Conflicts

[Back to top](#table-of-contents)

### Symptom

- `Could not load type 'Microsoft.Identity.Client.AuthenticationResult'`
- `Could not load file or assembly 'Microsoft.Identity.Client, Version=4.x...'`
- Assessment fails immediately after connecting to Exchange Online

### Cause

Older versions of the Microsoft.Graph SDK (< 2.36.0) shipped a version of `Microsoft.Identity.Client` (MSAL) that conflicted with the version bundled in ExchangeOnlineManagement 3.8.0+. PowerShell cannot load two different versions of the same assembly in one session.

### Resolution

**Upgrade to Graph SDK 2.36.0 or later** (recommended):

```powershell
# Remove older Graph SDK versions
Get-Module Microsoft.Graph* -ListAvailable |
    ForEach-Object { Uninstall-Module $_.Name -AllVersions -Force -ErrorAction SilentlyContinue }

# Install latest Graph SDK (2.36.0+ resolves the MSAL conflict)
Install-Module Microsoft.Graph -Force
```

Graph SDK 2.36.0 updated `Microsoft.Identity.Client` to 4.82.1 and improved its assembly resolution, eliminating conflicts with EXO 3.8.0+ in the same session.

After upgrading, **close and reopen your PowerShell session** before running the assessment. Assemblies loaded in the current session persist until the process exits.

**Verify the installed version:**

```powershell
Get-Module Microsoft.Graph.Authentication -ListAvailable | Select-Object Name, Version
# Version should be 2.36.0 or later
```

---

## 3. Execution Policy / Blocked Scripts

[Back to top](#table-of-contents)

### Symptom

- `File C:\...\M365-Assess.psm1 cannot be loaded because running scripts is disabled on this system`
- `File C:\...\Invoke-M365Assessment.ps1 is not digitally signed. The script will not execute on the system.`

### Cause

Windows applies a Zone.Identifier alternate data stream (ADS) to files downloaded from the internet (including GitHub releases and `Save-Module`). The default execution policy (`Restricted` or `AllSigned`) blocks these files.

### Resolution

**Option A -- Unblock the downloaded files:**

```powershell
# Unblock all files in the module directory
Get-ChildItem -Path (Get-Module M365-Assess -ListAvailable).ModuleBase -Recurse |
    Unblock-File
```

**Option B -- Set execution policy for your user:**

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

`RemoteSigned` allows local scripts to run and requires downloaded scripts to be either signed or unblocked. This is the recommended policy for development and assessment workstations.

**Verify the current policy:**

```powershell
Get-ExecutionPolicy -List
```

---

## 4. Module Version Conflicts

[Back to top](#table-of-contents)

### Symptom

- `Method not found: 'Void Microsoft.Graph...'`
- `Could not load type 'Microsoft.Graph.PowerShell.Models...'`
- `The term 'Get-MgUser' is not recognized` (even though the module is installed)

### Cause

Multiple versions of the Microsoft.Graph SDK sub-modules are installed side by side. PowerShell may load mismatched versions (e.g., `Microsoft.Graph.Authentication` v2.x with `Microsoft.Graph.Users` v1.x), causing type and method resolution failures.

### Resolution

**Step 1 -- Identify installed versions:**

```powershell
Get-Module Microsoft.Graph* -ListAvailable |
    Select-Object Name, Version, ModuleBase |
    Sort-Object Name
```

**Step 2 -- Remove older versions:**

```powershell
# Remove ALL versions, then reinstall the latest
Get-Module Microsoft.Graph* -ListAvailable |
    ForEach-Object { Uninstall-Module $_.Name -AllVersions -Force -ErrorAction SilentlyContinue }

Install-Module Microsoft.Graph -Force
```

**Step 3 -- Restart PowerShell** and confirm a single version is loaded:

```powershell
Get-Module Microsoft.Graph.Authentication -ListAvailable
```

> **Important:** Always close and reopen your PowerShell session after uninstalling or
> reinstalling Graph modules. Assemblies from the old version remain loaded until the
> process exits.

---

## 5. Non-Interactive Mode Failures

[Back to top](#table-of-contents)

### Symptom

- `Required modules are missing or incompatible`
- Assessment exits immediately when running in CI pipelines or scheduled tasks
- `A command that prompts the user failed because the host does not support user interaction`

### Cause

When `-NonInteractive` is used (or when running in a non-interactive host such as Azure DevOps agents or GitHub Actions), M365-Assess cannot prompt to install missing modules. All required modules must be pre-installed before the assessment runs.

### Resolution

**Pre-install all required modules in your automation script or pipeline setup step:**

```powershell
# Install required modules (run once during pipeline setup)
$modules = @(
    @{ Name = 'Microsoft.Graph.Authentication' }
    @{ Name = 'Microsoft.Graph.Users' }
    @{ Name = 'Microsoft.Graph.Groups' }
    @{ Name = 'Microsoft.Graph.Identity.DirectoryManagement' }
    @{ Name = 'Microsoft.Graph.Identity.SignIns' }
    @{ Name = 'Microsoft.Graph.Identity.Governance' }
    @{ Name = 'Microsoft.Graph.Security' }
    @{ Name = 'Microsoft.Graph.Applications' }
    @{ Name = 'ExchangeOnlineManagement' }
)

foreach ($mod in $modules) {
    if (-not (Get-Module $mod.Name -ListAvailable)) {
        Install-Module @mod -Force -Scope CurrentUser
    }
}
```

**Authenticate using certificate-based auth for unattended runs:**

```powershell
Invoke-M365Assessment -TenantId <tenant-id> `
    -ClientId <app-id> `
    -CertificateThumbprint <thumbprint> `
    -NonInteractive
```

> **Note:** Certificate-based authentication requires an Entra ID app registration
> with the appropriate application permissions (not delegated).

---

## 6. Power BI Connection Issues

[Back to top](#table-of-contents)

### Symptom

- `Login-PowerBIServiceAccount` times out or hangs
- `The operation has timed out` after 90 seconds
- Power BI section returns no data in non-interactive pipelines

### Cause

The `MicrosoftPowerBIMgmt` module supports interactive, certificate, and client secret authentication, but does not support device code or managed identity. Connection issues typically occur in headless environments where interactive login is expected but no browser is available.

### Resolution

**Option A -- Exclude the Power BI section:**

```powershell
Invoke-M365Assessment -Section Tenant,Identity,Licensing,Email,Intune,Security,Collaboration,Hybrid
```

Omit `PowerBI` from the `-Section` list when running in CI/CD or any non-interactive context.

**Option B -- Authenticate interactively before running the assessment:**

```powershell
# Connect to Power BI first in an interactive session
Connect-PowerBIServiceAccount

# Then run the assessment -- it will reuse the existing session
Invoke-M365Assessment
```

**Option C -- Run Power BI separately:**

If you need Power BI data but run most sections non-interactively, run two passes:

1. Run the full assessment without `PowerBI` in your `-Section` list in your pipeline
2. Run a second interactive pass with only the Power BI section enabled

---

## 7. Connection Failed Errors (ExchangeOnline / Purview)

[Back to top](#table-of-contents)

### Symptom

The assessment summary shows one or both of these issues:

```
--- Issues (2) -----------------------------------------
  X Email — ExchangeOnline connection failed
  X Security — Purview connection failed
```

The affected sections' collectors are skipped, but the rest of the assessment completes normally. The full error details appear in the `_Assessment-Log_<tenant>.txt` file in the output folder.

### How It Works

M365-Assess connects to services lazily — each service is connected only when its first dependent section runs. Exchange Online is used by the **Email**, **Security**, and **Inventory** sections. Purview (Security & Compliance) is used by the **Security** and **SOC2** sections. If a connection fails, the tool records the failure, skips all collectors that depend on that service, and continues with the rest of the assessment.

Exchange Online and Purview share the `ExchangeOnlineManagement` module and **cannot be connected simultaneously**. The orchestrator automatically disconnects one before connecting the other. If the first connection succeeds but the second fails, it may indicate a re-authentication issue.

---

### Diagnostic Checklist

Work through each area below. Most connection failures are caused by missing permissions, unsupported auth methods, or network restrictions.

#### A. Check the Log File First

Open the `_Assessment-Log_<tenant>.txt` file (path shown in the console output) and search for `connection failed`. The line immediately after contains the underlying error message. Common patterns:

| Log Pattern | Likely Cause | Jump To |
|-------------|--------------|---------|
| `401` or `Unauthorized` | Missing permissions or expired token | [Section B](#b-permissions--role-assignments) |
| `403` or `Forbidden` or `Insufficient privileges` | Account lacks required role | [Section B](#b-permissions--role-assignments) |
| `WAM` or `RuntimeBroker` | Windows broker conflict | [Section D](#d-authentication-method) |
| `client secret` | Unsupported auth method for EXO/Purview | [Section D](#d-authentication-method) |
| `timeout` or `timed out` | Network or firewall block | [Section C](#c-network--firewall) |
| `Could not load type` or `assembly` | Module version conflict | [Section 2](#2-exo-msal-assembly-conflicts) / [Section 4](#4-module-version-conflicts) |
| `not recognized` or `not installed` | Missing module | [Section E](#e-module-installation) |
| `device code` and `Purview` | Purview doesn't support device code | [Section D](#d-authentication-method) |

---

#### B. Permissions & Role Assignments

Connection failures due to insufficient permissions typically occur in app-only (certificate/managed identity) scenarios but can also affect interactive sessions with non-admin accounts.

**Exchange Online Checklist:**

- [ ] **Interactive auth:** The signed-in user has the **Exchange Administrator** or **Global Reader** Entra ID directory role
- [ ] **App-only (certificate) auth:** The app registration's service principal is a member of the **View-Only Organization Management** EXO role group
- [ ] **App-only (certificate) auth:** The app registration has the `Exchange.ManageAsApp` application permission
- [ ] **Managed identity:** The managed identity's service principal is a member of the **View-Only Organization Management** EXO role group
- [ ] Admin consent has been granted for the required permissions (`Grant admin consent` button clicked in the Entra admin center)
- [ ] Wait 1–5 minutes after granting permissions — propagation is not instant

**Purview Checklist:**

- [ ] **Interactive auth:** The signed-in user has one of: **Compliance Administrator**, **Security Reader**, or **Global Reader** Entra ID directory role
- [ ] **App-only (certificate) auth:** The app registration's service principal has the **Compliance Administrator** directory role assigned
- [ ] **App-only (certificate) auth:** The app registration's service principal has the **Security Reader** directory role assigned
- [ ] The **Global Reader** directory role covers gaps across both Exchange Online and Purview — assign it if unsure which specific roles are missing
- [ ] Role assignments propagated (wait 1–5 minutes after assigning)

**Verify role assignments:**

```powershell
# Check Entra directory roles for a service principal (app-only)
$sp = Get-MgServicePrincipal -Filter "appId eq '<your-client-id>'"
Get-MgServicePrincipalMemberOf -ServicePrincipalId $sp.Id |
    ForEach-Object { Get-MgDirectoryObject -DirectoryObjectId $_.Id } |
    Select-Object @{N='Role';E={$_.AdditionalProperties.displayName}}

# Check EXO role group membership
Get-RoleGroupMember -Identity 'View-Only Organization Management' |
    Where-Object { $_.Name -match '<your-app-name-or-sp-id>' }
```

**Quick fix — use the consent helper:**

```powershell
# Grants all required Graph permissions, EXO roles, and compliance directory roles
Grant-M365AssessConsent
```

---

#### C. Network & Firewall

All connections require outbound HTTPS (TCP 443). If your environment uses a proxy, firewall, or conditional access policies that restrict network access, the connection may time out or be rejected.

**Required endpoints:**

| Service | Endpoint | Protocol |
|---------|----------|----------|
| Microsoft Graph | `graph.microsoft.com` | HTTPS 443 |
| Exchange Online | `outlook.office365.com` | HTTPS 443 |
| Exchange Online PowerShell | `outlook.office365.com/powershell-liveid/` | HTTPS 443 |
| Purview (Compliance) | `ps.compliance.protection.outlook.com` | HTTPS 443 |
| Entra ID (Auth) | `login.microsoftonline.com` | HTTPS 443 |
| GCC High (Auth) | `login.microsoftonline.us` | HTTPS 443 |
| GCC High (EXO) | Endpoint varies — see [Cloud Environments](../AUTHENTICATION.md#cloud-environments) | HTTPS 443 |
| GCC High (Purview) | `ps.compliance.protection.office365.us` | HTTPS 443 |

**Test connectivity from your machine:**

```powershell
# Use the built-in port connectivity tester
.\src\M365-Assess\Networking\Test-PortConnectivity.ps1 `
    -ComputerName 'outlook.office365.com','graph.microsoft.com','ps.compliance.protection.outlook.com','login.microsoftonline.com' `
    -Port 443

# Quick test without the script
Test-NetConnection -ComputerName outlook.office365.com -Port 443
Test-NetConnection -ComputerName ps.compliance.protection.outlook.com -Port 443
```

**Network checklist:**

- [ ] All four endpoints above return **Open** / **TcpTestSucceeded: True**
- [ ] No TLS inspection appliance is rewriting certificates (causes MSAL token failures)
- [ ] Proxy settings are configured if required (`$env:HTTPS_PROXY`, `[System.Net.WebRequest]::DefaultWebProxy`)
- [ ] Conditional Access policies do not block the assessment account or service principal from the required endpoints
- [ ] IP-based Conditional Access policies allow the machine's egress IP

---

#### D. Authentication Method

Not all auth methods work with all services. A mismatch is a frequent cause of Purview connection failures.

| Auth Method | Exchange Online | Purview | Notes |
|-------------|:---------------:|:-------:|-------|
| Interactive (browser) | ✅ | ✅ | Most reliable for both |
| Interactive with `-UserPrincipalName` | ✅ | ✅ | Bypasses WAM broker issues |
| Device Code (`-UseDeviceCode`) | ✅ | ❌ | Purview falls back to browser with a warning; fails in headless environments |
| Certificate (`-ClientId` + `-CertificateThumbprint`) | ✅ | ✅ | Recommended for automation |
| Client Secret (`-ClientId` + `-ClientSecret`) | ❌ | ❌ | **Not supported for EXO or Purview** — use certificate auth instead |
| Managed Identity (`-ManagedIdentity`) | ✅ | ❌ | Purview falls back to browser with a warning |

**If using client secret auth:**

Client secrets only work for Microsoft Graph connections. Exchange Online and Purview require certificate-based authentication for app-only scenarios. Switch to certificate auth:

```powershell
Invoke-M365Assessment -TenantId 'contoso.onmicrosoft.com' `
    -ClientId '00000000-0000-0000-0000-000000000000' `
    -CertificateThumbprint 'ABC123DEF456'
```

**If using device code in a headless environment:**

Purview does not support device code flow. Either:
1. Use certificate-based auth (recommended for CI/CD)
2. Exclude Purview-dependent sections: `-Section Tenant,Identity,Licensing,Email,Intune,Collaboration,Hybrid`
3. Use `-SkipDLP` to skip the DLP collector (the primary Purview consumer in the Security section)

**If WAM broker errors occur:**

```powershell
# Option 1: Specify UPN to bypass WAM
Invoke-M365Assessment -TenantId 'contoso.onmicrosoft.com' `
    -UserPrincipalName 'admin@contoso.onmicrosoft.com'

# Option 2: Use device code (works for EXO but not Purview)
Invoke-M365Assessment -TenantId 'contoso.onmicrosoft.com' -UseDeviceCode
```

---

#### E. Module Installation

Exchange Online and Purview both use the `ExchangeOnlineManagement` module. If the module is missing or an incompatible version is installed, connections will fail.

**Verify module:**

```powershell
Get-Module ExchangeOnlineManagement -ListAvailable | Select-Object Name, Version
# Expected: 3.5.0 or later
```

**Install or update:**

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
```

**Module checklist:**

- [ ] `ExchangeOnlineManagement` 3.5.0+ is installed
- [ ] `Microsoft.Graph.Authentication` 2.36.0+ is installed (avoids MSAL assembly conflicts)
- [ ] Only one version of each module is installed (run `Get-Module ExchangeOnlineManagement -ListAvailable` — should show one entry)
- [ ] PowerShell session was restarted after installing or updating modules

See the [Compatibility Matrix](COMPATIBILITY.md) for the full list of tested module versions.

---

#### F. Conditional Access & Security Controls

Entra ID Conditional Access (CA) policies can block service connections even when permissions are correct.

**Checklist:**

- [ ] CA policies do not block the assessment account from accessing `Office 365 Exchange Online` or `Office 365 Security & Compliance Center` cloud apps
- [ ] If MFA is required, the auth method you are using supports MFA (interactive and device code do; certificate auth is exempt from user-facing MFA)
- [ ] The machine or service running the assessment is not excluded by a location-based CA policy
- [ ] If using app-only auth, the service principal is not blocked by a CA policy scoped to workload identities
- [ ] Tenant-level security defaults (if enabled instead of CA) do not conflict with the auth method

**Test whether CA is blocking access:**

```powershell
# Sign-in logs show CA policy evaluation results
# In Entra admin center: Monitor > Sign-in logs
# Filter by: User = assessment account, Status = Failure
# Check the "Conditional Access" tab on the failed sign-in entry
```

---

#### G. Tenant & Environment Configuration

- [ ] The `-TenantId` value is correct (use `contoso.onmicrosoft.com` or the tenant GUID)
- [ ] For GCC/GCC High/DoD tenants, pass `-M365Environment gcc|gcchigh|dod` — wrong environment routes to the wrong endpoints and causes auth failures
- [ ] The tenant has active Exchange Online and/or Purview licenses (connection fails if the service is not provisioned in the tenant)
- [ ] The assessment account is not a guest user in the tenant (guest accounts have limited access to EXO and Purview)

**Verify tenant environment:**

```powershell
# Auto-detect environment (no auth required)
. .\src\M365-Assess\Orchestrator\Resolve-M365Environment.ps1
Resolve-M365Environment -TenantId 'contoso.onmicrosoft.com'
# Returns: commercial, gcc, gcchigh, or dod
```

---

### Quick Resolution Summary

| Scenario | Fix |
|----------|-----|
| Both EXO and Purview fail with 401/403 | Assign **Global Reader** directory role to the assessment account or service principal |
| EXO fails, Purview works | Add account to **View-Only Organization Management** EXO role group; add `Exchange.ManageAsApp` app permission for app-only |
| Purview fails, EXO works | Assign **Compliance Administrator** + **Security Reader** directory roles |
| Using client secret | Switch to `-CertificateThumbprint` (client secret is Graph-only) |
| Device code + Purview | Switch to interactive or certificate auth |
| Timeout errors | Check firewall/proxy for `outlook.office365.com` and `ps.compliance.protection.outlook.com` on TCP 443 |
| WAM/RuntimeBroker errors | Use `-UserPrincipalName` or `-UseDeviceCode` |
| Module errors | `Install-Module ExchangeOnlineManagement -Force` then restart PowerShell |
| Wrong cloud environment | Add `-M365Environment gcchigh` (or `gcc`, `dod`) |

---

## Still Having Issues?

- Check the [Quickstart Guide](QUICKSTART.md) for initial setup steps
- Review the [README](../README.md) for supported environments and prerequisites
- Open an issue at [github.com/JoeKuster-Q/M365-Assess/issues](https://github.com/JoeKuster-Q/M365-Assess/issues) with:
  - The full error message
  - Your PowerShell version (`$PSVersionTable.PSVersion`)
  - Your module versions (`Get-Module Microsoft.Graph*, ExchangeOnlineManagement -ListAvailable`)

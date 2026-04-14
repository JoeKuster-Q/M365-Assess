function Connect-RequiredService {
    [CmdletBinding()]
    param(
        [string[]]$Services,
        [string]$SectionName
    )

    # Maximum number of connection attempts per service
    $maxRetries = 6

    foreach ($svc in $Services) {
        if ($connectedServices.Contains($svc)) { continue }
        if ($failedServices.Contains($svc)) { continue }

        # Friendly display names for host output
        $serviceDisplayName = switch ($svc) {
            'Graph'          { 'Microsoft Graph' }
            'ExchangeOnline' { 'Exchange Online' }
            'Purview'        { 'Purview (Security & Compliance)' }
            'PowerBI'        { 'Power BI' }
            default          { $svc }
        }
        Write-Host "    Connecting to $serviceDisplayName..." -ForegroundColor Yellow
        if (Get-Command -Name Update-ProgressStatus -ErrorAction SilentlyContinue) {
            Update-ProgressStatus -Message "Connecting to $serviceDisplayName..."
        }

        Write-AssessmentLog -Level INFO -Message "Connecting to $svc..." -Section $SectionName

        # EXO and Purview share the EXO module and conflict if connected simultaneously.
        # Disconnect the other before connecting.
        if ($svc -eq 'ExchangeOnline' -and $connectedServices.Contains('Purview')) {
            Write-AssessmentLog -Level INFO -Message "Disconnecting Purview before connecting ExchangeOnline" -Section $SectionName
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            $connectedServices.Remove('Purview') | Out-Null
        }
        elseif ($svc -eq 'Purview' -and $connectedServices.Contains('ExchangeOnline')) {
            Write-AssessmentLog -Level INFO -Message "Disconnecting ExchangeOnline before connecting Purview" -Section $SectionName
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            $connectedServices.Remove('ExchangeOnline') | Out-Null
        }

        $connectParams = @{ Service = $svc }
        if ($TenantId) { $connectParams['TenantId'] = $TenantId }
        if ($ClientId) { $connectParams['ClientId'] = $ClientId }
        if ($CertificateThumbprint) { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
        if ($ClientSecret) { $connectParams['ClientSecret'] = $ClientSecret }
        if ($UserPrincipalName -and $svc -ne 'Graph') {
            $connectParams['UserPrincipalName'] = $UserPrincipalName
        }

        if ($svc -eq 'Graph') {
            $connectParams['Scopes'] = $graphScopes
        }

        if ($M365Environment -ne 'commercial') {
            $connectParams['M365Environment'] = $M365Environment
        }
        if ($ManagedIdentity) {
            $connectParams['ManagedIdentity'] = $true
        }
        if ($UseDeviceCode) {
            $connectParams['UseDeviceCode'] = $true
        }

        # ------------------------------------------------------------------
        # Retry loop — attempt the connection up to $maxRetries times.
        # Transient failures (network timeouts, throttling, token service
        # hiccups) often succeed on a subsequent attempt. Each retry is
        # displayed on screen so the operator can see progress.
        # ------------------------------------------------------------------
        $connected = $false
        $lastError = $null
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                if ($attempt -gt 1) {
                    # Exponential back-off: 2s, 4s, 8s, 16s, 32s
                    $backoffSeconds = [math]::Pow(2, $attempt - 1)
                    Write-Host "    $([char]0x21BB) Retry $attempt of $maxRetries for $serviceDisplayName (waiting ${backoffSeconds}s)..." -ForegroundColor Cyan
                    Write-AssessmentLog -Level WARN -Message "$svc connection attempt $attempt of $maxRetries (backoff: ${backoffSeconds}s) — previous error: $($lastError.Exception.Message)" -Section $SectionName
                    if (Get-Command -Name Update-ProgressStatus -ErrorAction SilentlyContinue) {
                        Update-ProgressStatus -Message "Retry $attempt/$maxRetries for $serviceDisplayName..."
                    }
                    Start-Sleep -Seconds $backoffSeconds
                }

                # Suppress noisy output during connection (skip when device code
                # is active — the user needs to see the code and URL).
                #
                # Only PowerShell stream redirection is used here.
                # Console.SetOut() must NOT be called because it permanently
                # sets the internal s_isOutTextWriterRedirected flag, causing
                # Console.IsOutputRedirected to return true for the rest of
                # the process.  ExchangeOnlineManagement's .NET internals
                # check this flag and enter a code path that produces a
                # NullReferenceException during Connect-ExchangeOnline /
                # Connect-IPPSSession.
                if (-not $UseDeviceCode) {
                    & $connectServicePath @connectParams 2>$null 6>$null
                }
                else {
                    & $connectServicePath @connectParams
                }

                $connected = $true
                if ($attempt -gt 1) {
                    Write-Host "    $([char]0x2714) $serviceDisplayName connected on attempt $attempt" -ForegroundColor Green
                    Write-AssessmentLog -Level INFO -Message "$svc connected successfully on attempt $attempt of $maxRetries." -Section $SectionName
                }
                break
            }
            catch {
                $lastError = $_

                # Log verbose error context for every failed attempt
                Write-AssessmentLog -Level WARN -Message "$svc attempt $attempt failed: $($_.Exception.Message)" -Section $SectionName -Detail $_.Exception.ToString()

                # Non-retryable errors: unsupported auth method or missing module.
                # These will fail identically on every attempt, so bail out early.
                $nonRetryable = @(
                    'does not support client secret',
                    'does not support managed identity',
                    'not installed',
                    'not recognized'
                )
                $isNonRetryable = $false
                foreach ($pattern in $nonRetryable) {
                    if ($_.Exception.Message -match [regex]::Escape($pattern)) {
                        $isNonRetryable = $true
                        break
                    }
                }
                if ($isNonRetryable) {
                    Write-AssessmentLog -Level WARN -Message "$svc error is non-retryable — skipping remaining retries." -Section $SectionName
                    break
                }

                if ($attempt -lt $maxRetries) {
                    Write-Host "    $([char]0x26A0) $serviceDisplayName attempt $attempt failed — will retry" -ForegroundColor Yellow
                }
            }
        }

        if ($connected) {
            $connectedServices.Add($svc) | Out-Null
            Write-AssessmentLog -Level INFO -Message "Connected to $svc successfully." -Section $SectionName

            # Warn device code users about token lifetime risk
            if ($svc -eq 'Graph' -and $UseDeviceCode) {
                Write-Warning "Device code tokens have a limited lifetime. For multi-section assessments, use Interactive or Certificate auth to avoid mid-run token expiry."
            }

            # Validate Graph scopes once after first connection
            if ($svc -eq 'Graph' -and -not $script:graphPermissionsChecked) {
                $script:graphPermissionsChecked = $true
                if (Get-Command -Name Test-GraphPermissions -ErrorAction SilentlyContinue) {
                    Test-GraphPermissions -RequiredScopes $graphScopes -SectionScopeMap $sectionScopeMap -ActiveSections $Section
                }
            }

            # Resolve tenant licenses for check gating (first Graph connection only)
            if ($svc -eq 'Graph' -and -not $script:tenantLicensesResolved) {
                $script:tenantLicensesResolved = $true
                try {
                    $licenseHelper = Join-Path -Path $projectRoot -ChildPath 'Common\Resolve-TenantLicenses.ps1'
                    if (Test-Path -Path $licenseHelper) {
                        . $licenseHelper
                        $tenantLicenses = Resolve-TenantLicenses
                        if ($tenantLicenses -and $tenantLicenses.ActiveServicePlans.Count -gt 0) {
                            # Re-initialize progress with license data for accurate check gating
                            if (Get-Command -Name Initialize-CheckProgress -ErrorAction SilentlyContinue) {
                                $reInitParams = @{
                                    ControlRegistry = $progressRegistry
                                    ActiveSections  = $Section
                                    TenantLicenses  = $tenantLicenses
                                }
                                if ($QuickScan) { $reInitParams['SeverityFilter'] = @('Critical', 'High') }
                                Initialize-CheckProgress @reInitParams
                            }
                        }
                    }
                }
                catch {
                    Write-AssessmentLog -Level WARN -Message "Could not resolve tenant licenses: $($_.Exception.Message). License gating disabled." -Section $SectionName
                }
            }

            # After first Graph connection, capture connected tenant domain for
            # later use (e.g. report headers, logging).
            if ($svc -eq 'Graph' -and -not $script:resolvedTenantDomain) {
                try {
                    $orgInfo = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
                    $initialDomain = $orgInfo.VerifiedDomains | Where-Object { $_.IsInitial -eq $true } | Select-Object -First 1
                    if ($initialDomain) {
                        $script:resolvedTenantDomain = $initialDomain.Name
                        $script:resolvedTenantId = $orgInfo.Id
                        $script:resolvedTenantDisplayName = $orgInfo.DisplayName
                        Write-AssessmentLog -Level INFO -Message "Connected tenant: $($script:resolvedTenantDisplayName) ($($script:resolvedTenantDomain)) [ID: $($script:resolvedTenantId)]" -Section $SectionName

                        # Prefetch DNS records for all verified domains in background
                        # (runs while auth and other collectors proceed)
                        if ('Email' -in $Section) {
                            $verifiedDomainNames = @($orgInfo.VerifiedDomains | ForEach-Object { $_.Name })
                            Write-AssessmentLog -Level INFO -Message "Prefetching DNS records for $($verifiedDomainNames.Count) verified domain(s) in background" -Section $SectionName
                            $script:dnsPrefetchJobs = @()
                            $dnsHelperPath = Join-Path -Path $projectRoot -ChildPath 'Common\Resolve-DnsRecord.ps1'
                            foreach ($vdName in $verifiedDomainNames) {
                                $script:dnsPrefetchJobs += Start-ThreadJob -ScriptBlock {
                                    . $using:dnsHelperPath
                                    $d      = $using:vdName
                                    $spf    = Resolve-DnsRecord -Name $d -Type TXT -ErrorAction SilentlyContinue
                                    $dmarc  = Resolve-DnsRecord -Name ('_dmarc.' + $d) -Type TXT -ErrorAction SilentlyContinue
                                    $dkim1  = Resolve-DnsRecord -Name ('selector1._domainkey.' + $d) -Type CNAME -ErrorAction SilentlyContinue
                                    $dkim2  = Resolve-DnsRecord -Name ('selector2._domainkey.' + $d) -Type CNAME -ErrorAction SilentlyContinue
                                    $mtaSts = Resolve-DnsRecord -Name ('_mta-sts.' + $d) -Type TXT -ErrorAction SilentlyContinue
                                    $tlsRpt = Resolve-DnsRecord -Name ('_smtp._tls.' + $d) -Type TXT -ErrorAction SilentlyContinue
                                    [PSCustomObject]@{
                                        Domain = $d; Spf = $spf; Dmarc = $dmarc
                                        Dkim1 = $dkim1; Dkim2 = $dkim2
                                        MtaSts = $mtaSts; TlsRpt = $tlsRpt
                                    }
                                }
                            }
                        }

                        # Phase B: Rename folder/files to include domain prefix if not already set
                        if (-not $script:domainPrefix -and $script:resolvedTenantDomain -match '^([^.]+)\.onmicrosoft\.(com|us)$') {
                            $script:domainPrefix = $Matches[1]
                            try {
                                # Rename assessment folder (updates both local and script scope)
                                $newFolderName = "Assessment_${timestamp}_$($script:domainPrefix)"
                                Rename-Item -Path $assessmentFolder -NewName $newFolderName -ErrorAction Stop
                                $script:assessmentFolder = Join-Path -Path $OutputFolder -ChildPath $newFolderName
                                $assessmentFolder = $script:assessmentFolder

                                # Update log path to reflect renamed folder BEFORE renaming the file
                                $oldLogName = Split-Path -Leaf $script:logFilePath
                                $script:logFilePath = Join-Path -Path $assessmentFolder -ChildPath $oldLogName

                                # Rename log file
                                $newLogName = "_Assessment-Log_$($script:domainPrefix).txt"
                                Rename-Item -Path $script:logFilePath -NewName $newLogName -ErrorAction Stop
                                $script:logFileName = $newLogName
                                $script:logFilePath = Join-Path -Path $assessmentFolder -ChildPath $newLogName

                                # Update log header with resolved domain prefix
                                $logContent = Get-Content -Path $script:logFilePath -Raw
                                $logContent = $logContent -creplace '(?m)(Domain:\s*)(\r?\n)', "`${1}$($script:domainPrefix)`${2}"
                                Set-Content -Path $script:logFilePath -Value $logContent -Encoding UTF8 -NoNewline

                                Write-AssessmentLog -Level INFO -Message "Renamed output to include tenant domain: $($script:domainPrefix)" -Section $SectionName
                            }
                            catch {
                                Write-AssessmentLog -Level WARN -Message "Could not rename output folder/files: $($_.Exception.Message)" -Section $SectionName
                            }
                        }
                    }
                }
                catch {
                    Write-AssessmentLog -Level WARN -Message "Could not resolve tenant info from Graph: $($_.Exception.Message)" -Section $SectionName
                }
            }
        }
        else {
            # All retry attempts exhausted — record final failure
            $failedServices.Add($svc) | Out-Null

            # Extract clean one-liner for console
            $friendlyMsg = $lastError.Exception.Message
            if ($friendlyMsg -match '(.*?)(?:\r?\n|$)') {
                $friendlyMsg = $Matches[1]
            }
            if ($friendlyMsg.Length -gt 70) {
                $friendlyMsg = $friendlyMsg.Substring(0, 67) + '...'
            }

            $retriesMade = [math]::Min($maxRetries, $attempt) - 1
            if ($retriesMade -gt 0) {
                Write-Host "    $([char]0x2718) $svc connection failed after $($retriesMade + 1) attempts (see log)" -ForegroundColor Red
            }
            else {
                Write-Host "    $([char]0x2718) $svc connection failed (see log)" -ForegroundColor Red
            }
            Write-AssessmentLog -Level ERROR -Message "$svc connection failed after $attempt attempt(s): $friendlyMsg" -Section $SectionName -Detail $lastError.Exception.ToString()

            $issues.Add([PSCustomObject]@{
                Severity     = 'ERROR'
                Section      = $SectionName
                Collector    = '(connection)'
                Description  = "$svc connection failed"
                ErrorMessage = $friendlyMsg
                Action       = Get-RecommendedAction -ErrorMessage $lastError.Exception.ToString()
            })
        }
    }
}

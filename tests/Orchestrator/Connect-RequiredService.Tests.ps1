BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Connect-RequiredService' {
    BeforeAll {
        # Stub external commands
        function Get-MgContext { }
        function Get-MgOrganization { }
        function Disconnect-ExchangeOnline { }
        function Update-ProgressStatus { }
        function Test-GraphPermissions { }

        # Load helpers first (provides Write-AssessmentLog, Get-RecommendedAction)
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Connect-RequiredService.ps1"

        Mock Write-Host { }
        Mock Write-AssessmentLog { }
    }

    Context 'when a service is already connected' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $connectedServices.Add('Graph')
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $connectServicePath = 'fake-connect.ps1'
        }

        It 'should skip without displaying a connection message' {
            Connect-RequiredService -Services @('Graph') -SectionName 'Identity'
            # If it skipped, Write-Host should not be called (no "Connecting to..." message)
            Should -Invoke Write-Host -Times 0
        }
    }

    Context 'when a service previously failed' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices.Add('ExchangeOnline')
            $connectServicePath = 'fake-connect.ps1'
        }

        It 'should skip without retrying' {
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            Should -Invoke Write-Host -Times 0
        }
    }

    Context 'when connecting a new service successfully' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            $connectServicePath = Join-Path $TestDrive 'mock-connect.ps1'
            Set-Content -Path $connectServicePath -Value '# no-op'
            $M365Environment = 'commercial'
            $graphScopes = @('User.Read.All')
            $script:graphPermissionsChecked = $false
            $Section = @('Identity')
            $sectionScopeMap = @{ 'Identity' = @('User.Read.All') }

            Mock Test-GraphPermissions { }
            Mock Get-MgOrganization {
                return [PSCustomObject]@{
                    Id              = 'test-id'
                    DisplayName     = 'Contoso'
                    VerifiedDomains = @(
                        [PSCustomObject]@{ Name = 'contoso.onmicrosoft.com'; IsInitial = $true }
                    )
                }
            }
        }

        It 'should add the service to connectedServices' {
            Connect-RequiredService -Services @('Graph') -SectionName 'Identity'
            $connectedServices | Should -Contain 'Graph'
        }

        It 'should display friendly service name' {
            $connectedServices.Clear()
            $script:graphPermissionsChecked = $false
            Connect-RequiredService -Services @('Graph') -SectionName 'Identity'
            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Microsoft Graph*'
            }
        }
    }

    Context 'when connection throws an error' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            $connectServicePath = Join-Path $TestDrive 'fail-connect.ps1'
            Set-Content -Path $connectServicePath -Value 'throw "Connection refused"'
            $M365Environment = 'commercial'

            # Mock Start-Sleep to avoid real delays during retry back-off
            Mock Start-Sleep { }
        }

        It 'should add the service to failedServices' {
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            $failedServices | Should -Contain 'ExchangeOnline'
        }

        It 'should record an issue' {
            $issues.Count | Should -BeGreaterThan 0
            $issues[0].Severity | Should -Be 'ERROR'
        }

        It 'should retry up to 6 times before failing' {
            # Reset state
            $failedServices.Clear()
            $issues.Clear()
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            # Start-Sleep called once per retry (attempts 2-6 = 5 retries)
            Should -Invoke Start-Sleep -Times 5
        }
    }

    Context 'when error is non-retryable' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            $connectServicePath = Join-Path $TestDrive 'nonretry-connect.ps1'
            Set-Content -Path $connectServicePath -Value 'throw "Exchange Online does not support client secret authentication."'
            $M365Environment = 'commercial'

            Mock Start-Sleep { }
        }

        It 'should not retry on non-retryable errors' {
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            $failedServices | Should -Contain 'ExchangeOnline'
            # Start-Sleep should never be called — first attempt fails and is non-retryable
            Should -Invoke Start-Sleep -Times 0
        }
    }

    Context 'when connection succeeds on a retry' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            # Script that fails twice then succeeds (uses a temp counter file)
            $counterFile = Join-Path $TestDrive 'attempt-counter.txt'
            Set-Content -Path $counterFile -Value '0'
            $connectServicePath = Join-Path $TestDrive 'flaky-connect.ps1'
            $scriptContent = @"
`$cf = '$counterFile'
`$count = [int](Get-Content -Path `$cf)
`$count++
Set-Content -Path `$cf -Value `$count
if (`$count -lt 3) { throw "Transient network error" }
"@
            Set-Content -Path $connectServicePath -Value $scriptContent
            $M365Environment = 'commercial'

            Mock Start-Sleep { }
        }

        It 'should succeed after retries, add to connectedServices, and have called Start-Sleep for back-off' {
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            $connectedServices | Should -Contain 'ExchangeOnline'
            $failedServices | Should -Not -Contain 'ExchangeOnline'
            # Attempt 1 fails, attempt 2 fails, attempt 3 succeeds
            # Start-Sleep called for attempts 2 and 3
            Should -Invoke Start-Sleep -Times 2
        }
    }

    Context 'when EXO and Purview conflict' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $connectedServices.Add('Purview')
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            $connectServicePath = Join-Path $TestDrive 'mock-connect.ps1'
            Set-Content -Path $connectServicePath -Value '# no-op'
            $M365Environment = 'commercial'

            Mock Disconnect-ExchangeOnline { }
        }

        It 'should disconnect Purview before connecting ExchangeOnline' {
            Connect-RequiredService -Services @('ExchangeOnline') -SectionName 'Email'
            Should -Invoke Disconnect-ExchangeOnline -Times 1
        }

        It 'should remove Purview from connectedServices' {
            $connectedServices | Should -Not -Contain 'Purview'
        }
    }

    Context 'service display name mapping' {
        BeforeAll {
            $connectedServices = [System.Collections.Generic.List[string]]::new()
            $failedServices = [System.Collections.Generic.List[string]]::new()
            $issues = [System.Collections.Generic.List[object]]::new()
            $connectServicePath = Join-Path $TestDrive 'mock-connect.ps1'
            Set-Content -Path $connectServicePath -Value '# no-op'
            $M365Environment = 'commercial'
        }

        It 'should display "Exchange Online" for ExchangeOnline service' -ForEach @(
            @{ Service = 'ExchangeOnline'; Expected = 'Exchange Online' }
            @{ Service = 'Purview'; Expected = 'Purview' }
        ) {
            $connectedServices.Clear()
            $failedServices.Clear()
            Connect-RequiredService -Services @($Service) -SectionName 'Test'
            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*$Expected*"
            }
        }
    }
}

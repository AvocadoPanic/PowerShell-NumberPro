#requires -Version 5.1
#requires -Modules Pester

<#
.SYNOPSIS
Pester tests for the NumberPro PowerShell module

.DESCRIPTION
Unit and integration tests for NumberPro module functionality

.NOTES
Run with: Invoke-Pester -Path .\NumberPro.Tests.ps1
#>

# Import the module
$modulePath = Join-Path $PSScriptRoot "NumberPro.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    throw "NumberPro module not found at: $modulePath"
}

Describe "NumberPro Module Tests" {
    
    Context "Module Structure" {
        
        It "Should export expected functions" {
            $exportedFunctions = @(
                'Connect-NpServer',
                'Disconnect-NpServer',
                'Test-NpConnection',
                'Get-NpNumberRange',
                'Get-NpAvailableNumber',
                'New-NpReservation',
                'Get-NpReservation',
                'Remove-NpReservation'
            )
            
            $module = Get-Module NumberPro
            $moduleFunctions = $module.ExportedFunctions.Keys
            
            foreach ($function in $exportedFunctions) {
                $moduleFunctions | Should -Contain $function
            }
        }
        
        It "Should not export helper functions" {
            $helperFunctions = @(
                'ConvertTo-E164Format',
                'Invoke-NpRestMethod',
                'Get-SystemTypeInfo'
            )
            
            $module = Get-Module NumberPro
            $moduleFunctions = $module.ExportedFunctions.Keys
            
            foreach ($function in $helperFunctions) {
                $moduleFunctions | Should -Not -Contain $function
            }
        }
    }
    
    Context "Helper Function Tests" {
        
        # Access helper functions through module
        InModuleScope NumberPro {
            
            Describe "ConvertTo-E164Format" {
                
                It "Should convert 10-digit US number to E.164" {
                    $result = ConvertTo-E164Format -Number "3205551011"
                    $result | Should -Be "+13205551011"
                }
                
                It "Should handle 11-digit US number with country code" {
                    $result = ConvertTo-E164Format -Number "13205551011"
                    $result | Should -Be "+13205551011"
                }
                
                It "Should handle numbers with formatting characters" {
                    $result = ConvertTo-E164Format -Number "(320) 555-1011"
                    $result | Should -Be "+13205551011"
                }
                
                It "Should handle 7-digit extension with warning" {
                    $result = ConvertTo-E164Format -Number "5551011" -WarningAction SilentlyContinue
                    $result | Should -Be "5551011"
                }
            }
            
            Describe "Get-SystemTypeInfo" {
                
                It "Should return correct info for SfB" {
                    $result = Get-SystemTypeInfo -SystemType "SfB"
                    $result.UnusedResource | Should -Be "UnusedLineUri"
                    $result.ReservedResource | Should -Be "ReservedLineUri"
                    $result.NumberField | Should -Be "LineUri"
                }
                
                It "Should return correct info for Cisco" {
                    $result = Get-SystemTypeInfo -SystemType "Cisco"
                    $result.UnusedResource | Should -Be "UnusedExtension"
                    $result.ReservedResource | Should -Be "ReservedExtension"
                    $result.NumberField | Should -Be "Extension"
                }
            }
        }
    }
    
    Context "Connection Management Tests" {
        
        BeforeEach {
            # Clear any existing connection
            InModuleScope NumberPro {
                $script:NpConnection = $null
            }
        }
        
        It "Should fail when not connected" {
            { Get-NpNumberRange } | Should -Throw "*Not connected to NumberPro server*"
        }
        
        It "Test-NpConnection should return false when not connected" {
            Test-NpConnection | Should -Be $false
        }
        
        It "Disconnect-NpServer should handle no connection gracefully" {
            { Disconnect-NpServer } | Should -Not -Throw
        }
    }
    
    Context "Parameter Validation Tests" {
        
        # Mock connection for parameter tests
        BeforeEach {
            InModuleScope NumberPro {
                $script:NpConnection = @{
                    BaseUrl = "https://test.server.com:8443/2n"
                    AuthHeader = "Basic dGVzdDp0ZXN0"
                }
            }
        }
        
        Describe "Get-NpAvailableNumber Parameter Validation" {
            
            It "Should validate SystemType parameter" {
                { Get-NpAvailableNumber -SystemId 1 -SystemType "Invalid" -RangeName "Test" } | 
                    Should -Throw "*Cannot validate argument on parameter 'SystemType'*"
            }
            
            It "Should validate Count range" {
                { Get-NpAvailableNumber -SystemId 1 -SystemType "SfB" -RangeName "Test" -Count 101 } | 
                    Should -Throw "*Cannot validate argument on parameter 'Count'*"
            }
            
            It "Should validate Count minimum" {
                { Get-NpAvailableNumber -SystemId 1 -SystemType "SfB" -RangeName "Test" -Count 0 } | 
                    Should -Throw "*Cannot validate argument on parameter 'Count'*"
            }
        }
        
        Describe "New-NpReservation Parameter Validation" {
            
            It "Should require either NeverExpires or ExpirationDate" {
                { New-NpReservation -SystemId 1 -SystemType "SfB" -Number "1234567890" -Reason "Test" } | 
                    Should -Throw "*Parameter set cannot be resolved*"
            }
            
            It "Should validate RetryCount range" {
                { New-NpReservation -SystemId 1 -SystemType "SfB" -Number "1234567890" -Reason "Test" -NeverExpires -RetryCount 21 } | 
                    Should -Throw "*Cannot validate argument on parameter 'RetryCount'*"
            }
        }
    }
    
    Context "Object Output Tests" {
        
        # Mock successful API responses
        BeforeEach {
            Mock Invoke-RestMethod {
                return @(
                    @{
                        'Name' = 'TestRange'
                        'Description' = 'Test Description'
                        'Start' = '3205551000'
                        'End' = '3205551999'
                        'Count' = 1000
                        'Sn-Resource-Uri' = 'https://test/range/1'
                    }
                )
            }
            
            InModuleScope NumberPro {
                $script:NpConnection = @{
                    BaseUrl = "https://test.server.com:8443/2n"
                    AuthHeader = "Basic dGVzdDp0ZXN0"
                }
            }
        }
        
        It "Get-NpNumberRange should return custom objects" {
            $result = Get-NpNumberRange
            
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSTypeName | Should -Be 'NumberPro.Range'
            $result[0].StartE164 | Should -Be '+13205551000'
            $result[0].EndE164 | Should -Be '+13205551999'
        }
    }
    
    Context "Integration Test Examples" -Tag 'Integration' {
        
        # These tests require a real NumberPro server
        # Skip them in CI/CD environments
        
        BeforeAll {
            $skipIntegration = $true # Set to $false when testing against real server
            
            if (-not $skipIntegration) {
                $testServer = "numberpro.test.com"
                $testCred = Get-Credential -Message "Enter test credentials"
                Connect-NpServer -Server $testServer -Credential $testCred
            }
        }
        
        It "Should connect to server" -Skip:$skipIntegration {
            Test-NpConnection | Should -Be $true
        }
        
        It "Should get number ranges" -Skip:$skipIntegration {
            $ranges = Get-NpNumberRange
            $ranges | Should -Not -BeNullOrEmpty
        }
        
        It "Should complete full workflow" -Skip:$skipIntegration {
            # Get available number
            $number = Get-NpAvailableNumber -SystemId 1 -SystemType "SfB" -RangeName "Test"
            $number | Should -Not -BeNullOrEmpty
            
            # Reserve it
            $reservation = $number | New-NpReservation -Reason "Pester Test" -NeverExpires
            $reservation | Should -Not -BeNullOrEmpty
            $reservation.Number | Should -Be $number.Number
            
            # Verify reservation exists
            $found = Get-NpReservation -SystemId 1 -SystemType "SfB" -Number $reservation.Number
            $found | Should -Not -BeNullOrEmpty
            
            # Clean up
            $found | Remove-NpReservation -Force
        }
        
        AfterAll {
            if (-not $skipIntegration) {
                Disconnect-NpServer
            }
        }
    }
}

# Performance Tests
Describe "NumberPro Performance Tests" -Tag 'Performance' {
    
    Context "E.164 Conversion Performance" {
        
        It "Should convert 1000 numbers in reasonable time" {
            InModuleScope NumberPro {
                $numbers = 1..1000 | ForEach-Object { "320555{0:D4}" -f $_ }
                
                $elapsed = Measure-Command {
                    $numbers | ForEach-Object {
                        $null = ConvertTo-E164Format -Number $_
                    }
                }
                
                # Should complete in less than 1 second
                $elapsed.TotalSeconds | Should -BeLessThan 1
            }
        }
    }
}

# Mock Data Generation for Testing
function New-MockNumberData {
    param(
        [int]$Count = 10,
        [string]$RangeName = "Test",
        [string]$StartNumber = "3205551000"
    )
    
    $baseNumber = [long]$StartNumber
    $results = @()
    
    for ($i = 0; $i -lt $Count; $i++) {
        $number = ($baseNumber + $i).ToString()
        $results += @{
            'Inventory Number' = $number
            'LineUri' = $number
            'RangeName' = $RangeName
            'Sn-Resource-Uri' = "https://test/number/$number"
        }
    }
    
    return $results
}

# Example of testing with mock data
Describe "Mock Data Tests" {
    
    BeforeEach {
        Mock Invoke-RestMethod {
            return New-MockNumberData -Count 5
        }
        
        InModuleScope NumberPro {
            $script:NpConnection = @{
                BaseUrl = "https://test.server.com:8443/2n"
                AuthHeader = "Basic dGVzdDp0ZXN0"
            }
        }
    }
    
    It "Should handle bulk number retrieval" {
        $numbers = Get-NpAvailableNumber -SystemId 1 -SystemType "SfB" -RangeName "Test" -Count 5
        
        $numbers.Count | Should -Be 5
        $numbers[0].E164Number | Should -Match '^\+1\d{10}$'
    }
}
#requires -Version 5.1
#requires -Modules NumberPro

<#
.SYNOPSIS
Sample script demonstrating NumberPro module usage

.DESCRIPTION
This script shows common patterns for using the NumberPro module
in enterprise automation scenarios.

.NOTES
Author: IT Administrator
Date: 2024
#>

# Import the module
Import-Module NumberPro -Force

#region Configuration
$NpServer = "numberpro.company.com"
$NpPort = 8443
$UseHttps = $true
$DefaultSystemId = 1
$DefaultSystemType = "SfB"
#endregion

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

#endregion

#region Main Script

# 1. Connect to NumberPro Server
Write-ColorOutput "`n=== Connecting to NumberPro Server ===" -Color Cyan

# Check if already connected
if (-not (Test-NpConnection)) {
    $credential = Get-Credential -Message "Enter NumberPro API credentials"
    
    $connectParams = @{
        Server = $NpServer
        Port = $NpPort
        Credential = $credential
    }
    
    if (-not $UseHttps) {
        $connectParams.UseHttp = $true
    }
    
    try {
        Connect-NpServer @connectParams
    }
    catch {
        Write-ColorOutput "Failed to connect: $_" -Color Red
        exit 1
    }
}

# 2. Display Available Number Ranges
Write-ColorOutput "`n=== Available Number Ranges ===" -Color Cyan

$ranges = Get-NpNumberRange
if ($ranges) {
    $ranges | Format-Table Name, Description, Count, StartE164, EndE164 -AutoSize
}
else {
    Write-ColorOutput "No number ranges found" -Color Yellow
}

# 3. Get Available Numbers - Interactive Selection
Write-ColorOutput "`n=== Get Available Numbers ===" -Color Cyan

$selectedRange = $ranges | Out-GridView -Title "Select a Number Range" -OutputMode Single

if ($selectedRange) {
    Write-ColorOutput "Selected range: $($selectedRange.Name)" -Color Green
    
    # Get count from user
    $count = Read-Host "How many numbers do you need? (1-10)"
    if (-not $count) { $count = 1 }
    $count = [Math]::Min([Math]::Max([int]$count, 1), 10)
    
    # Get available numbers
    $availableNumbers = Get-NpAvailableNumber `
        -SystemId $DefaultSystemId `
        -SystemType $DefaultSystemType `
        -RangeName $selectedRange.Name `
        -Count $count
    
    if ($availableNumbers) {
        Write-ColorOutput "`nAvailable numbers:" -Color Green
        $availableNumbers | Format-Table Number, InventoryNumber, E164Number -AutoSize
    }
    else {
        Write-ColorOutput "No available numbers found in selected range" -Color Yellow
    }
}

# 4. Reserve Numbers - Demonstration
Write-ColorOutput "`n=== Number Reservation Demo ===" -Color Cyan

if ($availableNumbers) {
    $reserve = Read-Host "Would you like to reserve these numbers? (Y/N)"
    
    if ($reserve -eq 'Y') {
        # Get reservation details
        $reason = Read-Host "Enter reservation reason (e.g., 'New Hire', 'Project', 'Testing')"
        if (-not $reason) { $reason = "Testing" }
        
        $description = Read-Host "Enter description (optional)"
        
        $expireChoice = Read-Host "Should reservations expire? (Y/N)"
        
        $reservationParams = @{
            Reason = $reason
        }
        
        if ($description) {
            $reservationParams.Description = $description
        }
        
        if ($expireChoice -eq 'Y') {
            $days = Read-Host "Expire in how many days? (1-365)"
            if (-not $days) { $days = 90 }
            $reservationParams.ExpirationDate = (Get-Date).AddDays([int]$days)
        }
        else {
            $reservationParams.NeverExpires = $true
        }
        
        # Reserve each number
        $reservations = @()
        foreach ($number in $availableNumbers) {
            try {
                Write-ColorOutput "Reserving $($number.Number)..." -Color Gray
                $reservation = $number | New-NpReservation @reservationParams
                $reservations += $reservation
                Write-ColorOutput "  Success!" -Color Green
            }
            catch {
                Write-ColorOutput "  Failed: $_" -Color Red
            }
        }
        
        if ($reservations) {
            Write-ColorOutput "`nReserved numbers:" -Color Green
            $reservations | Format-Table Number, E164Number, Reason, NeverExpires, ExpirationDate -AutoSize
        }
    }
}

# 5. View Existing Reservations
Write-ColorOutput "`n=== Current Reservations ===" -Color Cyan

$currentReservations = Get-NpReservation -SystemId $DefaultSystemId -SystemType $DefaultSystemType

if ($currentReservations) {
    # Group by reason
    $grouped = $currentReservations | Group-Object Reason
    
    Write-ColorOutput "Reservation Summary:" -Color Green
    $grouped | ForEach-Object {
        Write-ColorOutput "  $($_.Name): $($_.Count) numbers" -Color Gray
    }
    
    # Show details
    $showDetails = Read-Host "`nShow detailed list? (Y/N)"
    if ($showDetails -eq 'Y') {
        $currentReservations | Format-Table Number, E164Number, Reason, Description, NeverExpires, ExpirationDate -AutoSize
    }
}
else {
    Write-ColorOutput "No reservations found" -Color Yellow
}

# 6. Cleanup Old Reservations (Optional)
Write-ColorOutput "`n=== Cleanup Options ===" -Color Cyan

if ($currentReservations) {
    $cleanup = Read-Host "Would you like to clean up any reservations? (Y/N)"
    
    if ($cleanup -eq 'Y') {
        # Filter options
        Write-ColorOutput "Filter by:" -Color Gray
        Write-ColorOutput "  1. Reason" -Color Gray
        Write-ColorOutput "  2. Expired only" -Color Gray
        Write-ColorOutput "  3. Specific number" -Color Gray
        Write-ColorOutput "  4. Select from grid" -Color Gray
        
        $choice = Read-Host "Enter choice (1-4)"
        
        $toRemove = @()
        
        switch ($choice) {
            '1' {
                $reasons = $currentReservations | Select-Object -ExpandProperty Reason -Unique
                Write-ColorOutput "Available reasons: $($reasons -join ', ')" -Color Gray
                $selectedReason = Read-Host "Enter reason to remove"
                $toRemove = $currentReservations | Where-Object { $_.Reason -eq $selectedReason }
            }
            '2' {
                $today = Get-Date
                $toRemove = $currentReservations | Where-Object { 
                    -not $_.NeverExpires -and [DateTime]$_.ExpirationDate -lt $today 
                }
            }
            '3' {
                $numberToRemove = Read-Host "Enter number to remove"
                $toRemove = $currentReservations | Where-Object { $_.Number -eq $numberToRemove }
            }
            '4' {
                $toRemove = $currentReservations | Out-GridView -Title "Select reservations to remove" -OutputMode Multiple
            }
        }
        
        if ($toRemove) {
            Write-ColorOutput "`nRemoving $($toRemove.Count) reservation(s)..." -Color Yellow
            
            $toRemove | ForEach-Object {
                try {
                    $_ | Remove-NpReservation -Force
                    Write-ColorOutput "  Removed: $($_.Number)" -Color Green
                }
                catch {
                    Write-ColorOutput "  Failed to remove $($_.Number): $_" -Color Red
                }
            }
        }
        else {
            Write-ColorOutput "No reservations selected for removal" -Color Yellow
        }
    }
}

# 7. Generate Report
Write-ColorOutput "`n=== Generate Report ===" -Color Cyan

$generateReport = Read-Host "Generate usage report? (Y/N)"

if ($generateReport -eq 'Y') {
    $reportPath = Join-Path $env:TEMP "NumberPro_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    # Collect all data
    $reportData = @()
    
    # Add range information
    foreach ($range in $ranges) {
        $reportData += [PSCustomObject]@{
            Type = "Range"
            Name = $range.Name
            Description = $range.Description
            Value = "Total: $($range.Count)"
            Details = "$($range.StartE164) to $($range.EndE164)"
            Status = "Active"
        }
    }
    
    # Add reservation information
    $allReservations = Get-NpReservation -SystemId $DefaultSystemId -SystemType $DefaultSystemType
    foreach ($res in $allReservations) {
        $reportData += [PSCustomObject]@{
            Type = "Reservation"
            Name = $res.Number
            Description = $res.Description
            Value = $res.E164Number
            Details = "Reason: $($res.Reason); Expires: $(if($res.NeverExpires){'Never'}else{$res.ExpirationDate})"
            Status = if($res.NeverExpires -or [DateTime]$res.ExpirationDate -gt (Get-Date)){"Active"}else{"Expired"}
        }
    }
    
    # Export report
    $reportData | Export-Csv -Path $reportPath -NoTypeInformation
    Write-ColorOutput "Report saved to: $reportPath" -Color Green
    
    # Open report
    $openReport = Read-Host "Open report? (Y/N)"
    if ($openReport -eq 'Y') {
        Invoke-Item $reportPath
    }
}

# 8. Disconnect
Write-ColorOutput "`n=== Cleanup ===" -Color Cyan

$disconnect = Read-Host "Disconnect from NumberPro server? (Y/N)"
if ($disconnect -eq 'Y') {
    Disconnect-NpServer
}

Write-ColorOutput "`nScript completed!" -Color Green

#endregion

# Example: Automated Employee Onboarding Function
function New-EmployeePhoneAllocation {
    <#
    .SYNOPSIS
    Automates phone number allocation for new employees
    
    .EXAMPLE
    New-EmployeePhoneAllocation -EmployeeName "John Doe" -Office "Minneapolis" -Department "Sales"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EmployeeName,
        
        [Parameter(Mandatory = $true)]
        [string]$Office,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [int]$SystemId = 1,
        
        [Parameter(Mandatory = $false)]
        [string]$SystemType = "SfB"
    )
    
    try {
        # Ensure connected
        if (-not (Test-NpConnection)) {
            throw "Not connected to NumberPro server. Run Connect-NpServer first."
        }
        
        # Get available number
        Write-Verbose "Getting available number from $Office range..."
        $number = Get-NpAvailableNumber -SystemId $SystemId -SystemType $SystemType -RangeName $Office
        
        if (-not $number) {
            throw "No available numbers in $Office range"
        }
        
        # Reserve the number
        Write-Verbose "Reserving number $($number.Number) for $EmployeeName..."
        $reservation = $number | New-NpReservation `
            -Reason "New Hire" `
            -Description "$EmployeeName - $Department - Start Date: $(Get-Date -Format 'yyyy-MM-dd')" `
            -NeverExpires
        
        # Create result object
        $result = [PSCustomObject]@{
            EmployeeName = $EmployeeName
            Office = $Office
            Department = $Department
            Extension = $reservation.Number
            PhoneNumber = $reservation.E164Number
            ReservationDate = Get-Date
            Status = "Success"
        }
        
        # Log to file
        $logPath = Join-Path $env:TEMP "EmployeePhoneAllocations.csv"
        $result | Export-Csv -Path $logPath -Append -NoTypeInformation
        
        Write-ColorOutput "Successfully allocated $($result.PhoneNumber) to $EmployeeName" -Color Green
        
        return $result
    }
    catch {
        Write-Error "Failed to allocate phone number: $_"
        
        # Log failure
        $failureLog = [PSCustomObject]@{
            EmployeeName = $EmployeeName
            Office = $Office
            Department = $Department
            Extension = "N/A"
            PhoneNumber = "N/A"
            ReservationDate = Get-Date
            Status = "Failed: $_"
        }
        
        $logPath = Join-Path $env:TEMP "EmployeePhoneAllocations.csv"
        $failureLog | Export-Csv -Path $logPath -Append -NoTypeInformation
        
        throw
    }
}
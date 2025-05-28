# NumberPro PowerShell Module

A PowerShell module for managing telephone numbers through the 2nd Nature NumberPro API.

## Features

- Connect to 2nd Nature NumberPro servers (HTTP/HTTPS)
- Get available numbers from specified ranges
- Create and manage number reservations
- Automatic retry logic for handling race conditions
- E.164 format output for all phone numbers
- Support for Skype for Business (SfB) and Cisco systems
- Pipeline-friendly cmdlets with custom PowerShell objects

## Requirements

- PowerShell 5.1 or higher
- Access to a 2nd Nature NumberPro server
- Valid credentials for the NumberPro API

## Installation

1. Download the module files:
   - `NumberPro.psd1` (module manifest)
   - `NumberPro.psm1` (module code)

2. Place the files in a folder named `NumberPro` in one of your PowerShell module paths:
   ```powershell
   # Check your module paths
   $env:PSModulePath -split ';'
   
   # Common location for user modules
   # C:\Users\<username>\Documents\WindowsPowerShell\Modules\NumberPro\
   ```

3. Import the module:
   ```powershell
   Import-Module NumberPro
   ```

## Quick Start

### Connect to NumberPro Server

```powershell
# Get credentials
$cred = Get-Credential -Message "Enter NumberPro credentials"

# Connect to server (HTTPS by default)
Connect-NpServer -Server "numberpro.company.com" -Credential $cred

# Or connect using HTTP
Connect-NpServer -Server "numberpro.company.com" -Port 8080 -Credential $cred -UseHttp
```

### Get Available Numbers

```powershell
# Get single available number
$number = Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Minneapolis"

# Get multiple consecutive numbers
$numbers = Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Duluth" -Count 5 -Consecutive
```

### Create Reservations

```powershell
# Reserve a number that never expires
$reservation = New-NpReservation -SystemId 1 -SystemType SfB -Number "6125554289" `
    -Reason "New Hire" -Description "For John Doe" -NeverExpires

# Reserve with expiration date (90-day aging)
New-NpReservation -SystemId 1 -SystemType SfB -Number "6125554290" `
    -Reason "Aging" -ExpirationDate (Get-Date).AddDays(90)

# Pipeline example - get and reserve in one operation
Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Minneapolis" |
    New-NpReservation -Reason "New Hire" -Description "Auto-reserved"
```

### View and Remove Reservations

```powershell
# View all reservations
Get-NpReservation -SystemId 1 -SystemType SfB

# Filter by reason
Get-NpReservation -SystemId 1 -SystemType SfB -Reason "New Hire"

# Remove a specific reservation
Remove-NpReservation -SystemId 1 -SystemType SfB -Number "6125554289"

# Remove all aging reservations
Get-NpReservation -SystemId 1 -SystemType SfB -Reason "Aging" |
    Remove-NpReservation -Force
```

## Common Scenarios

### Employee Onboarding Automation

```powershell
function New-EmployeePhoneNumber {
    param(
        [string]$EmployeeName,
        [string]$Office,
        [int]$SystemId = 1
    )
    
    # Get available number from office range
    $number = Get-NpAvailableNumber -SystemId $SystemId -SystemType SfB -RangeName $Office
    
    if ($number) {
        # Reserve the number
        $reservation = $number | New-NpReservation `
            -Reason "New Hire" `
            -Description "Assigned to $EmployeeName" `
            -NeverExpires
        
        # Return the E.164 formatted number for AD/other systems
        return $reservation.E164Number
    }
    else {
        throw "No available numbers in $Office range"
    }
}

# Usage
$phoneNumber = New-EmployeePhoneNumber -EmployeeName "John Doe" -Office "Minneapolis"
```

### Bulk Number Reservation

```powershell
# Reserve 10 numbers for upcoming project
$projectNumbers = Get-NpAvailableNumber -SystemId 1 -SystemType SfB `
    -RangeName "Minneapolis" -Count 10

$projectNumbers | ForEach-Object {
    $_ | New-NpReservation `
        -Reason "Project Reserve" `
        -Description "Q1 2024 Expansion" `
        -ExpirationDate (Get-Date).AddDays(180)
}
```

### Number Range Reporting

```powershell
# Get all ranges and their capacity
$ranges = Get-NpNumberRange

$ranges | Select-Object Name, Description, Count, StartE164, EndE164 |
    Format-Table -AutoSize
```

## Cmdlet Reference

### Connection Management
- `Connect-NpServer` - Establish connection to NumberPro server
- `Disconnect-NpServer` - Close connection
- `Test-NpConnection` - Verify connection status

### Number Management
- `Get-NpNumberRange` - List available number ranges
- `Get-NpAvailableNumber` - Get next available number(s)

### Reservation Management
- `New-NpReservation` - Create a number reservation
- `Get-NpReservation` - View existing reservations
- `Remove-NpReservation` - Delete a reservation

## Error Handling

The module provides detailed error messages for common scenarios:

```powershell
try {
    $number = Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "InvalidRange"
}
catch {
    Write-Error "Failed to get number: $_"
}
```

## Best Practices

1. **Always reserve numbers immediately** after getting them to avoid race conditions
2. **Use the pipeline** to combine get and reserve operations
3. **Set appropriate expiration dates** for temporary reservations
4. **Use descriptive reasons and descriptions** for audit trails
5. **Test connectivity** before bulk operations using `Test-NpConnection`

## Troubleshooting

### Connection Issues
```powershell
# Enable verbose output
$VerbosePreference = "Continue"
Connect-NpServer -Server "server.com" -Credential $cred -Verbose
```

### View Raw API Responses
```powershell
# The module returns custom objects, but you can see the original data
$DebugPreference = "Continue"
Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Test" -Debug
```

## Support

For issues with the module, check:
1. Connection status with `Test-NpConnection`
2. Valid credentials and permissions
3. Correct system ID and type
4. Valid range names

For API-specific issues, consult your 2nd Nature NumberPro documentation.
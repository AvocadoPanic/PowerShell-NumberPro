#
# NumberPro.psm1
# PowerShell module for 2nd Nature NumberPro API
#

# Module-scoped variables
$script:NpConnection = $null
$script:DefaultHeaders = @{
    'Accept' = 'application/json'
    'Content-Type' = 'application/json'
}

#region Helper Functions

function ConvertTo-E164Format {
    <#
    .SYNOPSIS
    Converts a phone number to E.164 format
    
    .DESCRIPTION
    Takes a phone number in various formats and converts it to E.164 format (+1 for US numbers)
    
    .PARAMETER Number
    The phone number to convert
    
    .EXAMPLE
    ConvertTo-E164Format -Number "3205551011"
    Returns: +13205551011
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Number
    )
    
    # Remove all non-numeric characters
    $cleanNumber = $Number -replace '[^\d]', ''
    
    # Handle different number lengths
    switch ($cleanNumber.Length) {
        10 { 
            # US number without country code
            return "+1{0}" -f $cleanNumber
        }
        11 {
            if ($cleanNumber.StartsWith('1')) {
                # US number with country code
                return "+{0}" -f $cleanNumber
            }
            else {
                Write-Warning "Unexpected 11-digit number format: $Number"
                return "+{0}" -f $cleanNumber
            }
        }
        7 {
            # Extension only - cannot convert to E.164
            Write-Warning "Extension-only number cannot be converted to E.164: $Number"
            return $Number
        }
        default {
            Write-Warning "Unexpected number format: $Number"
            return "+{0}" -f $cleanNumber
        }
    }
}

function Invoke-NpRestMethod {
    <#
    .SYNOPSIS
    Wrapper for Invoke-RestMethod with NumberPro-specific error handling
    
    .DESCRIPTION
    Handles authentication, error responses, and common API patterns
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = 'GET',
        
        [Parameter(Mandatory = $false)]
        [object]$Body,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{}
    )
    
    if (-not $script:NpConnection) {
        throw "Not connected to NumberPro server. Please run Connect-NpServer first."
    }
    
    # Merge headers
    $requestHeaders = $script:DefaultHeaders.Clone()
    $requestHeaders['Authorization'] = $script:NpConnection.AuthHeader
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }
    
    $params = @{
        Uri = $Uri
        Method = $Method
        Headers = $requestHeaders
        ErrorAction = 'Stop'
    }
    
    if ($Body) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10
    }
    
    try {
        Write-Verbose "Invoking REST method: $Method $Uri"
        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        $errorDetails = $null
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd()
            
            try {
                $errorDetails = $responseBody | ConvertFrom-Json
            }
            catch {
                $errorDetails = @{ Error = $responseBody }
            }
        }
        
        $errorMessage = if ($errorDetails -and $errorDetails.Details) {
            "NumberPro API Error: {0}" -f $errorDetails.Details
        }
        elseif ($errorDetails -and $errorDetails.Error) {
            "NumberPro API Error: {0}" -f $errorDetails.Error
        }
        else {
            "NumberPro API Error: {0}" -f $_.Exception.Message
        }
        
        throw $errorMessage
    }
}

function Get-SystemTypeInfo {
    <#
    .SYNOPSIS
    Returns the appropriate resource paths for different system types
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SfB', 'Cisco', 'Avaya')]
        [string]$SystemType
    )
    
    switch ($SystemType) {
        'SfB' {
            return @{
                UnusedResource = 'UnusedLineUri'
                ReservedResource = 'ReservedLineUri'
                NumberField = 'LineUri'
            }
        }
        'Cisco' {
            return @{
                UnusedResource = 'UnusedExtension'
                ReservedResource = 'ReservedExtension'
                NumberField = 'Extension'
            }
        }
        'Avaya' {
            return @{
                UnusedResource = 'UnusedStation'
                ReservedResource = 'ReservedStation'
                NumberField = 'StationExtension'
            }
        }
    }
}

#endregion

#region Public Functions

function Connect-NpServer {
    <#
    .SYNOPSIS
    Connects to a 2nd Nature NumberPro server
    
    .DESCRIPTION
    Establishes a connection to the NumberPro API server using basic authentication
    
    .PARAMETER Server
    The server hostname or IP address
    
    .PARAMETER Port
    The server port (default: 8443 for HTTPS, 8080 for HTTP)
    
    .PARAMETER Credential
    PSCredential object containing username and password
    
    .PARAMETER UseHttp
    Use HTTP instead of HTTPS
    
    .EXAMPLE
    $cred = Get-Credential
    Connect-NpServer -Server "numberpro.company.com" -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,
        
        [Parameter(Mandatory = $false)]
        [int]$Port,
        
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseHttp
    )
    
    # Determine protocol and default port
    $protocol = if ($UseHttp) { "http" } else { "https" }
    if (-not $Port) {
        $Port = if ($UseHttp) { 8080 } else { 8443 }
    }
    
    # Build base URL
    $baseUrl = "{0}://{1}:{2}/2n" -f $protocol, $Server, $Port
    
    # Create authentication header
    $authInfo = "{0}:{1}" -f $Credential.UserName, $Credential.GetNetworkCredential().Password
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
    $authHeader = "Basic {0}" -f [Convert]::ToBase64String($authBytes)
    
    # Test connection
    try {
        $testUri = "{0}/System" -f $baseUrl
        $testParams = @{
            Uri = $testUri
            Method = 'GET'
            Headers = @{
                'Authorization' = $authHeader
                'Accept' = 'application/json'
            }
            ErrorAction = 'Stop'
        }
        
        Write-Verbose "Testing connection to $testUri"
        $null = Invoke-RestMethod @testParams
        
        # Store connection info
        $script:NpConnection = @{
            BaseUrl = $baseUrl
            Server = $Server
            Port = $Port
            Protocol = $protocol
            AuthHeader = $authHeader
            Credential = $Credential
        }
        
        Write-Host "Successfully connected to NumberPro server at $baseUrl" -ForegroundColor Green
        
        # Return connection object
        [PSCustomObject]@{
            Server = $Server
            Port = $Port
            Protocol = $protocol
            Connected = $true
            User = $Credential.UserName
        }
    }
    catch {
        throw "Failed to connect to NumberPro server: {0}" -f $_.Exception.Message
    }
}

function Disconnect-NpServer {
    <#
    .SYNOPSIS
    Disconnects from the NumberPro server
    
    .DESCRIPTION
    Clears the stored connection information
    
    .EXAMPLE
    Disconnect-NpServer
    #>
    [CmdletBinding()]
    param()
    
    if ($script:NpConnection) {
        $server = $script:NpConnection.Server
        $script:NpConnection = $null
        Write-Host "Disconnected from NumberPro server: $server" -ForegroundColor Yellow
    }
    else {
        Write-Warning "Not connected to any NumberPro server"
    }
}

function Test-NpConnection {
    <#
    .SYNOPSIS
    Tests the current NumberPro connection
    
    .DESCRIPTION
    Verifies that the connection to the NumberPro server is still valid
    
    .EXAMPLE
    Test-NpConnection
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:NpConnection) {
        Write-Warning "Not connected to any NumberPro server"
        return $false
    }
    
    try {
        $testUri = "{0}/System" -f $script:NpConnection.BaseUrl
        $null = Invoke-NpRestMethod -Uri $testUri -Method GET
        
        Write-Host "Connection to NumberPro server is active" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Connection test failed: {0}" -f $_.Exception.Message
        return $false
    }
}

function Get-NpNumberRange {
    <#
    .SYNOPSIS
    Retrieves number ranges from the NumberPro system
    
    .DESCRIPTION
    Gets information about configured number ranges
    
    .PARAMETER RangeName
    Filter by specific range name
    
    .EXAMPLE
    Get-NpNumberRange
    
    .EXAMPLE
    Get-NpNumberRange -RangeName "Minneapolis"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$RangeName
    )
    
    $uri = "{0}/NumberInventory/Range" -f $script:NpConnection.BaseUrl
    
    if ($RangeName) {
        $uri += "?filter=Name eq '{0}'" -f $RangeName
    }
    
    try {
        $ranges = Invoke-NpRestMethod -Uri $uri
        
        foreach ($range in $ranges) {
            [PSCustomObject]@{
                PSTypeName = 'NumberPro.Range'
                Name = $range.Name
                Description = $range.Description
                Start = $range.Start
                StartE164 = ConvertTo-E164Format -Number $range.Start
                End = $range.End
                EndE164 = ConvertTo-E164Format -Number $range.End
                Count = $range.Count
                ResourceUri = $range.'Sn-Resource-Uri'
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve number ranges: {0}" -f $_.Exception.Message
    }
}

function Get-NpAvailableNumber {
    <#
    .SYNOPSIS
    Gets the next available number(s) from a specified range
    
    .DESCRIPTION
    Retrieves available numbers from the NumberPro system for a specific system and range
    
    .PARAMETER SystemId
    The ID of the system to query
    
    .PARAMETER SystemType
    The type of system (SfB or Cisco)
    
    .PARAMETER RangeName
    The name of the number range to pull from
    
    .PARAMETER Count
    Number of available numbers to return (default: 1)
    
    .PARAMETER Consecutive
    Request consecutive numbers
    
    .EXAMPLE
    Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Minneapolis"
    
    .EXAMPLE
    Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Duluth" -Count 5 -Consecutive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SystemId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('SfB', 'Cisco')]
        [string]$SystemType,
        
        [Parameter(Mandatory = $true)]
        [string]$RangeName,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$Count = 1,
        
        [Parameter(Mandatory = $false)]
        [switch]$Consecutive
    )
    
    $systemInfo = Get-SystemTypeInfo -SystemType $SystemType
    $uri = "{0}/System/{1}/{2}" -f $script:NpConnection.BaseUrl, $SystemId, $systemInfo.UnusedResource
    
    # Build query string
    $queryParams = @(
        "columns=default+InventoryNumber"
        "rangeName={0}" -f $RangeName
        "toRow={0}" -f $Count
    )
    
    if ($Consecutive) {
        $queryParams += "consecutiveNumbers=1"
    }
    
    $uri += "?" + ($queryParams -join "&")
    
    try {
        Write-Verbose "Getting available numbers from: $uri"
        $numbers = Invoke-NpRestMethod -Uri $uri
        
        if (-not $numbers -or $numbers.Count -eq 0) {
            Write-Warning "No available numbers found in range '$RangeName' for system $SystemId"
            return
        }
        
        foreach ($number in $numbers) {
            $inventoryNumber = if ($number.'Inventory Number') { 
                $number.'Inventory Number' 
            } else { 
                $number.$($systemInfo.NumberField) 
            }
            
            [PSCustomObject]@{
                PSTypeName = 'NumberPro.AvailableNumber'
                SystemId = $SystemId
                SystemType = $SystemType
                RangeName = $number.RangeName
                Number = $number.$($systemInfo.NumberField)
                InventoryNumber = $inventoryNumber
                E164Number = ConvertTo-E164Format -Number $inventoryNumber
                ResourceUri = $number.'Sn-Resource-Uri'
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve available numbers: {0}" -f $_.Exception.Message
    }
}

function New-NpReservation {
    <#
    .SYNOPSIS
    Creates a reservation for a phone number
    
    .DESCRIPTION
    Reserves a number to prevent it from being assigned to another user.
    Implements automatic retry logic to handle race conditions.
    
    .PARAMETER SystemId
    The ID of the system
    
    .PARAMETER SystemType
    The type of system (SfB or Cisco)
    
    .PARAMETER Number
    The number to reserve (in system format)
    
    .PARAMETER Reason
    Reason for the reservation
    
    .PARAMETER Description
    Description of the reservation
    
    .PARAMETER NeverExpires
    Set the reservation to never expire
    
    .PARAMETER ExpirationDate
    Date when the reservation should expire
    
    .PARAMETER RetryCount
    Number of retry attempts if reservation fails (default: 10)
    
    .EXAMPLE
    $availableNumber = Get-NpAvailableNumber -SystemId 1 -SystemType SfB -RangeName "Minneapolis"
    $availableNumber | New-NpReservation -Reason "New Hire" -Description "For John Doe"
    
    .EXAMPLE
    New-NpReservation -SystemId 1 -SystemType SfB -Number "6125554289" -Reason "Aging" -ExpirationDate (Get-Date).AddDays(90)
    #>
    [CmdletBinding(DefaultParameterSetName = 'NeverExpires')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int]$SystemId,
        
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('SfB', 'Cisco')]
        [string]$SystemType,
        
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Number,
        
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        
        [Parameter(Mandatory = $false)]
        [string]$Description,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'NeverExpires')]
        [switch]$NeverExpires,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ExpirationDate')]
        [DateTime]$ExpirationDate,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$RetryCount = 10
    )
    
    Process {
        $systemInfo = Get-SystemTypeInfo -SystemType $SystemType
        $baseUri = "{0}/System/{1}/{2}" -f $script:NpConnection.BaseUrl, $SystemId, $systemInfo.ReservedResource
        
        # Build reservation object
        $reservation = @{
            $systemInfo.NumberField = $Number
            Reason = $Reason
        }
        
        if ($Description) {
            $reservation.Description = $Description
        }
        
        if ($NeverExpires) {
            $reservation.NeverExpires = "Yes"
        }
        elseif ($ExpirationDate) {
            $reservation.ExpirationDate = $ExpirationDate.ToString("yyyy-MM-dd")
        }
        
        # Attempt to create reservation with retry logic
        $attempt = 0
        $reserved = $false
        
        while (-not $reserved -and $attempt -lt $RetryCount) {
            $attempt++
            
            try {
                Write-Verbose "Attempting to reserve number $Number (attempt $attempt of $RetryCount)"
                $result = Invoke-NpRestMethod -Uri $baseUri -Method POST -Body $reservation
                $reserved = $true
                
                Write-Host "Successfully reserved number: $Number" -ForegroundColor Green
                
                # Get the created reservation details
                $reservationUri = "{0}/{1}" -f $baseUri, $Number
                $createdReservation = Invoke-NpRestMethod -Uri $reservationUri
                
                [PSCustomObject]@{
                    PSTypeName = 'NumberPro.Reservation'
                    SystemId = $SystemId
                    SystemType = $SystemType
                    Number = $Number
                    E164Number = ConvertTo-E164Format -Number $Number
                    Reason = $createdReservation.Reason
                    Description = $createdReservation.Description
                    NeverExpires = $createdReservation.NeverExpires -eq "Yes"
                    ExpirationDate = $createdReservation.ExpirationDate
                    ResourceUri = $createdReservation.'Sn-Resource-Uri'
                }
            }
            catch {
                if ($_.Exception.Message -match "already exists" -and $attempt -lt $RetryCount) {
                    Write-Verbose "Reservation failed, number already taken. Getting new number..."
                    
                    # Get a new available number
                    $newNumbers = Get-NpAvailableNumber -SystemId $SystemId -SystemType $SystemType -RangeName $RangeName -Count ($attempt + 1)
                    if ($newNumbers -and $newNumbers.Count -ge $attempt) {
                        $Number = $newNumbers[$attempt - 1].Number
                        $reservation.$($systemInfo.NumberField) = $Number
                    }
                    else {
                        throw "Unable to find alternative available number after $attempt attempts"
                    }
                }
                else {
                    throw
                }
            }
        }
        
        if (-not $reserved) {
            throw "Failed to reserve a number after $RetryCount attempts"
        }
    }
}

function Get-NpReservation {
    <#
    .SYNOPSIS
    Retrieves existing reservations
    
    .DESCRIPTION
    Gets reservation information from the NumberPro system
    
    .PARAMETER SystemId
    The ID of the system
    
    .PARAMETER SystemType
    The type of system (SfB or Cisco)
    
    .PARAMETER Number
    Filter by specific number
    
    .PARAMETER Reason
    Filter by reservation reason
    
    .EXAMPLE
    Get-NpReservation -SystemId 1 -SystemType SfB
    
    .EXAMPLE
    Get-NpReservation -SystemId 1 -SystemType SfB -Reason "New Hire"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SystemId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('SfB', 'Cisco')]
        [string]$SystemType,
        
        [Parameter(Mandatory = $false)]
        [string]$Number,
        
        [Parameter(Mandatory = $false)]
        [string]$Reason
    )
    
    $systemInfo = Get-SystemTypeInfo -SystemType $SystemType
    $uri = "{0}/System/{1}/{2}" -f $script:NpConnection.BaseUrl, $SystemId, $systemInfo.ReservedResource
    
    # Add filters if specified
    $filters = @()
    if ($Number) {
        $filters += "{0} eq '{1}'" -f $systemInfo.NumberField, $Number
    }
    if ($Reason) {
        $filters += "Reason eq '{0}'" -f $Reason
    }
    
    if ($filters.Count -gt 0) {
        $uri += "?filter=" + ($filters -join " and ")
    }
    
    try {
        $reservations = Invoke-NpRestMethod -Uri $uri
        
        foreach ($reservation in $reservations) {
            [PSCustomObject]@{
                PSTypeName = 'NumberPro.Reservation'
                SystemId = $SystemId
                SystemType = $SystemType
                Number = $reservation.$($systemInfo.NumberField)
                E164Number = ConvertTo-E164Format -Number $reservation.$($systemInfo.NumberField)
                Reason = $reservation.Reason
                Description = $reservation.Description
                NeverExpires = $reservation.NeverExpires -eq "Yes"
                ExpirationDate = $reservation.ExpirationDate
                ResourceUri = $reservation.'Sn-Resource-Uri'
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve reservations: {0}" -f $_.Exception.Message
    }
}

function Remove-NpReservation {
    <#
    .SYNOPSIS
    Removes a number reservation
    
    .DESCRIPTION
    Deletes an existing reservation from the NumberPro system
    
    .PARAMETER SystemId
    The ID of the system
    
    .PARAMETER SystemType
    The type of system (SfB or Cisco)
    
    .PARAMETER Number
    The number to unreserve
    
    .PARAMETER Force
    Skip confirmation prompt
    
    .EXAMPLE
    Remove-NpReservation -SystemId 1 -SystemType SfB -Number "6125554289"
    
    .EXAMPLE
    Get-NpReservation -SystemId 1 -SystemType SfB -Reason "Aging" | Remove-NpReservation -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int]$SystemId,
        
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('SfB', 'Cisco')]
        [string]$SystemType,
        
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Number,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    Process {
        $systemInfo = Get-SystemTypeInfo -SystemType $SystemType
        $uri = "{0}/System/{1}/{2}/{3}" -f $script:NpConnection.BaseUrl, $SystemId, $systemInfo.ReservedResource, $Number
        
        if ($Force -or $PSCmdlet.ShouldProcess($Number, "Remove reservation")) {
            try {
                Write-Verbose "Removing reservation for number: $Number"
                Invoke-NpRestMethod -Uri $uri -Method DELETE
                
                Write-Host "Successfully removed reservation for number: $Number" -ForegroundColor Green
                
                [PSCustomObject]@{
                    SystemId = $SystemId
                    SystemType = $SystemType
                    Number = $Number
                    Status = "Removed"
                }
            }
            catch {
                Write-Error "Failed to remove reservation for number {0}: {1}" -f $Number, $_.Exception.Message
            }
        }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Connect-NpServer',
    'Disconnect-NpServer',
    'Test-NpConnection',
    'Get-NpNumberRange',
    'Get-NpAvailableNumber',
    'New-NpReservation',
    'Get-NpReservation',
    'Remove-NpReservation'
)
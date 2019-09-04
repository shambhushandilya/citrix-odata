function Get-CitrixMonitorServiceData {
    
    <#
    .SYNOPSIS
    Returns Citrix Virtual Apps and Desktops usage data over a period of time.
    
    .DESCRIPTION
    The Get-CitrixMonitorServiceData cmdlet gets an object with usage data (sessions, number of virtual machines)
    of a Citrix Virtual Apps and Desktops Site over an specified period of time.
    
    This cmdlet takes a required parameter: a list of Citrix Virtual Apps and Desktops Delivery Controllers.
    Without any other parameters, it will use the current user to connect to the DDCs and collect usage information
    for the past day.
    
    It will return a custom object with session, user, login times and number of VMs for every Delivery Group
    present on the selected Site.
    
    Additional filters can be applied to select a different date range.
    
    .LINK
    https://github.com/karjona/citrix-odata
    
    .PARAMETER DeliveryControllers
    Specifies a single Citrix Virtual Apps and Desktops Delivery Controller or an array of Citrix DDCs from
    different Sites to collect data from.
    
    .PARAMETER Credential
    Specifies a user account that has permission to send the request. The default is the current user. A minimum of
    read-only administrator permissions on Citrix Virtual Apps and Desktops are required to collect this data.
    
    Enter a PSCredential object, such as one generated by the Get-Credential cmdlet.
    
    .PARAMETER StartDate
    Specifies the start date for the report in yyyy-MM-ddTHH:mm:ss. If you omit the time part, 00:00:00 will be
    automatically appended to the date.
    
    The default value is yesterday's date, midnight.
    
    .PARAMETER EndDate
    Specifies the end date for the report in yyyy-MM-ddTHH:mm:ss. If you omit the time part, 23:59:59 will be
    automatically appended to the date.
    
    The default value if no start date is specified is yesterday's date, 23:59:59.
    If a start date is specified but no end date is provided, the end date will automatically be set 23 hours,
    59 minutes and 59 seconds after the start date.
    
    .EXAMPLE
    Get-CitrixMonitorServiceData -DeliveryControllers @('myddc01.example.com', 'myddc02.example.com') -Credential $(Get-Credential)
    
    Example 1: Get the usage data for the past day
    Returns the usage data for all Delivery Groups present on myddc01 and myddc02 Delivery Controllers using the
    specified credentials. The returned custom object will contain yesterday's usage data.
    
    .EXAMPLE
    Get-CitrixMonitorServiceData -DeliveryControllers 'myddc01.example.com' -StartDate '2019-08-01T00:00:00' -EndDate '2019-08-31T23:59:59'
    
    Example 2: Get the usage data for the month of August
    Returns the usage data for all Delivery Groups present on myddc01 using the credentials of the current user.
    The returned custom object will contain the usage data for the month of August 2019.
    
    .COMPONENT
    citrix-odata
    #>
    
    [CmdletBinding()]
    [OutputType('citrix-odata.CitrixMonitorServiceData')]
    
    param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0, HelpMessage='Enter one or more Delivery' +
    ' Controllers separated by commas.')]
    [Alias('ComputerName')]
    [String[]]
    $DeliveryControllers,
    
    [Parameter()]
    [PSCredential]
    $Credential,
    
    [Parameter()]
    [ValidateScript({
        if ($(New-TimeSpan -Start $_ -End $(Get-Date)).TotalSeconds -ge 1) {
            return $true
        }
        throw "The provided start date cannot be in the future."
    })]
    [DateTime]
    $StartDate = "$(Get-Date (Get-Date).AddDays(-1) -Format 'yyyy-MM-ddT00:00:00')",
    
    [Parameter()]
    [ValidateScript({
        if ($null -eq $StartDate) {
            $StartDate = "$(Get-Date (Get-Date).AddDays(-1) -Format 'yyyy-MM-ddT00:00:00')"
        }
        if ($(New-TimeSpan -Start $StartDate -End $_).TotalSeconds -ge 1) {
            return $true
        }
        throw "The provided end date cannot be earlier than the start date."
    })]
    [DateTime]
    $EndDate = "$(Get-Date $StartDate.AddSeconds(86399) -Format 'yyyy-MM-ddTHH:mm:ss')"
    )
    
    begin {
        Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
        -Status 'Attempting to connect to Delivery Controllers'
        if ($Credential) {
            $DeliveryControllers = Test-CitrixDDCConnectivity -DeliveryControllers $DeliveryControllers `
            -Credential $Credential
        } else {
            $DeliveryControllers = Test-CitrixDDCConnectivity -DeliveryControllers $DeliveryControllers
        }
        Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
        -Status 'Attempting to connect to Delivery Controllers' -Completed
    }
    
    process {
        if ($DeliveryControllers.Count -ge 2) {
            $DeliveryControllerObject = @()
        }

        foreach ($DeliveryController in $DeliveryControllers) {
            Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
            -Status 'Retrieving usage data for Delivery Controllers'

            if ($Credential) {
                $DeliveryGroupsForDDC = Get-CitrixDeliveryGroups -DeliveryController $DeliveryController `
                -Credential $Credential
                $Machines = Get-CitrixMachines -DeliveryController $DeliveryController -Credential $Credential
            } else {
                $DeliveryGroupsForDDC = Get-CitrixDeliveryGroups -DeliveryController $DeliveryController
                $Machines = Get-CitrixMachines -DeliveryController $DeliveryController
            }
            
            if ($DeliveryGroupsForDDC.value.length -ge 1) {
                $DeliveryGroupInfo = @()
                if ($Credential) {
                    $ConcurrentSessionsForDDC = Get-CitrixConcurrentSessions `
                    -DeliveryController $DeliveryController -Credential $Credential -StartDate $StartDate `
                    -EndDate $EndDate
                } else {
                    $ConcurrentSessionsForDDC = Get-CitrixConcurrentSessions `
                    -DeliveryController $DeliveryController -StartDate $StartDate -EndDate $EndDate
                }
                
                foreach ($DeliveryGroup in $DeliveryGroupsForDDC.value) {
                    Write-Progress -Id 1 -Activity 'Calculating maximum sessions per Delivery Group' `
                    -Status (
                    "Total progress: $($DeliveryGroupsForDDC.value.IndexOf($DeliveryGroup))`/" +
                    "$($DeliveryGroupsForDDC.value.length) - " +
                    "Calculating sessions for $($DeliveryGroup.Name)"
                    ) -PercentComplete `
                    ($DeliveryGroupsForDDC.value.IndexOf($DeliveryGroup)/$DeliveryGroupsForDDC.value.length*100)
                    
                    $DeliveryGroupInfo += [PSCustomObject]@{
                        PSTypeName = 'citrix-odata.CitrixMonitorDeliveryGroupInfo'
                        Name = $DeliveryGroup.Name
                        Id = $DeliveryGroup.Id
                        MaxConcurrentSessions = Get-CitrixMaximumSessionsForDG `
                        -SessionsObject $ConcurrentSessionsForDDC -DeliveryGroupId $DeliveryGroup.Id
                        MachineCount = Get-CitrixMachinesForDG -MachinesObject $Machines `
                        -DeliveryGroupId $DeliveryGroup.Id
                    }
                }

                Write-Progress -Id 1 -Activity 'Calculating maximum sessions per Delivery Group' `
                -Completed

            } else {
                $DeliveryGroupInfo = $null
            }
            
            Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
            -Status 'Retrieving usage data for Delivery Controllers' -Completed
            
            
            Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
            -Status 'Preparing usage data object'
            
            if ($DeliveryGroupInfo.length -ge 1) {
                $DeliveryControllerObject += [PSCustomObject]@{
                    PSTypeName = 'citrix-odata.CitrixMonitorServiceDeliveryController'
                    DeliveryControllerAddress = $DeliveryController
                    DeliveryGroups = $DeliveryGroupInfo
                }
            } else {
                $DeliveryControllerObject += [PSCustomObject]@{
                    PSTypeName = 'citrix-odata.CitrixMonitorServiceDeliveryController'
                    DeliveryControllerAddress = $DeliveryController
                }
            }
            
            Write-Progress -Id 0 -Activity 'Retrieving Citrix Virtual Apps and Desktops usage data' `
            -Status 'Preparing usage data object' -Completed
        }
        
        # Construct the object that we will return and add the data from the loop
        $CitrixMonitorServiceData = [PSCustomObject]@{
            PSTypeName = 'citrix-odata.CitrixMonitorServiceData'
            CreationDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
            StartDate = Get-Date -Date $StartDate -Format "yyyy-MM-ddTHH:mm:ss"
            EndDate = Get-Date -Date $EndDate -Format "yyyy-MM-ddTHH:mm:ss"
            DeliveryControllers = $DeliveryControllerObject
        }
        $CitrixMonitorServiceData
    }
}

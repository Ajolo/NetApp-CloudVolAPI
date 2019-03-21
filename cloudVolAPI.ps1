# +---------------------------------------------------------------------------
# | File    : cloudVolAPI.PS1                                          
# | Version : 1.0                                          
# | Purpose : Pull Cloud Volume info from web to better assist in volume deployment
# |           based on user input of necessary throughput or IOPS 
# | Usage   : .\cloudVolAPI.ps1
# +---------------------------------------------------------------------------
# | Maintenance History                                            
# | -------------------                                            
# | Name              Date [YYYY-MM-DD]      Version       Description        
# | --------------------------------------------------------------------------
# | Alex Lopez        2018-09-26             1.0           Initial release
# +-------------------------------------------------------------------------------
# ********************************************************************************

# ***********************
# Globals
# ***********************

$URI = "http://nfsaas.runarberg.test/v1/"
$apiKey = "omitted :)" 
$secretKey = "omitted :)"
$region =  "us-east-1" 


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("API-KEY", $apiKey)
$headers.Add("SECRET-KEY", $secretKey)


# ***********************
# Functions
# ***********************

Function GetFileSystems {
    Invoke-RestMethod -Method Get -Uri ($URI+"FileSystems") -Headers $headers
}

Function GetWebTables {
    $tableURL = "https://docs.netapp.com/us-en/cloud_volumes/aws/reference_selecting_service_level_and_quota.html"
    $page = Invoke-WebRequest $tableURL
    $tables = @($page.ParsedHtml.IHTMLDocument3_getElementsByTagName("TABLE"))
    $table = $tables[2]
    $titles = @('Capacity (TB)', 'Standard (MB/s)', 'Cost1', 'Premium (MB/s)', 'Cost2', 'Extreme (MB/s)', 'Cost3')
    $rows = @($table.Rows)

    foreach($row in $rows | select -skip 2)
    {
        $cells = @($row.Cells)
        $resultObject = [Ordered] @{}
        for($counter = 0; $counter -lt $cells.Count; $counter++)
        {
            $title = $titles[$counter]
            if(-not $title) { continue }
            if ($cells[$counter].InnerText -contains '*$*') {
                # $resultObject[$title] = ("" + $cells[$counter+1].InnerText).Trim()
            }
            else {
                $resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
            }
            
        }

    ## Cast hashtable to a PSCustomObject
    [PSCustomObject] $resultObject
    }
} 
# GetWebTables | Format-Table -Property 'Capacity (TB)','Standard (MB/s)','Premium (MB/s)','Extreme (MB/s)'

Function CreateCloudVol ($volName, $creationToken, $quota, $serviceLevel, $protocol) {
    $filesystem = '
    {
      "name": "' + $volName + '", 
      "region": "' + $region + '",
      "backupPolicy": {
        "dailyBackupsToKeep": 7,
        "enabled": false,
        "monthlyBackupsToKeep": 12,
        "weeklyBackupsToKeep": 52
      },
      "creationToken": "' + $creationToken + '",
      "jobs": [
        {}
      ],
      "labels": [
        "API"
      ],
      "poolId": "",
      "protocolTypes": [' + $protocol + '],
      "quotaInBytes": ' + $quota + ',
      "serviceLevel": "' + $serviceLevel + '",
      "smbShareSettings": [
        "encrypt_data"
      ],
      "snapReserve": 20,
      "snapshotPolicy": {
        "dailySchedule": {
          "hour": 23,
          "minute": 10,
          "snapshotsToKeep": 7
        },
        "enabled": false,
        "hourlySchedule": {
          "minute": 10,
          "snapshotsToKeep": 24
        },
        "monthlySchedule": {
          "daysOfMonth": "1,15,31",
          "hour": 23,
          "minute": 10,
          "snapshotsToKeep": 12
        },
        "weeklySchedule": {
          "day": "Saturday,Sunday",
          "hour": 23,
          "minute": 10,
          "snapshotsToKeep": 52
        }
      }
    }'
    # $filesystem
    Invoke-RestMethod -Method Post -Uri ($URI+"FileSystems") -Headers $headers -Body $filesystem -ContentType 'application/json'   
}
# CreateCloudVol 'API Test Vol' 'api-nfs-volume' '30000000000' 'extreme' '"NFSv3"' 

Function GetInput {
    # store table locally
    $table = @(GetWebTables) 
    do {
        do {
            Write-Host "Enter IOPS or Throughput" 
            # Write-Host "***********************" -ForegroundColor Green
            #[ValidateRange(0,?)]
            [int]$userIOPS = Read-Host -Prompt 'IOPS (if unknown, hit enter)' 
            if ($userIOPS) {
                [ValidateRange(4,128)][int]$userBlock = Read-Host -Prompt 'Block size (in KB, values 4 - 128)'
                # TP = (IOps * block size [kb]) / 1024
                $userTP = ($userIOPS * $userBlock) / 1024
            }
            else {
                [ValidateRange(0,3500)]$userTP = Read-Host -Prompt 'ThroughPut (in MB/s, values 16 - 3,500)'
            }
            # display offered configs based on table
            if (!$userIOPS -and !$userTP) {
                Write-Host 'Please enter a value' -ForegroundColor Yellow
                $continue = $false
            }
            else {
                $continue = $true
            }
        } while ($continue -eq $false)

        # $table | Where-Object {[int]$_.'Standard (MB/s)' -ge 900} | Select -first 1 | Format-Table -Property 'Capacity (TB)','Standard (MB/s)'
        # $table | Where-Object {[int]$_.'Premium (MB/s)' -ge 900} | Select -first 1 | Format-Table -Property 'Capacity (TB)','Premium (MB/s)'
        # $table | Where-Object {[int]$_.'Extreme (MB/s)' -ge 900} | Select -first 1 | Format-Table -Property 'Capacity (TB)','Extreme (MB/s)'

        # store config options based on input
        $standardTP = $table | Where-Object {[int]$_.'Standard (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Standard (MB/s)' -First 1; 
        $standardCapacity = $table | Where-Object {[int]$_.'Standard (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Capacity (TB)' -First 1;

        $premiumTP = $table | Where-Object {[int]$_.'Premium (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Premium (MB/s)' -First 1; 
        $premiumCapacity = $table | Where-Object {[int]$_.'Premium (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Capacity (TB)' -First 1;

        $extremeTP = $table | Where-Object {[int]$_.'Extreme (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Extreme (MB/s)' -First 1; 
        $extremeCapacity = $table | Where-Object {[int]$_.'Extreme (MB/s)' -ge $userTP} |  Select -ExpandProperty 'Capacity (TB)' -First 1;

        # create a new table, add in above values and format
        $newTable = New-Object system.Data.DataTable "Volume Options"
        $quotaColumn = New-Object system.Data.DataColumn 'Quota (TB)',([string])
        $tpColumn = New-Object system.Data.DataColumn 'Throughput (MB/s)',([string])
        $slColumn = New-Object system.Data.DataColumn 'Service Level',([string])

        $newTable.Columns.Add($slColumn)
        $newTable.Columns.Add($quotaColumn)
        $newTable.Columns.Add($tpColumn)
    
        $standardRow = $newTable.NewRow()
        $premiumRow = $newTable.NewRow()
        $extremeRow = $newTable.NewRow()

        $standardRow.'Service Level' = '1) Standard'
        $standardRow.'Quota (TB)' = $standardCapacity
        $standardRow.'Throughput (MB/s)' = $standardTP
        $newTable.Rows.Add($standardRow)

        $premiumRow.'Service Level' = '2) Premium'
        $premiumRow.'Quota (TB)' = $premiumCapacity
        $premiumRow.'Throughput (MB/s)' = $premiumTP
        $newTable.Rows.Add($premiumRow)

        $extremeRow.'Service Level' = '3) Extreme'
        $extremeRow.'Quota (TB)' = $extremeCapacity
        $extremeRow.'Throughput (MB/s)' = $extremeTP
        $newTable.Rows.Add($extremeRow)

        # output table
        Write-Host 'Available configurations based on input:'
        $newTable | Out-Host
    
        # deploy volume loop
        # $deployYN = Read-Host -Prompt 'Would you like to deploy one of these volumes now? (Y/N)'
        # if ($deployYN -eq 'y') {
            [ValidateRange(1,3)]$userSLOnum = Read-Host -Prompt 'Select a Service Level from the above table [1, 2, 3]'
            Switch ($userSLOnum) {
                1 { $userSLO = "basic"; [double]$userQuota = $standardCapacity } # basic --> standard
                2 { $userSLO = "standard"; [double]$userQuota = $premiumCapacity} # standard --> premium
                3 { $userSLO = "extreme"; [double]$userQuota = $extremeCapacity } # extreme --> extreme
            }

            #if ($userSLOnum -eq '1') { $userSLO = "basic"; [double]$userQuota = $standardCapacity } 
            #elseif ($userSLOnum -eq '2') { $userSLO = "standard"; [double]$userQuota = $premiumCapacity} # standard --> premium
            #else { $userSLO = "extreme"; [double]$userQuota = $extremeCapacity } # extreme --> extreme

            # get desired protocol
            
            [ValidateRange(1,3)]$protocol = Read-Host -Prompt 'Select a protocol [NFSv3 - 1, SMB - 2, Dual - 3]'
            Switch ($protocol) {
                1 { $userProtocol = '"NFSv3"' }
                2 { $userProtocol = '"CIFS"' }
                3 { $userProtocol = '"NFSv3", "CIFS"' }
            }
        
            # get name and number of volumes
            $userVolName = Read-Host -Prompt 'Give this volume a name'
            [ValidateRange(0,25)][int]$numVols = Read-Host -Prompt 'How many of these volumes would you like to create?'
        
            # convert the quota (TB) to bytes  
            [double]$quotaInBytes = $userQuota * 1000000000000 

            if ($numVols -lt [int]'2') {
                # if input is 0 or 1, create 1 volume
                CreateCloudVol $userVolName "api-vol-$userVolName" $quotaInBytes $userSLO $userProtocol
            }
            else {
                for ($i=0; $i -lt $numVols; $i++) {
                    Write-Host "Creating  volume number" ($i+1) -BackgroundColor Green
                    CreateCloudVol ($userVolName+$i) ("api-vol-$userVolName"+$i) $quotaInBytes $userSLO $userProtocol
                }
            } 
        # }
        $loopYN = Read-Host "Would you like to create more volumes? (Y/N)"         
    } while ($loopYN -eq 'y') 
}

GetInput
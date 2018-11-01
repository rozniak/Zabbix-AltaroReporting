<#
    .SYNOPSIS
    This script is used for obtaining the status of backups that have taken place in
    Altaro VM Backup.

    .DESCRIPTION
    This script utilises the logs that Altaro VM Backup outputs into Event Viewer in
    order to determine the condition of onsite and offsite backup jobs.

    .PARAMETER BackupType
    The type of backup to check. (Choices: Offsite,
                                           Onsite)

    .PARAMETER ZabbixIP
    The IP address of the Zabbix server/proxy to send the value to.
    
    .EXAMPLE
    Get-AltaroBackupStatus.ps1 -BackupType Offsite -ZabbixIP 10.0.0.240

    .NOTES
    Author: Rory Fewell
    GitHub: https://github.com/rozniak
    Website: https://oddmatics.uk
#>

Param (
    [Parameter(Position=0, Mandatory=$TRUE)]
    [String]
    $BackupType
)

# FUNCTION DEFINITIONS
#
Function Send-ZabbixValue
{
    Param (
        [Parameter(Position=0, Mandatory=$TRUE)]
        [System.Byte]
        $ResultCode
    )

    Write-Host $ResultCode;

    Exit

    # Push value to Zabbix
    #
    & ($env:ProgramFiles + "\Zabbix Agent\bin\win64\zabbix_sender.exe") ("-z", $ZabbixIP, "-p", "10051", "-s", $env:ComputerName, "-k", ("altaro.backupstatus[" + $BackupType.ToLower() + "]"), "-o", $ResultCode)
}

# CONSTANTS
#
$cutoffDateTime = [System.DateTime]::UtcNow.AddDays(-2);
$keywordOffsite = "Offsite Copy Result";
$keywordOnsite = "Backup Result";

# MAIN SCRIPT STARTS
#
$altaroEvents = Get-EventLog -Source "Altaro VM Backup" -LogName Application -Newest 10;
$checkOffsite = $FALSE;
$resultCode = 3; # Unknown

switch ($BackupType.ToLower())
{
    "offsite" {
        $checkOffsite = $TRUE;
    }

    "onsite" {
        $checkOffsite = $FALSE;
    }

    default {
        throw [System.ArgumentException] "Unknown backup type specified.";
    }
}

# Search for first instance of onsite and offsite backup reports
#
$eventOffsite = $NULL;
$eventOnsite  = $NULL;
$foundOffsite = $FALSE;
$foundOnsite  = $FALSE;

for ($i = 0; $i -lt $altaroEvents.Length; $i++)
{
    $message   = $altaroEvents[$i].Message.Split([Environment]::NewLine)[2];

    # Check for offsite
    #
    if (-Not $foundOffsite -And $message.StartsWith($keywordOffsite))
    {
        $eventOffsite = $altaroEvents[$i];
        $foundOffsite = $TRUE;

        continue;
    }

    # Check for onsite
    #
    if (-Not $foundOnsite -And $message.StartsWith($keywordOnsite))
    {
        $eventOnsite = $altaroEvents[$i];
        $foundOnsite = $TRUE;

        continue;
    }
}

# Always check onsite first
#
switch ($eventOnsite.EntryType)
{
    "Error" {
        Send-ZabbixValue -ResultCode 1 # Failure
    }

    "Information" {
        $resultCode = 0; # Success
    }
    
    default {
        Send-ZabbixValue -ResultCode 3; # Unknown
    }
}

# Ensure onsite was within the threshold
#
if ($eventOnsite.TimeGenerated -le $cutoffDateTime)
{
    Send-ZabbixValue -ResultCode 2; # Out of date
}

# See if we need to check offsite
#
if (-Not $checkOffsite)
{
    Send-ZabbixValue -ResultCode $resultCode;
}

switch ($eventOffsite.EntryType)
{
    "Error" {
        Send-ZabbixValue -ResultCode 1; # Failure
    }

    "Information" {
        $resultCode = 0; # Success
    }

    default {
        Send-ZabbixValue -ResultCode 3; # Unknown
    }
}

# Ensure offiste was within the threshold
#
if ($eventOffsite.TimeGenerated -le $cutoffDateTime)
{
    Send-ZabbixValue -ResultCode 2; # Out of date
}
else
{
    Send-ZabbixValue -ResultCode 0; # Success
}
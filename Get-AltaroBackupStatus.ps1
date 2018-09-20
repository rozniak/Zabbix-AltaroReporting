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
    $BackupType,
    [Parameter(Position=1, Mandatory=$TRUE)]
    [ValidatePattern("^(\d+\.){3}\d+$")]
    [String]
    $ZabbixIP
)

$altaroEvents = Get-EventLog -Source "Altaro VM Backup" -LogName Application -Newest 10;
$filterBackupType = "";
$resultCode = 2;

switch ($BackupType.ToLower())
{
    "offsite" {
        $filterBackupType = "Offsite Copy Result";
    }

    "onsite" {
        $filterBackupType = "Backup Result";
    }

    default {
        throw [System.ArgumentException] "Unknown backup type specified.";
    }
}

# Search for the backup type we want
#
for ($i = 0; $i -lt $altaroEvents.Length; $i++)
{
    $entryType = $altaroEvents[$i].EntryType;
    $message   = $altaroEvents[$i].Message.Split([Environment]::NewLine)[2];

    # If this isn't the right type, skip this iteration
    #
    if (-Not ($message.StartsWith($filterBackupType)))
    {
        continue;
    }

    # This is the result we want, analyse it
    #
    switch ($entryType)
    {
        "Error" {
            $resultCode = 1; # Failure
        }

        "Information" {
            $resultCode = 0; # Success
        }

        default {
            $resultCode = 2; # Unknown
        }
    }
}

# Push value to Zabbix
#
& ($env:ProgramFiles + "\Zabbix Agent\bin\win64\zabbix_sender.exe") ("-z", $ZabbixIP, "-p", "10051", "-s", $env:ComputerName, "-k", ("altaro.backupstatus[" + $BackupType.ToLower() + "]"), "-o", $resultCode)
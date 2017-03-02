<#
.Synopsis
   A PowerShell Nagios script to check the health of Hyper-V replicas.
.DESCRIPTION
   A PowerShell Nagios script to check the health of Hyper-V replicas.
   Using the Hyper-V module we can check for VM's that are primary replicas
   and check their replication health. If they are not normal then we report
   back warning or critical depending on the replication health status.

   Usage with NSClient++
   ---------------------
   Add an external command to your nsclient.ini:
   
   CheckHyperVReplica=cmd /c echo scripts\Check-HyperVReplica.ps1; exit($lastexitcode) | powershell.exe -command -

   Create a nagios service check:
   $USER1$/check_nrpe -H $HOSTADDRESS$ -u -t 90 -c $ARG1$
   ($ARG1$ = CheckHyperVReplica)

.NOTES
   Created by: Jason Wasser @wasserja
   Modified: 10/6/2015 08:37:33 AM  

   Version 1.3

   Changelog:
   v 1.3
    * Now shows critical VM's with Warning VM's if both are present.
    * Using Get-VMReplication appears to be more efficient when grabbing all VM's.
    * I attempted to change to filtering using the Get-VMReplication and Measure-VMReplication, but it required multiple queries increasing run time.
   v 1.2
    * Need to not just include Primary VM's, but Replica's as well. New default is to include Primary and Replica VM's 
      in check. Added switch to include only primary replicas if needed.
    * Added replication health details to output so we know why the VM repliation is unhealthy.

.EXAMPLE
   .\Check-Hyper-VReplica.ps1
   Checks the Hyper-V Replica status of VM's on the local computer and returns status code.
.EXAMPLE
   .\Check-Hyper-VReplica.ps1 -ComputerName SERVER01
   Checks the Hyper-V Replica status of VM's on the remote computer SERVER01 and returns status code.
.LINK
   https://gallery.technet.microsoft.com/scriptcenter/Check-Hyper-V-Replication-415988f7
#>
#Requires -Modules Hyper-V
#Requires -Version 3.0
[CmdletBinding()]
Param
(
    # Name of the server, defaults to local
    [Parameter(Mandatory=$false,
                ValueFromPipelineByPropertyName=$true,
                Position=0)]
    [string]$ComputerName=$env:COMPUTERNAME,
    [int]$returnStateOK = 0,
    [int]$returnStateWarning = 1,
    [int]$returnStateCritical = 2,
    [int]$returnStateUnknown = 3,
    [switch]$IncludePrimaryReplicaOnly=$false
)

Begin
{
}
Process
{
    # Get a list of VM's who are primary replicas whose is not Normal.
    try {
        if ($IncludePrimaryReplicaOnly) {
            $VMs = Get-VMReplication -ComputerName $ComputerName -ReplicationMode Primary -ErrorAction Stop
            }
        else {
            $VMs = Get-VMReplication -ComputerName $ComputerName -ErrorAction Stop
            }
        }
    catch {
        Write-Output "Hyper-V Replica Status is Unknown.|" ; exit $returnStateUnknown
        }
    if ($VMs) {
        # If we have VMs with repliation issues then we need to report their status.
        $CriticalVMs = $VMs | Where-Object -FilterScript {$_.ReplicationHealth -eq 'Critical'}
        $WarningVMs = $VMs | Where-Object -FilterScript {$_.ReplicationHealth -eq 'Warning'}
        if ($CriticalVMs -and $WarningVMs) {
            $CriticalVMsDetails = $CriticalVMs | ForEach-Object {Measure-VMReplication -VMName $_.Name -ComputerName $ComputerName}
            $WarningVMsDetails = $WarningVMs | ForEach-Object {Measure-VMReplication -VMName $_.Name -ComputerName $ComputerName}
            Write-Output "Hyper-V Replica Health is critical for $($CriticalVMsDeatails.Name) and warning for $($WarningVMsDetails.Name). $($CriticalVMsDetails.ReplicationHealthDetails) $($WarningVMsDetails.ReplicationHealthDetails) |" ; exit $returnStateCritical
            }
        elseif ($CriticalVMs) {
            $CriticalVMsDetails = $CriticalVMs | ForEach-Object {Measure-VMReplication -VMName $_.Name -ComputerName $ComputerName}
            Write-Output "Hyper-V Replica Health is critical for $($CriticalVMsDetails.Name). $($CriticalVMsDetails.ReplicationHealthDetails) |" ; exit $returnStateCritical
            }
        elseif ($WarningVMs) {
            $WarningVMsDetails = $WarningVMs | ForEach-Object {Measure-VMReplication -VMName $_.Name -ComputerName $ComputerName}
            Write-Output "Hyper-V Replica Health is warning for $($WarningVMsDetails.Name). $($WarningVMsDetails.ReplicationHealthDetails) |" ; exit $returnStateWarning
            }
        else {
            Write-Output "Hyper-V Replica Health is Normal.|" ; exit $returnStateOK
            }
        }
    else {
        # No Replication Problems Found
        Write-Output "Hyper-V Replica Health is Normal. |" ; exit $returnStateOK
        }
}
End
{
}
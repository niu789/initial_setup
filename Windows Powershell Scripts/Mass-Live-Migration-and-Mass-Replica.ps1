# Parsing arguments
 param (
	[string]$DEST_SRV = $(throw "-dest_srv is required (eg: hyper02."),
	[string]$SOURCE_SRV = $(throw "-source_srv is required (eg: hyper03."),
	[string]$LIVE_MIGRATION_LIMITS_ = $(throw "-live_migration_limits is required")
 )

echo "Please confirm the following before we initiate the mass live migration..."
write-host "=======================================================================" -foreground green
echo "Destination Server Name: $DEST_SRV"
echo "Source (and replica srv to become) Server Name: $SOURCE_SRV"
echo "Simultaneous Live Migrations: $LIVE_MIGRATION_LIMITS_"
write-host "=======================================================================" -foreground green
echo "If the above is correct, please press 'c', if not, CTRL+C to quit the script..."

while ($true) {
if ($Host.UI.RawUI.KeyAvailable -and ("c" -eq $Host.UI.RawUI.ReadKey("IncludeKeyUp,NoEcho").Character)) {
	echo "Gathering the list of replicated VMs in order to fully remove the replicated data..."
	$GetVM = Get-VMReplication -ComputerName $DEST_SRV | Get-VM

	Foreach ($vm in $GetVM)
	{
		$vmName = $vm.name
		echo ">>> VM: $vmName"
	}	

	echo "De-activating replication on both servers... starting with $DEST_SRV"
	Foreach ($vm in $GetVM)
	{
		$vmName = $vm.name
		echo ">>> Deactivating replication for $vmName on $DEST_SRV..."
		Remove-VMReplication $vmName -ComputerName $DEST_SRV
	}

	echo "De-activating replication on $SOURCE_SRV..."
	Foreach ($vm in $GetVM)
	{
		$vmName = $vm.name
		echo ">>> Deactivating replication for $vmName on $SOURCE_SRV..."
		Remove-VMReplication $vmName -ComputerName $SOURCE_SRV
	}

	echo "Removing the replicated VMs DATA..."
	Start-Sleep -milliseconds 1000
	Foreach ($vm in $GetVM)
	{
		$vmName = $vm.name
		$vmID = $vm.id
		$vm_ = $vm
		$vmComputerName = $vm.ComputerName

		echo ">>> Removing $vmName virtual disks (vhd) on $DEST_SRV..."
		$disks = Get-VHD -VMId $vmID -ComputerName $DEST_SRV
		Invoke-Command {
		 	Remove-Item $using:disks.path
		} -computername $DEST_SRV

		echo ">>> Removing $vmName meta-data from HyperV Manager on $DEST_SRV..."
		remove-vm -Name $vmName -ComputerName $DEST_SRV -Force
	}

	echo "Replicated VMs have been removed...!"
	echo "-----------------------------------------------"
	echo "Will now initiate mass live migrations..."

	Workflow Invoke-ParallelLiveMigrate
	{
		Param (
		[parameter(Mandatory=$true)][String[]] $VMList,
		[parameter(Mandatory=$true)][String] $SourceHost,
		[parameter(Mandatory=$true)][String] $DestHost,
		[parameter(Mandatory=$true)][String] $DestPath,
		[parameter(Mandatory=$true)][String] $LiveMigrationLimits
		)

		ForEach -Parallel -ThrottleLimit $LiveMigrationLimits ($VM in $VMList)
		{
			Move-VM -ComputerName $SourceHost -Name $VM -DestinationHost $DestHost -DestinationStoragePath $DestPath

			Start-Sleep -milliseconds 2000

			Enable-VMReplication -ComputerName $DestHost -VMName $VM -ReplicaServerName $SourceHost -ReplicaServerPort 8088 -AuthenticationType Kerberos -ReplicationFrequencySec 900 -RecoveryHistory 24 -CompressionEnabled 1
			Start-VMInitialReplication -ComputerName $DestHost -VMName $VM
		}
	}

	$VMList = Get-VM -ComputerName $SOURCE_SRV
	Invoke-ParallelLiveMigrate -VMList $VMList.Name -SourceHost $SOURCE_SRV -DestHost $DEST_SRV -DestPath E:\Hyper-V -LiveMigrationLimits $LIVE_MIGRATION_LIMITS_

	break;
}
}
# EMail: administrator@dataenligne.com
# Name: create_vm.ps1
# ----------------------------------------------------------------------------------------------------------------------------
# Version 1.1: Added the "Set-VMNetworkConfiguration" functionnality
# Version 1.0: Initial Release
# ----------------------------------------------------------------------------------------------------------------------------
# Script to be installed in C:\Users\Administrator\Desktop\
# This script will create a VM from a template (Windows 2012R2 STD, Ubuntu 14.04LTS x64, CentOS7 x64 with or without cPanel).
# It will also:
# - configure the VM's name;
# - set the number of RAM;
# - set the number of vCPU;
# - configure the disk size of the VM;
# - configure a NIC with either a static or a random MAC address.
# ----------------------------------------------------------------------------------------------------------------------------

# Parsing arguments
 param (
	[string]$VM_NAME = $(throw "-vm_name is required (eg: DEL-CLIENT-0000-01."),
	[int]$VM_CPUS = $(throw "-vm_cpus is required"),
	[int64]$VM_RAM = $(throw "-vm_ram is required (in GB)"),
	[ValidateScript({Test-Path $_ -PathType 'Container'})][string]$VM_DEST_PATH = "E:\Hyper-V\$VM_NAME",
	[ValidateSet("Windows","CentOS","Ubuntu","Ubuntu2","cPanel")][string]$VM_OS,
	[string]$VM_MAC = "00:00:00:00:00:00",
	[string]$VM_IP_WAN = $(throw "-vm_ip_wan is required"),
	[string]$VM_MASK_WAN = $(throw "-vm_mask_wan is required"),
	[string]$VM_GW_WAN = $(throw "-vm_gw_wan is required"),
	[ValidateSet("yes","no")][string]$VM_DOMAIN,
	[ValidateRange(10,1000)][Int64]$VM_DISK_SIZE_INT = $(throw "-vm_disk_size_int is required (in GB - must be between 50 and 1000)")
 )

# TIMER: Get Start Time
$startDTM = (Get-Date)

# Asking right away for domain's post-config credentials...
#$DOMAIN_PASS = Read-Host -Prompt "Please enter domain's user password" -AsSecureString
#$DOMAIN_PASS2 = Read-Host -Prompt "Please confirm domain's user password" -AsSecureString


# Setting default root's password to empty (we're using ssh key) to connect to linux boxes...
#$VM_CREDS = New-Object System.Management.Automation.PSCredential ("root", (new-object System.Security.SecureString))


###################################################
################ IMPORTING CMDLETs ################
###################################################
Import-Module -Name .\Set-VMNetworkConfiguration.ps1


######################################################
################ SETTING UP VARIABLES ################
######################################################
# Set WAN vSwitch name
$NETWORK_SWITCH_WAN = "Public vSwitch - VLAN 2081"
$NETWORK_SWITCH_MNGT = "Local vSwitch - VLAN 3073"

# Set Name Servers
#$NS1 = "213.186.33.99"
#$NS2 = "8.8.8.8"

# Convert the amount of RAM (Bytes) in GB
$VM_RAM = 1GB*$VM_RAM

# Converting the amount of disk space (Bytes) in GB
$VM_DISK_SIZE = $VM_DISK_SIZE_INT * 1024 * 1024 * 1024

# Setting VM hostname
$VM_HOSTNAME = $VM_NAME.toLower() + ".dataenligne.com"

# Getting and assigning the actual server's hostname (eg: hyper01)
$COMPUTER_NAME = [System.Net.Dns]::GetHostName()

# Setup VM hdd paths
$VM_ROOT_VHD = "${VM_DEST_PATH}/${VM_NAME}.vhdx"


##############################################
################ OS SELECTION ################
##############################################
# OS selection
switch ($VM_OS)
	{
		Windows { 
			$ROOT_VHD_TPL = "E:\VMs Templates\Windows\Windows 2012 R2 STD - Vanilla\Windows 2012 R2 STD - Template (GEN2)\Virtual Hard Disks\Windows2012R2_STD.vhdx" 
			$VM_OS_VER = "Windows 2012 R2 Standard"
			echo "Windows 2012 R2 Standard edition selected! Creating VM..."

			$VM = New-VM -Name $VM_NAME.ToUpper() -Path $VM_DEST_PATH -MemoryStartupBytes $VM_RAM -ComputerName $COMPUTER_NAME -Generation 2
			# Copying the template disk and attaching it to the VM...
			echo "Copying disk template ($VM_OS) and attaching it to the VM ($VM_NAME)..."
			Convert-VHD -Path $ROOT_VHD_TPL -DestinationPath $VM_ROOT_VHD
			Add-VMHardDiskDrive -VM $VM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VM_ROOT_VHD			
		}

		CentOS {
#			$ROOT_PASS = Read-Host -Prompt "Please enter desired root's password: " -AsSecureString
			$ROOT_VHD_TPL = "E:\VMs Templates\Linux\CentOS 7 - Vanille avec HyperV Modules\CentOS 7 x64 - Template (GEN2)\Virtual Hard Disks\CentOS 7 x64 - Template (GEN2).vhdx"
			$VM_OS_VER = "CentOS 7"
			echo "CentOS 7 (Generation 2) selected! Creating VM..."
			
			$VM = New-VM -Name $VM_NAME.ToUpper() -Path $VM_DEST_PATH -MemoryStartupBytes $VM_RAM -ComputerName $COMPUTER_NAME -Generation 2
			Set-VMFirmware $VM_NAME -EnableSecureBoot Off

			# Copying the template disk and attaching it to the VM...
			echo "Copying disk template ($VM_OS) and attaching it to the VM ($VM_NAME)..."
			Convert-VHD -Path $ROOT_VHD_TPL -DestinationPath $VM_ROOT_VHD –BlockSizeBytes 1MB -VHDType Dynamic
			Add-VMHardDiskDrive -VM $VM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VM_ROOT_VHD
		}

		cPanel {
#			$ROOT_PASS = Read-Host -Prompt "Please enter desired root's password: " -AsSecureString

			$SFTP_USER  = Read-Host -Prompt "Please enter cPanel sFTP username: "
			$SFTP_PASS  = Read-Host -Prompt "Please enter cPanel sFTP password: " -AsSecureString
			#convert the SecureString object to plain text using PtrToString and SecureStringToBSTR
			$BSFTP_PASS = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SFTP_PASS)
			$SFTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSFTP_PASS) #$Pwd now has the secure-string contents in plain text
			[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSFTP_PASS) #this is an important step to keep things secure

			$ROOT_VHD_TPL = "E:\VMs Templates\Linux\CentOS 7 - Vanille avec HyperV Modules\CentOS 7 x64 - Template (GEN2)\Virtual Hard Disks\CentOS 7 x64 - Template (GEN2).vhdx"
			$VM_OS_VER = "CentOS 7 with cPanel"
			echo "CentOS 7 (Generation 2) + cPanel selected! Creating VM..."
			
			$VM = New-VM -Name $VM_NAME.ToUpper() -Path $VM_DEST_PATH -MemoryStartupBytes $VM_RAM -ComputerName $COMPUTER_NAME -Generation 2
			Set-VMFirmware $VM_NAME -EnableSecureBoot Off

			# Copying the template disk and attaching it to the VM...
			echo "Copying disk template ($VM_OS) and attaching it to the VM ($VM_NAME)..."
			Convert-VHD -Path $ROOT_VHD_TPL -DestinationPath $VM_ROOT_VHD –BlockSizeBytes 1MB -VHDType Dynamic
			Add-VMHardDiskDrive -VM $VM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VM_ROOT_VHD
		}

		Ubuntu {
#			$ROOT_PASS = Read-Host -Prompt "Please enter desired new root's password: "
			$ROOT_VHD_TPL = "E:\VMs Templates\Linux\Ubuntu 14.04 LTS - Vanille avec HyperV Modules\Ubuntu 14.04 LTS x64 - Template (GEN2)\Virtual Hard Disks\Ubuntu 14.04 LTS x64 - Template (GEN2).vhdx" 
			$VM_OS_VER = "Ubuntu 14.04 LTS"
			echo "Ubuntu 14.04 LTS (Generation 2) selected! Creating VM..."
			
			$VM = New-VM -Name $VM_NAME.ToUpper() -Path $VM_DEST_PATH -MemoryStartupBytes $VM_RAM -ComputerName $COMPUTER_NAME -Generation 2
			Set-VMFirmware $VM_NAME -EnableSecureBoot Off

			# Copying the template disk and attaching it to the VM...
			echo "Copying disk template ($VM_OS) and attaching it to the VM ($VM_NAME)..."
			Convert-VHD -Path $ROOT_VHD_TPL -DestinationPath $VM_ROOT_VHD –BlockSizeBytes 1MB -VHDType Dynamic
			Add-VMHardDiskDrive -VM $VM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VM_ROOT_VHD			
		}
		default {"NADA!"}
	}



#############################################
################ VM CREATION ################
#############################################
# Configure the amount of CPU
echo "Configuring CPUs..."
Set-VMProcessor -VM $VM -Count $VM_CPUS

# Resizing disk size of the VM
echo "Resizing VM disk to $VM_DISK_SIZE (bytes)..."
Resize-VHD –Path $VM_ROOT_VHD –SizeBytes $VM_DISK_SIZE

#############################################################################################
################ NETWORKING CONFIGURATION - PART 1 - MAC ADDRESS ASSIGNATION ################
#############################################################################################
Remove-VMNetworkAdapter -VM $VM

##################################################################
##### MAC ADDRESS GENERATION AND ASSIGNATION - WAN INTERFACE #####
##################################################################
# MAC address generation - Get the current available MAC address and assign it to the VM
$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Worker'
$CurrentAddress = Get-ItemProperty -Path $Path -Name CurrentMacAddress
$VM_MAC = [System.BitConverter]::ToString($CurrentAddress.CurrentMacAddress)
$VM_MAC_STRING = $VM_MAC -replace "-", ""

echo "Starting VM to initialize the static WAN Interface MAC address..."
Add-VMNetworkAdapter -VM $VM -Name WAN -SwitchName $NETWORK_SWITCH_WAN
Start-VM $VM_NAME

do {Start-Sleep -milliseconds 20000}
    until ((Get-VMIntegrationService $VM_NAME | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

echo "Stopping the VM and configuring the static WAN Interface MAC address..."
Stop-VM $VM_NAME
Start-Sleep -milliseconds 20000
Get-VM -name $VM_NAME | Get-VMNetworkAdapter | Set-VMNetworkAdapter -StaticMacAddress $VM_MAC_STRING

############################################################################################
################ NETWORKING CONFIGURATION - IP ADDRESS ASSIGNATION ################
############################################################################################

echo "Starting VM and waiting for a heartbeat..."
Start-VM $VM_NAME
do {Start-Sleep -milliseconds 20000}
    until ((Get-VMIntegrationService $VM_NAME | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

echo "Heartbeat received, configuring network!"
$vmName = "$VM_NAME" 
                              $Msvm_VirtualSystemManagementService = Get-WmiObject -Namespace root\virtualization\v2 `
                                  -Class Msvm_VirtualSystemManagementService 
                              
                              $Msvm_ComputerSystem = Get-WmiObject -Namespace root\virtualization\v2 `
                                  -Class Msvm_ComputerSystem -Filter "ElementName='$vmName'" 
                              
                              $Msvm_VirtualSystemSettingData = ($Msvm_ComputerSystem.GetRelated("Msvm_VirtualSystemSettingData", `
                                  "Msvm_SettingsDefineState", $null, $null, "SettingData", "ManagedElement", $false, $null) | % {$_})
                              
                              $Msvm_SyntheticEthernetPortSettingData = $Msvm_VirtualSystemSettingData.GetRelated("Msvm_SyntheticEthernetPortSettingData")
                              
                              $Msvm_GuestNetworkAdapterConfiguration = ($Msvm_SyntheticEthernetPortSettingData.GetRelated( `
                                  "Msvm_GuestNetworkAdapterConfiguration", "Msvm_SettingDataComponent", `
                                  $null, $null, "PartComponent", "GroupComponent", $false, $null) | % {$_})
                              
                              $Msvm_GuestNetworkAdapterConfiguration.DHCPEnabled = $false
                              $Msvm_GuestNetworkAdapterConfiguration.IPAddresses = @("$VM_IP_WAN")
                              $Msvm_GuestNetworkAdapterConfiguration.Subnets = @("$VM_MASK_WAN")
                              $Msvm_GuestNetworkAdapterConfiguration.DefaultGateways = @("$VM_GW_WAN")
                              ###$Msvm_GuestNetworkAdapterConfiguration.DNSServers = @("8.8.8.8")
                              
                              $Msvm_VirtualSystemManagementService.SetGuestNetworkAdapterConfiguration( `
                              $Msvm_ComputerSystem.Path, $Msvm_GuestNetworkAdapterConfiguration.GetText(1))

Start-Sleep -milliseconds 10000
echo "Stopping the VM and generating the static Management Interface MAC address..."
Stop-VM $VM_NAME
Start-Sleep -milliseconds 20000

################################
##### MAC - MNGT INTERFACE #####
################################
# MAC address generation - Get the current available MAC address and assign it to the VM
$Path_MNGT = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Worker'
$CurrentAddress_MNGT = Get-ItemProperty -Path $Path_MNGT -Name CurrentMacAddress
$VM_MAC_MNGT = [System.BitConverter]::ToString($CurrentAddress_MNGT.CurrentMacAddress)
$VM_MAC_STRING_MNGT = $VM_MAC_MNGT -replace "-", ""

echo "Starting VM to initialize the static Management Interface MAC address..."
Add-VMNetworkAdapter -VM $VM -Name MNGT -SwitchName $NETWORK_SWITCH_MNGT
Start-VM $VM_NAME

do {Start-Sleep -milliseconds 20000}
    until ((Get-VMIntegrationService $VM_NAME | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

echo "Stopping the VM and configuring the static Management Interface MAC address..."
Stop-VM $VM_NAME
Start-Sleep -milliseconds 20000
Get-VM -name $VM_NAME | Get-VMNetworkAdapter -Name MNGT | Set-VMNetworkAdapter -StaticMacAddress $VM_MAC_STRING_MNGT


##########################
##### Starting VM... #####
##########################
echo "Starting VM and waiting for a heartbeat..."
Start-VM $VM_NAME
do {Start-Sleep -milliseconds 20000}
    until ((Get-VMIntegrationService $VM_NAME | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

echo "Heartbeat received, VM ready for use!"

############################################################################
##################### INSTALLING CPANEL IF OS = CPANEL #####################
################ AND JOINING VM TO THE DOMAIN IF REQUESTED #################
############################################################################
switch ($VM_OS)
	{
		cPanel {
			echo "Connecting to the cPanel VM through SSH..."
			New-SSHSession -Computer $VM_IP_WAN -Port 22332 -AcceptKey -Credential $VM_CREDS -Force -KeyFile "C:\Users\administrator\Documents\ssh-key"

			echo "Establishing ssh session stream..."
			$stream = New-SSHShellStream -Index 0
			Start-Sleep -s 5
			$stream.Read()

			If ($VM_DOMAIN -like "yes") {
				echo "Executing post-configuration script..."
#				Invoke-SSHStreamExpectSecureAction -ShellStream $stream -Command "/root/initial_setup/CentOS7/initial_setup_centos7.sh $VM_HOSTNAME domain cpanel 2>&1 | tee -a initial_setup.log" -ExpectString "password:" -SecureAction $DOMAIN_PASS -Timeout 10000
				Start-Sleep -s 20
				$stream.Read()
				} 
				else
					{
						echo "Executing post-configuration script. VM will NOT be joined to dataenligne's domain..."
						Invoke-SSHCommand -Index 0 -Command "/root/initial_setup/CentOS7/initial_setup_centos7.sh $VM_HOSTNAME cpanel 2>&1 | tee -a initial_setup.log"
						Start-Sleep -s 20
						$stream.Read()
					}
		}


	}

#####################################################
################ VM CREATION SUMMARY ################
#####################################################

# Converting RAM and DISK Bytes number to GBytes
$VM_RAM_GB = $VM_RAM/1024/1024/1024
$VM_DISK_SIZE = $VM_DISK_SIZE/1024/1024/1024
$VM_NAME = $VM_NAME.toUpper()

# TIMER: Get End Time
$endDTM = (Get-Date)
"Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"

$VM_MAC_STRING2 = $VM_MAC -replace "-", ":"
$VM_MAC_MNGT_STRING2 = $VM_MAC_MNGT -replace "-", ":"


Write-Host "Exiting now, closing SSH session..."
Remove-SSHSession -Index 0


Write-Host "Exiting now, closing SSH session with monitoring server..."
Remove-SSHSession -Index 0

# Rebooting the VM to finalize the installation...
Write-Host "Rebooting the VM to finalize the installation..."
Stop-VM $VM_NAME
Start-Sleep -milliseconds 20000
Start-VM $VM_NAME
do {Start-Sleep -milliseconds 20000}
    until ((Get-VMIntegrationService $VM_NAME | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")



# VM Creation Summary
echo "VM Creation completed !"
echo "---------------------------"
echo "VM Name: $VM_NAME"
echo "VM Hostname: $VM_HOSTNAME"
echo "CPU: $VM_CPUS"
echo "RAM (GB): $VM_RAM_GB"
echo "DISK SIZE (GB): $VM_DISK_SIZE"
echo "OS: $VM_OS_VER"
echo "WAN MAC: $VM_MAC_STRING2"
echo "WAN IP: $VM_IP_WAN"
echo "WAN NETMASK: $VM_MASK_WAN"
echo "WAN GATEWAY: $VM_GW_WAN"
echo "MNGT MAC: $VM_MAC_MNGT_STRING2"
If ($VM_DOMAIN -like "yes") {
	echo "DOMAIN: Yes! VM should be joined to dataenligne's domain."
}
If ($VM_OS -like "cPanel") {
	echo "ADDON: cPanel"
	Write-Host "Make sure to finish setting up cpanel by logging into WHM @ http://$VM_IP_WAN/whm" -Background DarkRed
}
echo "---------------------------"

If ($VM_OS -like "Windows") {
	echo "To finalize the configuration on this VM, please run the following:"
	echo "cmd.exe -> Administrator\Desktop\initial_setup.ps1"
}

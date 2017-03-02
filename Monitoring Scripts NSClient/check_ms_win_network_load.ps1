# Script name:   	check_ms_win_network_load.ps1
# Version:			0.15.03.31
# Created on:    	25/10/2014
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows network load for the active adapter.
# On Github:		https://github.com/willemdh/check_ms_win_network_load
# On OutsideIT:		http://outsideit.net/check-ms-win-network-load
# Recent History:       	
#	28/10/2014 => Added perfdata, NeworkStruct
#	10/03/2015 => Testing, rework
#	11/03/2015 => Support for teamed network cards, error handling
#   30/03/2015 => Small change in query for used team member
#	31/03/2015 => Added support for Intel[R] PRO/1000 MT Network Connection and failover cluster where detected ip was always apipa
#
#
# Modified by DATAenligne:
#	15/07/2015 => Modified the script so that Interface Name could be specified as an argument and throughput results modified to be shown as in Mbps
#
#
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published
#	by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program is distributed 
#	in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
#	PARTICULAR PURPOSE. See the GNU General Public License for more details. You should have received a copy of the GNU General Public 
#	License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0
	
$NetworkStruct = New-Object PSObject -Property @{
    Hostname = [string]'localhost';
	ActiveIp = (((ipconfig.exe | findstr.exe [0-9].\.)[0]).Split()[-1])
	Adapter = [string]'';
    ExitCode = [int]3;
	LinkWarn = [int]0;
	LinkCrit = [int]0;
	Timer = [int]10;
    OutputString = [string]'UNKNOWN: Error processing, no data returned.';
	EnabledNetAdapters = @()
}

#region Functions

Function Initialize-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args
    )	
    try {
        For ( $i = 0; $i -lt $Args.count; $i++ ) { 
		    $CurrentArg = $Args[$i].ToString()
            if ($i -lt $Args.Count-1) {
				$Value = $Args[$i+1];
				If ($Value.Count -ge 2) {
					foreach ($Item in $Value) {
						Test-Strings $Item | Out-Null
					}
				}
				else {
	                $Value = $Args[$i+1];
					Test-Strings $Value | Out-Null
				}	                             
            } else {
                $Value = ''
            };

            switch -regex -casesensitive ($CurrentArg) {
                "^(-H|--Hostname)$" {
					if ($Value -ne ([System.Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower() -and $Value -ne 'localhost') {
						& ping.exe -n 1 $Value | out-null
						if($? -eq $true) {
							$NetworkStruct.Hostname = $Value
							$i++
		    			} 
						else {
		    				Write-Host "CRITICAL: Ping to $Value failed! Please provide valid reachable hostname!"
							exit 3
		    			}
					}
					else {
						$NetworkStruct.Hostname = $Value
						$i++
					}
						
                }
				"^(-I|--IPAddress)$" {
                    $NetworkStruct.ActiveIp = $value
                    $i++					
                }    
				"^(-a|--Adapter)$" {
                    $NetworkStruct.Adapter = $value
                    $i++					
                }                          
				"^(-t|--Timer)$" {
	                if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $NetworkStruct.Timer = $value
                    } 
					else {
                        throw "Critical treshold should be numeric and less than 100. Value given is $value"
                    }
                    $i++					
                }
                "^(-lw|--LinkWarn)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $NetworkStruct.LinkWarn = $value
                    } else {
                        throw "Link warning treshold should be numeric and less than 100. Value given is $value"
                    }
                    $i++
                }
                "^(-lc|--LinkCrit)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                         $NetworkStruct.LinkCrit = $value
                    } else {
                        throw "Link critical treshold should be numeric and less than 100. Value given is $value"
                    }
                    $i++
                 }
                "^(-h|--Help)$" {
                    Write-Help
                }
                default {
                    throw "Illegal arguments detected: $_"
                 }
            }
        }
    } catch {
		Write-Host "UNKNOWN: $_"
        Exit $NetworkStruct.ExitCode
	}	
}	

Function Test-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    # `, `n, |, ; are bad, I think we can leave {}, @, and $ at this point.
    $BadChars=@("``", "|", ";", "`n")
    $BadChars | ForEach-Object {
        If ( $String.Contains("$_") ) {
            Write-Host 'Unknown: String contains illegal characters.'
            Exit $NetStruct.ExitCode
        }
    }
    Return $true
} 

Function Write-Help {
	Write-Host @"
check_ms_win_network_load.ps1:`n`tThis script is designed to monitor Microsoft Windows network load.
Arguments:
    -H  | --Hostname     => Optional hostname of remote system, default is localhost, not yet tested on remote host.
    -I  | --IPAddress    => Ip Address of the system
    -a  | --Adapter      => Adapter to gather load from (eg: Intel[R] I350 Gigabit Network Connection)
    -lw | --LinkWarn     => Warning threshold for total link utilisation, not yet implemented.
    -lc | --LinkCrit     => Critical threshold for total link utilisation, not yet implemented.
    -t  | --Timer        => Amount of seconds to gather data.
    -h  | --Help         => Print this help output.
"@
    Exit $TaskStruct.ExitCode;
} 

Function Get-NetworkLoad {
	$StartTime = get-date
	$EndTime   = $StartTime.addSeconds($NetworkStruct.Timer)
	$TimeSpan = New-Timespan $StartTime $EndTime
	$TimeCount = 0
	$AvgLinkUtilTotalValues = @()
	$AvgTotalBytesPerSecValues = @()
	$AvgLinkUtilReceivedValues = @()
	$AvgReceivedBytesPerSecValues = @()
	$AvgLinkUtilSentValues = @()
	$AvgSentBytesPerSecValues = @()

	#####Write-Host $NetworkStruct.Adapter
	#####$NetworkStruct.Adapter = "Intel[R] I350 Gigabit Network Connection"

	$ActiveAdapter = Get-WmiObject -class Win32_PerfFormattedData_Tcpip_NetworkInterface |where Name -eq $NetworkStruct.Adapter | Select-Object Name

try {      
	while ($TimeSpan -gt 0) 
	{
	 $TimeSpan = New-Timespan $(Get-Date) $EndTime
	 $AdapterBandwithBytes = Get-WmiObject -class Win32_PerfFormattedData_Tcpip_NetworkInterface |where Name -eq $NetworkStruct.Adapter | Select-Object CurrentBandwidth
	 $CurrentBytesPerSec = Get-WmiObject -class Win32_PerfFormattedData_Tcpip_NetworkInterface |where Name -eq $NetworkStruct.Adapter | Select-Object BytesTotalPersec, BytesReceivedPersec, BytesSentPersec

	 [float]$LinkUtilTotal = ($CurrentBytesPerSec.BytesTotalPerSec / $AdapterBandwithBytes.CurrentBandwidth) * 100 * 8
	 $AvgLinkUtilTotalValues += $LinkUtilTotal

	 # Converting values in Mbps
	 $AvgTotalBytesPerSecValues += ($CurrentBytesPerSec.BytesTotalPerSec / 1024 / 1024) * 8
	 $AvgReceivedBytesPerSecValues += ($CurrentBytesPerSec.BytesReceivedPerSec / 1024 / 1024) * 8
	 $AvgSentBytesPerSecValues += ($CurrentBytesPerSec.BytesSentPerSec / 1024 / 1024) * 8
	 $TimeCount++ 
	}
}
catch {
     Write-Host "UNKNOWN: Problem detected while querying performance data of adapter $AdapterCleanName. Plugin has probably issues detecting the active adapter. Please debug."
     Exit $TaskStruct.ExitCode
}

	$AvgBandwithTotal = '{0:N5}' -f (($AvgLinkUtilTotalValues | Measure-Object -Average).average)

	$AvgTotalBytesPerSec = (($AvgTotalBytesPerSecValues | Measure-Object -Average).average)
	$AvgReceivedBytesPerSec = (($AvgReceivedBytesPerSecValues | Measure-Object -Average).average)
	$AvgSentBytesPerSec = (($AvgSentBytesPerSecValues | Measure-Object -Average).average)

	$OutputOkString = "OK: Adapter: $($ActiveAdapter.Name) - Avg of $($NetworkStruct.Timer) seconds - Total Link Utilisation: $AvgBandwithTotal%"
	$OutputPerfdata = " | TotalRxTx=$AvgTotalBytesPerSec" + "Mb/s" +", Rx=$AvgReceivedBytesPerSec" + "Mb/s" +", Tx=$AvgSentBytesPerSec" + "Mb/s"
	
	$NetworkStruct.OutputString = $OutputOkString + $OutputPerfdata
	$NetworkStruct.ExitCode = 0
}

#endregion

# Main function 
if($Args.count -ge 1){Initialize-Args $Args}

if ($NetworkStruct.Hostname -eq 'localhost') {
	$NetworkStruct.Hostname = ([System.Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower()
}

Get-NetworkLoad -NetworkStruct $NetworkStruct

Write-Host $NetworkStruct.OutputString

Exit $NetworkStruct.ExitCode
function GetHddSmart
{
	function ConvertTo-Hex ( $DEC ) {
		'{0:x2}' -f [int]$DEC
	}
	function ConvertTo-Dec ( $HEX ) {
		[Convert]::ToInt32( $HEX, 16 )
	}
	function Get-AttributeDescription ( $Value ) {
		switch ($Value) {
			'01' { 'Raw Read Error Rate' }
			'02' { 'Throughput Performance' }
			'03' { 'Spin-Up Time' }
			'04' { 'Number of Spin-Up Times (Start/Stop Count)' }
			'05' { 'Reallocated Sector Count' }
			'07' { 'Seek Error Rate' }
			'08' { 'Seek Time Performance' }
			'09' { 'Power On Hours Count (Power-on Time)' }
			'0a' { 'Spin Retry Count' }
			'0b' { 'Calibration Retry Count (Recalibration Retries)' }
			'0c' { 'Power Cycle Count' }
			'aa' { 'Available Reserved Space' }
			'ab' { 'Program Fail Count' }
			'ac' { 'Erase Fail Count' }
			'ae' { 'Unexpected power loss count' }
			'b7' { 'SATA Downshift Error Count' }
			'b8' { 'End-to-End Error' }
            'bb' { 'Reported Uncorrected Sector Count (UNC Error)' }
			'bc' { 'Command Timeout' }
			'bd' { 'High Fly Writes' }
			'be' { 'Airflow Temperature' }
			'bf' { 'G-Sensor Shock Count (Mechanical Shock)' }
			'c0' { 'Power Off Retract Count (Emergency Retry Count)' }
			'c1' { 'Load/Unload Cycle Count' }
			'c2' { 'Temperature' }
			'c3' { 'Hardware ECC Recovered' }
			'c4' { 'Reallocated Event Count' }
			'c5' { 'Current Pending Sector Count' }
			'c6' { 'Offline Uncorrectable Sector Count (Uncorrectable Sector Count)' }
			'c7' { 'UltraDMA CRC Error Count' }
			'c8' { 'Write Error Rate (MultiZone Error Rate)' }
			'c9' { 'Soft Read Error Rate' }
			'cb' { 'Run Out Cancel' }
			'c�' { 'Data Address Mark Error' }
			'dc' { 'Disk Shift' }
			'e1' { 'Load/Unload Cycle Count' }
			'e2' { 'Load ''In''-time' }
			'e3' { 'Torque Amplification Count' }
			'e4' { 'Power-Off Retract Cycle' }
			'e8' { 'Endurance Remaining' }
			'e9' { 'Media Wearout Indicator' }
			'f0' { 'Head Flying Hours' }
			'f1' { 'Total LBAs Written' }
			'f2' { 'Total LBAs Read' }
			'f9' { 'NAND Writes (1GiB)' }
			'fe' { 'Free Fall Protection' }
			default { $Value }
		}
	}

$PnpDev=@{}
$hdddev=$Win32_DiskDrive | Select-Object Model,Size,MediaType,InterfaceType,FirmwareRevision,SerialNumber,PNPDeviceID
$hdddev | foreach {
    $PnpDev.Add($($_.pnpdeviceid -replace "\\","\\"),$_)
}

$PnpDev.Keys | foreach {
    $PnpDevid=$_
    $TmpFailData=$MSStorageDriver_FailurePredictData | Where-Object  {$_.InstanceName -Match $PnpDevid}
    $TmpFailStat=$MSStorageDriver_FailurePredictStatus | Where-Object  {$_.InstanceName -Match $PnpDevid}
    if ($TmpFailStat)
    {
        $PnpDev[$PnpDevid] | Add-Member -MemberType NoteProperty -Name  PredictFailure -Value $TmpFailStat.PredictFailure
    }
    else
    {
        $PnpDev[$PnpDevid] | Add-Member -MemberType NoteProperty -Name  PredictFailure -Value 'Not supported'
    }
    if ($TmpFailData)
    {
        $Disk=$TmpFailData
        $i = 0
        #$Report = @()
        $pByte = $null
		        foreach ( $Byte in $Disk.VendorSpecific ) {
			        $i++
			        if (( $i - 3 ) % 12 -eq 0 ) 
                    {
				        if ( $Byte -eq 0) { break }
				        $Attribute = '{0:x2}' -f [int]$Byte
			        } 
                    else 
                    {
				        $post = ConvertTo-Hex $pByte
				        $pref = ConvertTo-Hex $Byte
				        $Value = ConvertTo-Dec "$pref$post"
				        if (( $i - 3 ) % 12 -eq 6 ) 
                        {
					        if ( $Attribute -eq '09' ) { [int]$Value = $Value / 24 }
				            $PnpDev[$PnpDevid] | Add-Member -MemberType NoteProperty -Name $( Get-AttributeDescription $Attribute) -Value $Value
                        }
			        }
			        $pByte = $Byte
                }
        
    }
    else
    {
        $PnpDev[$PnpDevid] | Add-Member -MemberType NoteProperty -Name SmartStatus -Value 'Not supported' 
    }
    $HddSmart=$PnpDev[$PnpDevid]
    $WarningThreshold=@{
    "Temperature"=46,54
    "Reallocated Sector Count"=1,10
    }
    $CriticalThreshold=@{
    "Temperature"=55
    "Reallocated Sector Count"=11
    }
        $HddWarning=$False
        $HddCritical=$False
        $HddSmart | Get-Member | foreach {
            $Property=$_.name
            if ($WarningThreshold[$Property])
            {
                $MinWarningThreshold=$WarningThreshold[$Property][0]
                $MaxWarningThreshold=$WarningThreshold[$Property][1]
                    if ($HddSmart.$Property -le $MaxWarningThreshold -and $HddSmart.$Property -ge $MinWarningThreshold)
                    {
                        $HddWarning=$true
                    }
            }
            

            if ($CriticalThreshold[$Property])
            {
                $MinCriticalThreshold=$CriticalThreshold[$Property]
                    if($HddSmart.$Property -ge $MinCriticalThreshold)
                    {
                        $HddCritical=$true
                    } 
            }
              
            
        #End Foreach
        }
    if ($HddSmart.smartstatus -ne "Not supported")
    {
        if ($HddWarning)
        {
            $HddSmart | Add-Member -MemberType NoteProperty -Name SmartStatus -Value 'Warning' 
        }
        elseif($HddCritical -or $HddSmart.PredictFailure)
        {
            $HddSmart | Add-Member -MemberType NoteProperty -Name SmartStatus -Value 'Critical'   
        }
        else
        {
            $HddSmart | Add-Member -MemberType NoteProperty -Name SmartStatus -Value 'Ok'   
        }
    }
$HddSmart
#End Foreach
}
}
# Author: Chris Harrod
# Purpose: Find permanent WMI event consumers on endpoints that could be used by APT actors.

$ResultsDir = "C:\Temp"

if($arrComputers -eq $Null){
    #change this if you want to hit servers
    $arrComputers = Get-ADComputer -Properties Name, OperatingSystem -Filter {OperatingSystem -NOTLIKE "Windows Server*"}
}
$arrSelection = $arrComputers | Sort-Object {Get-Random} #|  select-object -Last 50
$i = $arrSelection.count
foreach ($Computer in $arrSelection){
    Write-Host $i
    $i--
    $Computer = $Computer.Name
        $ResultsPath = "$ResultsDir\$Computer.txt"
        #Write-Host $ResultsPath
        $MaxThreads = 30
        While(@(Get-Job | Where {$_.State -eq "Running"}).Count -ge $MaxThreads){
            Write-Host "Waiting for open thread .. ($MaxThreads Maximum) "
            Start-Sleep 1
            $JobsCompleted = Get-Job | Where {$_.State -eq "Completed"}
            if($JobsCompleted.count -gt 0){
                Write-Host Cleaning up $JobsCompleted.count completed job
                $JobsCompleted | Remove-Job
            }
        }
        $ScriptBlock = {
            Param(
                [string]$Computer,
                [string]$ResultsPath
            )

            if(Test-Connection -ComputerName $Computer -Count 1 -quiet){
                try{
                    $WMIFault = $False
                    Get-WmiObject __EventFilter -ComputerName $Computer -namespace root\subscription -ErrorAction Stop | out-null
                }
                catch {
                    $WMIFault = $True
                }

                if($WMIFault -eq $False){
                    #Write-Host Testing $Computer
                    $Filters = Get-WmiObject __EventFilter -ComputerName $Computer -namespace root\subscription | Where-Object {$_.name -NotMatch "BVTFilter" -and $_.name -notmatch "SCM Event Log Filter"}
                    $Consumers = Get-WmiObject __EventConsumer -ComputerName $Computer -namespace root\subscription | Where-Object {$_.name -NotMatch "BVTConsumer" -and $_.name -notmatch "SCM Event Log Cdonsumer"}
                    $Bindings = Get-WmiObject __FilterToConsumerBinding -ComputerName $Computer  -Namespace root\subscription | Where-Object {$_.Filter -NotMatch "SCM Event Log Filter" -and $_.Filter -notmatch "BVTFilter"}
                        if ($Filters -ne $Null){
                            Add-Content $ResultsPath $Filters
                        }
                        if ($Consumers -ne $Null){
                            Add-Content $ResultsPath $Consumers
                        }
                        #if ($CommandLines -ne $Null){
                        #    Add-Content $ResultsPath $CommandLines
                        #}
                        if ($Bindings -ne $Null){
                            Add-Content $ResultsPath $Bindings
                        }

                    $Filters = $Null
                    $Consumers = $Null
                    $CommandLines = $Null
                    $Bindings = $Null
                }
            }
        }
    Start-Job -ScriptBlock $ScriptBlock -ArgumentList "$Computer",$ResultsPath
    $ResultsPath = $Null
}
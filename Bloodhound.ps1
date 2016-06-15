# Author: Chris Harrod
# Purpose: Find permanent WMI event consumers on endpoints that could be used by APT actors.
# Updated: 6/15/16

$ResultsPath = "C:\temp\Results\Bloodhound"

if($arrComputers -eq $Null){
    $arrComputers = Get-ADComputer -Properties Name, OperatingSystem -Filter *
}

$arrSelection = $arrComputers | Sort-Object {Get-Random} #|  select-object -Last 2000

$MaxThreads = 3
$RunspacePool = [RunspaceFactory ]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()
$RunspaceCollection = New-Object system.collections.arraylist

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
            $Filters = Get-WmiObject __EventFilter -ComputerName $Computer -namespace root\subscription | Where-Object {$_.name -NotMatch "BVTFilter" -and $_.name -notmatch "SCM Event Log Filter"}
            $Consumers = Get-WmiObject __EventConsumer -ComputerName $Computer -namespace root\subscription | Where-Object {$_.name -NotMatch "BVTConsumer" -and $_.name -notmatch "SCM Event Log Consumer"}
            $Bindings = Get-WmiObject __FilterToConsumerBinding -ComputerName $Computer  -Namespace root\subscription | Where-Object {$_.Filter -NotMatch "SCM Event Log Filter" -and $_.Filter -notmatch "BVTFilter"}
            if ($Filters -ne $Null){
                Add-Content "$ResultsPath\$Computer.csv" $Filters
            }
            if ($Consumers -ne $Null){
                foreach($Consumer in $Consumers){
                    if($Consumer.__CLASS -eq "CommandLineEventConsumer"){
                        $Name = "Name: " + $Consumer.Name
                        $CommandLineTemplate = "CommandLine: " + $Consumer.CommandLineTemplate
                        Add-Content "$ResultsPath\$Computer.csv" $Name
                        Add-Content "$ResultsPath\$Computer.csv" $CommandLineTemplate
                    }
                    else{
                        Add-Content "$ResultsPath\$Computer.csv" $Consumer
                    }
                }
                Add-Content "$ResultsPath\$Computer.csv" $Consumers
            }
            if ($Bindings -ne $Null){
                Add-Content "$ResultsPath\$Computer.csv" $Bindings
            }

            $Filters = $Null
            $Consumers = $Null
            $Bindings = $Null
            $Name = $Null
            $CommandLineTemplate = $Null
        }
    }
}

foreach($Computer in $arrSelection){
    if($Computer.Name){
        $Computer = $Computer.Name
    }
    if(!(Test-Path $ResultsPath\$Computer.csv)){
        $Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($Computer).AddArgument($ResultsPath)
        $Powershell.RunspacePool = $RunspacePool
        $RunSpace = New-Object -TypeName PSObject -Property @{
            Runspace = $PowerShell.BeginInvoke()
            PowerShell = $PowerShell
        }
        $RunspaceCollection.Add($RunSpace) | Out-Null
    }
    [System.GC]::Collect()
}

While($RunspaceCollection){
    Foreach($Runspace in $RunspaceCollection.ToArray()){
    #Write-Host $Runspace.Runspace.IsCompleted
        If($Runspace.Runspace.IsCompleted){
            $Runspace.PowerShell.EndInvoke($Runspace.Runspace)
            $Runspace.PowerShell.Dispose()
            $RunspaceCollection.Remove($Runspace)
        }
    }
}

$RunspacePool = $Null
$RunspaceCollection = $Null
$RunSpace = $Null
$Powershell = $Null

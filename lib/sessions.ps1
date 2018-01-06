function Get-PoCSessions {
    [CmdletBinding()]
    param ( 
        [string[]]$NeededHosts=@('DC','CA','ADFS','RDS','WAP'),
        [string]$UserName="Administrator"
        )
    
    if($PSBoundParameters['Debug']){
        $DebugPreference = 'Continue'
    }

    $sessions = Get-PSSession | ? State -ne 'Broken'
    $result = @{  }

    $hosts = @{
        DC = "10.0.0.10"
        CA = "10.0.0.20"
        ADFS = "10.0.0.30"
        RDS = "10.0.0.40"
        WAP = "10.10.10.10"
    }

    $hosts.GetEnumerator() | % {
        $sessionName = "$($UserName)@$($_.Value)"
        "check session for $sessionName" | Write-Debug
        $pss = $sessions | ? Name -eq $sessionName | select -Last 1
        if((-not $pss) -and ($_.Key -in $NeededHosts)){
            "open new session for $sessionName" | Write-Verbose
            if((-not $cred)) { $cred = (Get-Credential -UserName $UserName -Message "Credentials for '$UserName'") }
            $pss = New-PSSession -Name $sessionName -ComputerName $_.Value -Credential $cred
            "add new session for $sessionName to result" | Write-Debug
        } elseif($pss) {
            "add existing session for $sessionName to result" | Write-Debug
        } else {
            "ignore session for $sessionName because it is not needed" | Write-Debug
        }

        if($pss){
            $result.Add($_.Key, $pss)
        }
    }

    return $result
}



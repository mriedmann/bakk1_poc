. "$PSScriptRoot\..\lib\sessions.ps1"

$domainSessions = Get-PoCSessions -NeededHosts RDS, ADFS -UserName "SECLAB\Administrator"
$localSessions = Get-PoCSessions -NeededHosts WAP,DC
$pssAdfs = $domainSessions['ADFS']
$pssWap = $localSessions['WAP']
$pssDc = $localSessions['DC']
$pssRds = $domainSessions['RDS']

###### Configure RDS
Invoke-Command -Session $pssRds -ScriptBlock {
    $filepath = "C:\Windows\Web\RDWeb\Pages\en-US\Desktops.aspx"
    $pattern = 'RDPstr \+= getUserNameRdpProperty\(\);'
    $replace = "RDPstr += `"pre-authentication server address:s:https://rdg.seclab.test/rdweb\n`";`r`n                RDPstr += `"require pre-authentication:i:1\n`";`r`n                RDPstr += getUserNameRdpProperty();"
    $text = Get-Content $filepath -raw
    if(-not ($text -match 'RDPstr \+= "pre-authentication server address')){
        [regex]::Replace($text, $pattern, $replace) | Set-Content $filepath 
    }
}

###### Configure ADFS
Invoke-Command -Session $pssAdfs -ScriptBlock {
    Add-AdfsRelyingPartyTrust -Name "RDS" -Identifier "https://rdg.seclab.test" -AccessControlPolicyName "Permit everyone"
}

###### Configure WebApplication

Invoke-Command -Session $pssWap -ScriptBlock {
    Add-WebApplicationProxyApplication `
        -BackendServerUrl 'http://ca.seclab.test' `
        -ExternalUrl 'http://ca.seclab.test$' `
        -Name 'CA' `
        -ExternalPreAuthentication PassThrough

    New-NetFirewallRule -DisplayName "Allow HTTP" -Enabled True -Action Allow -Protocol TCP -LocalPort 80

    $appCert = Get-ChildItem "Cert:\LocalMachine\My" | ? Subject -match ".*\*\.seclab\.test" | select -First 1

    Add-WebApplicationProxyApplication `
        -BackendServerUrl 'https://rdg.seclab.test' `
        -ExternalCertificateThumbprint $appCert.Thumbprint `
        -EnableHTTPRedirect:$true `
        -ExternalUrl 'https://rdg.seclab.test' `
        -Name 'RDS' `
        -ExternalPreAuthentication ADFS `
        -ADFSRelyingPartyName 'RDS'
    
    Get-WebApplicationProxyApplication | Set-WebApplicationProxyApplication -DisableHttpOnlyCookieProtection:$true -InactiveTransactionsTimeoutSec 28800
}

####### Create Test User

Invoke-Command -Session $pssDC -ScriptBlock {
    New-ADUser -Name "Zeroone Testuser" -GivenName "Zeroone" -Surname "Testuser" -SamAccountName "user01" -AccountPassword (Read-Host -AsSecureString -Prompt "Enter user01 Account Password") -Enabled $true
}

####### Configure ADFS as Remote Desktop Test Target

Invoke-Command -Session $pssAdfs -ScriptBlock {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "SECLAB\user01"
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
}
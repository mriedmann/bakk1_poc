. "$PSScriptRoot\..\lib\sessions.ps1"

$domainSessions = Get-PoCSessions -NeededHosts RDS, ADFS -UserName "SECLAB\Administrator"
$localSessions = Get-PoCSessions -NeededHosts WAP,DC
$pssAdfs = $domainSessions['ADFS']
$pssWap = $localSessions['WAP']
$pssDc = $localSessions['DC']

###### Configure RDS

# create app pool
# set access rules

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

    $appCert = Get-ChildItem "Cert:\LocalMachine\My" | ? Subject -match ".*\*\.seclab\.test" | select -First 1

    Add-WebApplicationProxyApplication `
        -BackendServerUrl 'https://rdg.seclab.test' `
        -ExternalCertificateThumbprint $appCert.Thumbprint `
        -EnableHTTPRedirect:$true `
        -ExternalUrl 'https://rdg.seclab.test' `
        -Name 'RDS' `
        -ExternalPreAuthentication ADFS `
        -ADFSRelyingPartyName 'RDS'
    
    Get-WebApplicationProxyApplication | Set-WebApplicationProxyApplication -DisableHttpOnlyCookieProtection:$true
}

####### Create Test User

Invoke-Command -Session $pssDC -ScriptBlock {
    New-ADUser -Name "Zeroone Testuser" -GivenName "Zeroone" -Surname "Testuser" -SamAccountName "user01" -AccountPassword (Read-Host -AsSecureString -Prompt "Enter user01 Account Password") -Enabled $true
}
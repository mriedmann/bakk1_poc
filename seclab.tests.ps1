. "$PSScriptRoot\lib\sessions.ps1"

$global:sessions = Get-PoCSessions

function Invoke-TargetCommand {
  param([string]$HostName, [scriptblock]$ScriptBlock , [object[]]$ArgumentList)

  if($HostName -eq "local"){
    return (Invoke-Command -ArgumentList $ArgumentList -ScriptBlock $ScriptBlock)
  } else {
    $session = $global:sessions[$HostName]
    return (Invoke-Command -Session $session -ArgumentList $ArgumentList -ScriptBlock $ScriptBlock)
  }
}

function Test-TargetConnection {
  param($HostName, $Target, $Action, $Result, $Port)

  $ip = $Target
  $text = if($Result){"should"}else{"shouldn't"}
  switch($Action){
    "ping" {
      $text += " be able to ping $($Target)"

      It $text {
        $r = Invoke-TargetCommand -HostName $HostName -ArgumentList @($ip) -ScriptBlock {param($ip) Test-Connection -ComputerName $ip -Count 1 -Quiet} 
        $r | Should Be $Result
      }
    }
    "tcp" {
      $text += " be able to reach tcp port $($Port) on $($Target)"
      $port = $Port

      It $text {
        $r = Invoke-TargetCommand -HostName $HostName -ArgumentList @($ip, $port) -ScriptBlock {param($ip,$port) Test-NetConnection -ComputerName $ip -Port $port} 
        $r.TcpTestSucceeded | Should Be $Result
      }
    }
  } 
}

Describe 'client01' {
  $target = "local"

  $connections = @(
    @{
      Target="fs.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    },@{
      Target="rdg.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    }
  )

  $connections | % {
    Test-TargetConnection -HostName $target -Target $_.Target -Action $_.Action -Result $_.Result -Port $_.Port
  }

}

Describe 'wap.dmz.seclab.test' {
  $target = 'WAP'

  $connections = @(
    @{
      Target="10.0.0.10"
      Action="ping"
      Result=$false
    },@{
      Target="10.10.10.1"
      Action="ping"
      Result=$true
    },@{
      Target="rdg.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    },@{
      Target="ca.seclab.test"
      Action="tcp"
      Port=80
      Result=$true
    },@{
      Target="fs.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    }
  )

  It "should have 'Web Application Proxy'-Role installed" {
    $result = Invoke-TargetCommand -HostName $target -ScriptBlock {Get-WindowsFeature -Name Web-Application-Proxy} 
    $result.Name | Should Be "Web-Application-Proxy" 
  }

  $connections | % {
    Test-TargetConnection -HostName $target -Target $_.Target -Action $_.Action -Result $_.Result -Port $_.Port
  }
}
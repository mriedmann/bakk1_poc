$sessions = Get-PSSession

@("wap.dmz.seclab.test") | %{
  if(($sessions | select -ExpandProperty Name) -notcontains $_ ) {
    New-PSSession -Name $_ -ComputerName $_ -Credential (Get-Credential -UserName "Administrator" -Message $_) -ErrorAction Stop
  }
}

function Invoke-TargetCommand {
  param([string]$ComputerName, [scriptblock]$ScriptBlock)
  $session = Get-PSSession -Name $ComputerName
  return (Invoke-Command -Session $session -ScriptBlock $ScriptBlock)
}

function Test-TargetConnection {
  param($ComputerName, $Target, $Action, $Result, $Port)

  $ip = $Target
  $text = if($Result){"should"}else{"shouldn't"}
  switch($Action){
    "ping" {
      $text += " can ping $($Target)"

      It $text {
        $result = Invoke-TargetCommand -ComputerName $ComputerName -ScriptBlock {Test-Connection -ComputerName $using:ip -Count 1 -Quiet} 
        $result | Should Be $Result
      }
    }
    "tcp" {
      $text += " can reach tcp port $($Port) on $($Target)"
      $port = $Port

      It $text {
        $result = Invoke-TargetCommand -ComputerName $ComputerName -ScriptBlock {Test-NetConnection -ComputerName $using:ip -Port $using:port} 
        $result.TcpTestSucceeded | Should Be $conn.Result
      }
    }
  } 
}

Describe 'client01' {
  $target = "127.0.0.1"

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
    Test-TargetConnection -ComputerName $target -Target $_.Target -Action $_.Action -Result $_.Result -Port $_.Port
  }

}

Describe 'wap.dmz.seclab.test' {
  $target = 'wap.dmz.seclab.test'

  $connections = @(
    @{
      Target="10.0.0.10"
      Action="ping"
      Result=$false
    },@{
      Target="10.0.0.101"
      Action="ping"
      Result=$true
    },@{
      Target="10.10.10.1"
      Action="ping"
      Result=$true
    },@{
      Target="adfs01.corp.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    },@{
      Target="fs.seclab.test"
      Action="tcp"
      Port=443
      Result=$true
    }
  )

  It "should have 'Web Application Proxy'-Role installed" {
    $result = Invoke-TargetCommand -ComputerName $target -ScriptBlock {Get-WindowsFeature -Name Web-Application-Proxy} 
    $result.Name | Should Be "Web-Application-Proxy" 
  }

  $connections | % {
    Test-TargetConnection -ComputerName $target -Target $_.Target -Action $_.Action -Result $_.Result -Port $_.Port
  }
}
################
## Variables
################

$menu = @"
1. Ingest host list from file path
2. Check hosts for shares
Q. To Quit the script

Select a task by number or Q to quit
"@

$host_list = ""
$log_file = "C:\users\username\desktop\open_shares.csv"
$poll_list = new-object System.Collections.Arraylist



################
## Functions
################

function ConvertTo-BinaryIP {
  <#
    .Synopsis
      Converts a Decimal IP address into a binary format.
    .Description
      ConvertTo-BinaryIP uses System.Convert to switch between decimal and binary format. The output from this function is dotted binary.
    .Parameter IPAddress
      An IP Address to convert.
  #>

  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Net.IPAddress]$IPAddress
  )

  process {  
    return [String]::Join('.', $( $IPAddress.GetAddressBytes() |
      ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') } ))
  }
}

function ConvertTo-DecimalIP {
  <#
    .Synopsis
      Converts a Decimal IP address into a 32-bit unsigned integer.
    .Description
      ConvertTo-DecimalIP takes a decimal IP, uses a shift-like operation on each octet and returns a single UInt32 value.
    .Parameter IPAddress
      An IP Address to convert.
  #>
  
  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Net.IPAddress]$IPAddress
  )

  process {
    $i = 3; $DecimalIP = 0;
    $IPAddress.GetAddressBytes() | ForEach-Object { $DecimalIP += $_ * [Math]::Pow(256, $i); $i-- }

    return [UInt32]$DecimalIP
  }
}
function ConvertTo-DottedDecimalIP {
  <#
    .Synopsis
      Returns a dotted decimal IP address from either an unsigned 32-bit integer or a dotted binary string.
    .Description
      ConvertTo-DottedDecimalIP uses a regular expression match on the input string to convert to an IP address.
    .Parameter IPAddress
      A string representation of an IP address from either UInt32 or dotted binary.
  #>

  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [String]$IPAddress
  )
  
  process {
    Switch -RegEx ($IPAddress) {
      "([01]{8}.){3}[01]{8}" {
        return [String]::Join('.', $( $IPAddress.Split('.') | ForEach-Object { [Convert]::ToUInt32($_, 2) } ))
      }
      "\d" {
        $IPAddress = [UInt32]$IPAddress
        $DottedIP = $( For ($i = 3; $i -gt -1; $i--) {
          $Remainder = $IPAddress % [Math]::Pow(256, $i)
          ($IPAddress - $Remainder) / [Math]::Pow(256, $i)
          $IPAddress = $Remainder
         } )
       
        return [String]::Join('.', $DottedIP)
      }
      default {
        Write-Error "Cannot convert this format"
      }
    }
  }
}

function ConvertTo-Mask {
  <#
    .Synopsis
      Returns a dotted decimal subnet mask from a mask length.
    .Description
      ConvertTo-Mask returns a subnet mask in dotted decimal format from an integer value ranging 
      between 0 and 32. ConvertTo-Mask first creates a binary string from the length, converts 
      that to an unsigned 32-bit integer then calls ConvertTo-DottedDecimalIP to complete the operation.
    .Parameter MaskLength
      The number of bits which must be masked.
  #>
  
  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Alias("Length")]
    [ValidateRange(0, 32)]
    $MaskLength
  )
  
  Process {
    return ConvertTo-DottedDecimalIP ([Convert]::ToUInt32($(("1" * $MaskLength).PadRight(32, "0")), 2))
  }
}

function Get-NetworkRange( [String]$IP, [String]$Mask ) {
  if ($IP.Contains("/")) {
    $Temp = $IP.Split("/")
    $IP = $Temp[0]
    $Mask = $Temp[1]
  }
 
  if (!$Mask.Contains(".")) {
    $Mask = ConvertTo-Mask $Mask
  }
 
  $DecimalIP = ConvertTo-DecimalIP $IP
  $DecimalMask = ConvertTo-DecimalIP $Mask
  
  $Network = $DecimalIP -band $DecimalMask
  $Broadcast = $DecimalIP -bor ((-bnot $DecimalMask) -band [UInt32]::MaxValue)
 
  for ($i = $($Network + 1); $i -lt $Broadcast; $i++) {
    ConvertTo-DottedDecimalIP $i
  }
}


$check_available_shares = {param($hostname)
  #$host_shares = get-host-shares($hostname)
  $hostname_netview = ((net view \\$hostname) -match '\S+\s+Disk')
  if ($hostname_netview){
    $host_shares = $hostname_netview.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries) | where-object {$_ -ne "Disk" -and $_ -ne "winapps"}
  } else {
    exit
  }
  write-host("host={0},share_count={1}" -f $hostname, $host_shares.count)
  if ($host_shares.count -gt 0){
    foreach ($host_share in $host_shares){
      if (test-path -path \\$hostname\$host_share){
        $logmsg = "{0},{1},{2}" -f $hostname, $host_share, "Successfully Connected"
        Out-File -filepath "C:\users\username\desktop\shares.csv" -inputobject $logmsg -append
        #log-this-data "C:\users\username\desktop\shares.csv", $logmsg
      }
    }
  }
}


Function get-host-shares($hostname){
  $hostname_netview = ((net view \\$hostname) -match '\S+\s+Disk')
  if ($hostname_netview){
    $hostname_netview = $hostname_netview.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries) | where-object {$_ -ne "Disk" -and $_ -ne "winapps"}
  }
  return $hostname_netview
  
}

Function retrieve-file {
  $file_path = Read-Host "What is the file path"
  if (Test-Path $file_path){
    $host_list = Get-Content $file_path
    if ($host_list.Length -eq 0){
      Write-Host "The file path provided does not contain any hosts!" -ForegroundColor Red    
    } else {
      Write-Host "Successfully retrieved host list."
      return $host_list
    } 
  } else {
    Write-Host "File path was not provided or is invalid or couldn't be found. Please try again." -ForegroundColor Red
  }
}

Function log-this-data ($logfile, $logmsg) {
  Out-File -filepath $logfile -inputobject $logmsg -append
}


Function press-any-key {
  Write-Host "Press any key to continue ..."
  $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Function Show-Menu {

Param(
[Parameter(Position=0,Mandatory=$True,HelpMessage="Enter your menu text")]
[ValidateNotNullOrEmpty()]
[string]$Menu,
[Parameter(Position=1)]
[ValidateNotNullOrEmpty()]
[string]$Title="Menu",
[switch]$ClearScreen
)

if ($ClearScreen) {Clear-Host}

#build the menu prompt
$menuPrompt=$title
#add a return
$menuprompt+="`n"
#add an underline
$menuprompt+="-"*$title.Length
$menuprompt+="`n"
#add the menu
$menuPrompt+=$menu

Read-Host -Prompt $menuprompt

} #end function



################
## Main loop
################

$maxthreads = 200
$sleep = 5000


Do {

  #use a Switch construct to take action depending on what menu choice is selected.
  Switch (Show-Menu $menu "My  Helper Tasks" -clear ) {
    "1" {
    Write-Host "** Ingest host list from file path **" -ForegroundColor Green
    $host_list = retrieve-file
    foreach ($h in $host_list){ Write-Host $h }
    press-any-key
  }
    "2" {
    Write-Host "** Check netrange hosts for open shares **" -ForegroundColor Green
    # meh..idc where i put this.
    $loghdr = "hostname,host_share,status"
    Out-File -filepath "C:\users\username\desktop\shares.csv" -inputobject $loghdr -append

    $hosts = Get-NetworkRange 10.0.0.1 16
    $i = 0
    foreach ($h in $hosts) {
      while ((get-job -state running).count -ge $maxthreads){
        write-host "Reached maxthreads. Pausing."
        get-job
        start-sleep -milliseconds $sleep
        write-host "Purging completed jobs."
        get-job -state completed | % {receive-job -wait -AutoRemoveJob $_.id}
      }
      $i++
      start-job -filepath C:\code\powershell\get-openshares.ps1 -argumentlist $h
      write-host "Host count: $i"
      }

      get-job | wait-job
    

    press-any-key
  }
    "Q" {
    Write-Host "** Goodbye **" -ForegroundColor Cyan
    Return
    }
  
    Default {
      Write-Warning "Invalid Choice. Try again."  -ForegroundColor Red
      sleep -milliseconds 750
    }
  } #switch
  
} While ($True)


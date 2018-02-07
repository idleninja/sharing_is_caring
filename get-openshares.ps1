
### Get-OpenShares.ps1 ###
Param($hostname = "Localhost")


$hostname_netview = ((net view \\$hostname) -match '\S+\s+Disk')

if ($hostname_netview){
  $host_shares = ($hostname_netview -split "\s{2,}(!?Disk)") | ? {$_ -ne "Disk" -and $_ -ne "" -and $_ -ne "winapps" -and $_ -ne "print" -and $_ -notlike "*UNC*" -and $_ -notlike "*     *" }
} else {
  $loghdr = "{0},{1},{2}" -f $hostname, "-", "No Shares"
  Out-File -filepath "C:\users\username\desktop\shares.csv" -inputobject $loghdr -append
  return
}

if ($host_shares.count -gt 0){
  foreach ($host_share in $host_shares){
    if (test-path -path \\$hostname\$host_share){
      $acl = (get-acl -path \\$hostname\$host_share).AccessToString.replace(",", " &").replace("`n", ";")
      $logmsg = "{0},{1},{2},{3}" -f $hostname, $host_share, "Successfully Connected", $acl
      Out-File -filepath "C:\users\username\desktop\shares.csv" -inputobject $logmsg -append
      write-host $logmsg
      #log-this-data "C:\users\username\desktop\shares.csv", $logmsg
    } else {
      $logmsg = "{0},{1},{2}" -f $hostname, $host_share, "Failed to Connect"
      Out-File -filepath "C:\users\username\desktop\shares.csv" -inputobject $logmsg -append
    }
  }
}


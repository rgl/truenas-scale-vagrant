param(
    [string]$storageIpAddress = '10.10.0.12',
    [string]$iscsiPortal = '10.10.0.2',
    [int]$storageMtu = 9000
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

# configure the storage network interface when running in vsphere.
$systemVendor = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -Property Vendor).Vendor
if ($systemVendor -eq 'VMware, Inc.') {
    # NB the first network adapter is the vagrant management interface
    #    which we do not modify.
    # NB this is somewhat brittle: InterfaceIndex sometimes does not enumerate
    #    the same way, so we use MacAddress instead, as it seems to work more
    #    reliably; but this is not ideal either.
    # TODO somehow use the MAC address to set the IP address.
    $adapter = Get-NetAdapter -Physical | Sort-Object MacAddress | Select-Object -Index 1
    $address = $storageIpAddress
    $adapterAddresses = @($adapter | Get-NetIPAddress -ErrorAction SilentlyContinue)
    if ($adapterAddresses -and ($adapterAddresses.IPAddress -ne $address)) {
        Write-Output "Setting the $($adapter.Name) ($($adapter.MacAddress)) adapter IP address to $address..."
        $adapter | New-NetIPAddress -IPAddress $address -PrefixLength 24 | Out-Null
        $adapter | Set-NetConnectionProfile -NetworkCategory Private | Out-Null
    }
    $adapter | Set-NetIPInterface -NlMtuBytes $storageMtu
}

# start the Microsoft iSCSI Initiator Service.
Set-Service MSiSCSI -StartupType Automatic
Start-Service MSiSCSI

# mount the windows-data iscsi disk lun.
New-IscsiTargetPortal `
    -TargetPortalAddress $iscsiPortal `
    -TargetPortalPortNumber 3260 `
    | Out-Null
Get-IscsiTarget | ForEach-Object {
    Write-Output "Available iSCSI Target: $($_.NodeAddress)"
}
$iscsiTargetAddress = 'iqn.2005-10.org.freenas.ctl:windows-data'
Connect-IscsiTarget `
    -NodeAddress $iscsiTargetAddress `
    -IsPersistent:$true `
    | Out-Null
Get-Disk | Where-Object { $_.BusType -eq 'iSCSI' } | ForEach-Object {
    $disk = $_
    $session = $disk | Get-IscsiSession
    if (!$session -or $session.TargetNodeAddress -ne $iscsiTargetAddress) {
        return
    }
    $diskDrive = Get-CimInstance Win32_DiskDrive -Filter "Index='$($disk.DiskNumber)'"
    if (!$diskDrive) {
        return
    }
    $lun = $diskDrive.SCSILogicalUnit
    if ($lun -ne 0) {
        return
    }
    if ($disk.IsOffline) {
        Write-Host "Setting disk to Online..."
        $disk | Set-Disk -IsOffline:$false
    }
    if ($disk.PartitionStyle -eq 'RAW') {
        Write-Host "Initializing LUN #$lun ($($disk.Size) bytes)..."
        $volume = $disk `
          | Initialize-Disk -PartitionStyle GPT -PassThru `
          | New-Partition -AssignDriveLetter -UseMaximumSize `
          | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'windows-data' -Confirm:$false
        Write-Host "Initialized LUN #$lun ($($_.Size) bytes) as $($volume.DriveLetter):."
        $disk = $disk | Get-Disk
    }
}
Get-IscsiTarget | Where-Object { $_.IsConnected } | ForEach-Object {
    Write-Output "Connected iSCSI Target: $($_.NodeAddress)"
}

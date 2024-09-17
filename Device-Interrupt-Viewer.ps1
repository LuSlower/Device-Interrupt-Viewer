# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Console
{
    param ([Switch]$Show,[Switch]$Hide)
    if (-not ("Console.Window" -as [type])) { 

        Add-Type -Name Window -Namespace Console -MemberDefinition '
        [DllImport("Kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
        '
    }

    if ($Show)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()

        $null = [Console.Window]::ShowWindow($consolePtr, 5)
    }

    if ($Hide)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()
        #0 hide
        $null = [Console.Window]::ShowWindow($consolePtr, 0)
    }
}

function Get-CoreIndex {
    param (
        [uint32]$CoreMask
    )

    $coreList = "N/A"
    $isFirst = $false
    $currentCore = 0
    $mask = $CoreMask

    while ($mask -gt 0) {
        if ($mask % 2 -eq 1) {
            if (-not $isFirst) {
                $coreList = "$currentCore"
                $isFirst = $true
            } else {
                $coreList += ", $currentCore"
            }
        }
        $mask = [math]::Floor($mask / 2)
        $currentCore++
    }
    
    return $coreList
}


function Load-ListViewData {
    $listView.Items.Clear()
    $enumKey = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    $categoryKeys = Get-ChildItem -Path $enumKey
    $showAllDevices = $chkShowAll.Checked

    foreach ($categoryKey in $categoryKeys) {
        $deviceKeys = Get-ChildItem -Path $categoryKey.PSPath
        foreach ($deviceKey in $deviceKeys) {
            $instanceKeys = Get-ChildItem -Path $deviceKey.PSPath
            foreach ($instanceKey in $instanceKeys) {
                $deviceDesc = $instanceKey.GetValue("DeviceDesc")
                if ($deviceDesc -like "*;*") {
                    $deviceDesc = $deviceDesc.Split(";")[1]
                }

                $temporalPath = "$($instanceKey.PSPath)\Device Parameters\Interrupt Management\Affinity Policy - Temporal"
                $msiPath = "$($instanceKey.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                $Path = "$($instanceKey.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"

                # Obtener Affinity y Priority
                $cores = $null
                $priority = $null
                $msiSupported = $null
                $messageLimit = $null

                $showDevice = $false
                if (Test-Path -Path $temporalPath) {
                    $temporalKey = Get-Item -Path $temporalPath
                    $bitmask = $temporalKey.GetValue("TargetSet", $null)
                    if ($bitmask -ne $null) {
                        $tempcores = Get-CoreIndex -CoreMask $BitMask
                        $showDevice = $true
                    }
                } else {
                        $tempcores = "N/A"
                }

                if (Test-Path -Path $Path) {
                    $defaultKey = Get-Item -Path $Path
                    $priority = $defaultKey.GetValue("DevicePriority", $null)
                    $policy = $defaultKey.GetValue("DevicePolicy", $null)
                    $assignmentBytes = $defaultKey.GetValue("AssignmentSetOverride", $null)
                    if ($assignmentBytes -ne $null) {
                        if ($assignmentBytes.Length -eq 4) {
                            # Convertir el array de bytes a UInt32
                            $assignment = [BitConverter]::ToUInt32($assignmentBytes, 0)
                            $cores = Get-CoreIndex -CoreMask $assignment
                        }
                    }
                } else {
                    $priority = "N/A"
                    $policy = "N/A"
                    $assignmentBytes = "N/A"

                }

                if (Test-Path -Path $msiPath) {
                    $msiKey = Get-Item -Path $msiPath
                    $msiSupported = $msiKey.GetValue("MSISupported", $null)
                    $messageLimit = $msiKey.GetValue("MessageNumberLimit", $null)
                }

                if ($showAllDevices -or $showDevice) {
                    $item = New-Object System.Windows.Forms.ListViewItem($deviceDesc)

                    $item.SubItems.Add($tempcores)

                    switch ($policy) {
                        0 {$strpolicy = "MachineDefault (0)"}
                        1 {$strpolicy = "AllCloseProc (1)"}
                        2 {$strpolicy = "OneCloseProc (2)"}
                        3 {$strpolicy = "AllProcInMachine (3)"}
                        4 {$strpolicy = "SpecifiedProc (4)"}
                        5 {$strpolicy = "SpreadMessagesAcrossAllProc (5)"}
                        6 {$strpolicy = "AllProcInMachineWhenSteered (6)"}
                            
                        default {
                            $strpolicy = "N/A"
                        }
                    }
                    $item.SubItems.Add($strpolicy)

                    switch ($priority) {
                        1 {$strpriority = "Low (1)"}
                        2 {$strpriority = "Normal (2)"}
                        3 {$strpriority = "High (3)"}

                        default {
                            $strpriority = "N/A"
                        }

                    }
                    $item.SubItems.Add($strpriority)

                    switch ($msiSupported) {
                        0 {$strmsi = "Off"}
                        1 {$strmsi = "On"}

                        default {
                            $strmsi = "N/A"
                        }
                    }
                    $item.SubItems.Add($strmsi)

                    if ($messageLimit) {
                        $item.SubItems.Add("$messageLimit Messages")
                    } else {
                        $item.SubItems.Add("N/A")
                    }

                        $item.SubItems.Add("$instanceKey")

                    $listView.Items.Add($item)
                }
            }
        }
    }

    $listView.AutoResizeColumns([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::ColumnContent)
}

# ocultar consola, crear form
Console -Hide
[System.Windows.Forms.Application]::EnableVisualStyles();
$form = New-Object System.Windows.Forms.Form
$form.Text = "Device-Interrupt-Viewer"
$form.ClientSize = New-Object System.Drawing.Size(780,440)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Load-ListViewData
    }
})

$form.Add_Paint({
    param (
        [object]$sender,
        [System.Windows.Forms.PaintEventArgs]$e
    )
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(44, 44, 44),   # Color negro
        [System.Drawing.Color]::FromArgb(99, 99, 99),# Color gris oscuro
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $e.Graphics.FillRectangle($brush, $rect)
})

$listView = New-Object System.Windows.Forms.ListView
$listView.Size = New-Object System.Drawing.Size(760, 400)
$listView.Location = New-Object System.Drawing.Point(10, 10)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)  # Fondo oscuro
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 255)  # Texto blanco

$columnHeader1 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader1.Text = "Device Description"
$columnHeader2 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader2.Text = "Affinity"
$columnHeader3 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader3.Text = "Policy"
$columnHeader4 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader4.Text = "Priority"
$columnHeader5 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader5.Text = "Msi"
$columnHeader6 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader6.Text = "MsiLimit"
$columnHeader7 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader7.Text = "KeyPath"

$listView.Columns.AddRange(@($columnHeader1, $columnHeader2, $columnHeader3, $columnHeader4, $columnHeader5, $columnHeader6, $columnHeader7))
$form.Controls.Add($listView)

$listView.Add_DoubleClick({
    $selectedItem = $listView.SelectedItems[0]
    if ($selectedItem) {
        $keyPathValue = $selectedItem.SubItems[6].Text
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $keyPathValue
        Start-Process -FilePath regedit
    }
})

$chkShowAll = New-Object System.Windows.Forms.CheckBox
$chkShowAll.Size = New-Object System.Drawing.Size(120, 20)
$chkShowAll.Location = New-Object System.Drawing.Point(10, 415)
$chkShowAll.Text = "Show All Devices"
$chkShowAll.ForeColor = [System.Drawing.Color]::White
$chkShowAll.BackColor = [System.Drawing.Color]::Transparent
$chkShowAll.Add_CheckedChanged({
    Load-ListViewData | Out-Null
})
$form.Controls.Add($chkShowAll)

Load-ListViewData | Out-Null

[void]$form.ShowDialog()

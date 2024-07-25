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

function Get-Cores {
    param (
        [uint32]$TargetSet
    )
    
    $CoreNumber = 0
    $str = "(invalid assignment)"
    $ds = $false
    $TS = $TargetSet
    
    while ($TS -gt 0) {
        if ($TS % 2 -eq 1) {
            if (-not $ds) {
                $str = "$CoreNumber"
                $ds = $true
            } else {
                $str += ", $CoreNumber"
            }
        }
        $TS = [math]::Floor($TS / 2)
        $CoreNumber++
    }
    
    return $str
}

function Load-ListViewData {
    $listView.Items.Clear()
    $enumKey = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    $categoryKeys = Get-ChildItem -Path $enumKey

    foreach ($categoryKey in $categoryKeys) {
        $deviceKeys = Get-ChildItem -Path $categoryKey.PSPath
        foreach ($deviceKey in $deviceKeys) {
            $instanceKeys = Get-ChildItem -Path $deviceKey.PSPath
            foreach ($instanceKey in $instanceKeys) {
                $parametersKeyPath = "$($instanceKey.PSPath)\Device Parameters\Interrupt Management\Affinity Policy - Temporal"
                if (Test-Path -Path $parametersKeyPath) {
                    $temporalKey = Get-Item -Path $parametersKeyPath
                    if ($temporalKey.GetValue("TargetSet")) {
                        $targetSet = $temporalKey.GetValue("TargetSet")
                        $deviceDesc = $instanceKey.GetValue("DeviceDesc")
                        if ($deviceDesc -like "*;*") {
                            $deviceDesc = $deviceDesc.Split(";")[1]
                        }
                        $cores = Get-Cores -TargetSet $targetSet
                        $item = New-Object System.Windows.Forms.ListViewItem($deviceDesc)
                        $item.SubItems.Add($cores)
                        $listView.Items.Add($item)
                    }
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
$form.Text = "Device-Affinity-Checker"
$form.ClientSize = New-Object System.Drawing.Size(780,550)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Load-ListViewData
    }
})

$listView = New-Object System.Windows.Forms.ListView
$listView.Size = New-Object System.Drawing.Size(760, 500)
$listView.Location = New-Object System.Drawing.Point(10, 10)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true

$columnHeader1 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader1.Text = "Device Description"
$columnHeader1.Width = -2
$columnHeader2 = New-Object System.Windows.Forms.ColumnHeader
$columnHeader2.Text = "Affinity"
$columnHeader2.Width = -2

$listView.Columns.AddRange(@($columnHeader1, $columnHeader2))
$form.Controls.Add($listView)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Size = New-Object System.Drawing.Size(75, 23)
$refreshButton.Location = New-Object System.Drawing.Point(10, 520)
$refreshButton.Add_Click({ Load-ListViewData })
$form.Controls.Add($refreshButton)

# cargar datos iniciales + flujo de salida nulo
Load-ListViewData | Out-Null

[void]$form.ShowDialog()

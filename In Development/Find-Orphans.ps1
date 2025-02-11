# Powershell script to discover VMDK files that are not referenced in any VM's VMX file.
# Warning - I've heard reports that this doesn't work on some versions of ESXi and have no had time to troubleshoot/test it.
# Also detects VMDKs from machines that need snapshot consolidation (from differentials that exist but are not part of the tree).
# Author: HJA van Bokhoven
# Modifications: LucD

function LoadSnapin{
  param($PSSnapinName)
  if (!(Get-PSSnapin | where {$_.Name   -eq $PSSnapinName})){
    Add-pssnapin -name $PSSnapinName
  }
}

# Load PowerCLI snapin
LoadSnapin -PSSnapinName   "VMware.VimAutomation.Core"

# Variables
[string] $vCenter = "vcenter.domain.local" # vCenter FQDN
# Connect to vCenter
Connect-VIServer -Server $vCenter

$report = @()
$arrUsedDisks = Get-View -ViewType VirtualMachine | % {$_.Layout} | % {$_.Disk} | % {$_.DiskFile}
$arrDS = Get-Datastore | Sort-Object -property Name
foreach ($strDatastore in $arrDS) {
    Write-Host "Checking" $strDatastore.Name "..."
    $ds = Get-Datastore -Name $strDatastore.Name | % {Get-View $_.Id}
    $fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
    $fileQueryFlags.FileSize = $true
    $fileQueryFlags.FileType = $true
    $fileQueryFlags.Modification = $true
    $searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
    $searchSpec.details = $fileQueryFlags
    $searchSpec.matchPattern = "*.vmdk"
    $searchSpec.sortFoldersFirst = $true
    $dsBrowser = Get-View $ds.browser
    $rootPath = "[" + $ds.Name + "]"
    $searchResult = $dsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)

    foreach ($folder in $searchResult)
    {
        foreach ($fileResult in $folder.File)
        {
            if ($fileResult.Path)
            {
                if (-not ($fileResult.Path.contains("ctk.vmdk"))) #Remove Change Tracking Files
                {
                    if (-not ($arrUsedDisks -contains ($folder.FolderPath.trim('/') + '/' + $fileResult.Path)))
                    {
                        $row = "" | Select DS, Path, File, Size, ModDate
                        $row.DS = $strDatastore.Name
                        $row.Path = $folder.FolderPath
                        $row.File = $fileResult.Path
                        $row.Size = $fileResult.FileSize
                        $row.ModDate = $fileResult.Modification
                        $report += $row
                    }
                }
            }
        }
    }
} 

# Print report to console
$report

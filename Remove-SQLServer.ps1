<#
.SYNOPSIS
Uninstall all instances and components of Microsoft SQL Server from a Windows 11 computer.

.DESCRIPTION
  - Identifies SQL Server products through the registry.
  - Stops MSSQL* services.
  - Runs each uninstaller in silent mode.
  - Cleans residual directories.

.RUN
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\Remove-SQLServer.ps1

.NOTES
  Author : César Reneses
  Date : 26-May-2025
#>

#region Privilege check

$IsAdmin = (
    [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Error "You must run this script in a PowerShell console with administrator rights."
    exit 1
}
#endregion


#region Stop SQL Server services (in case of remaining locks)
Write-Host "`nStopping services MSSQL*..." -ForegroundColor Cyan
Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Status -ne 'Stopped') {
        try {
            Stop-Service $_ -Force -ErrorAction Stop
            Write-Host "  > Service $($_.Name) stopped."
        } catch {
            Write-Warning "  ! Could not be stopped $($_.Name): $_"
        }
    }
}
#endregion

#region Locate SQL Server products in the registry
$uninstallRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$sqlProducts = foreach ($root in $uninstallRoots) {
    Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
      Where-Object {
          $_.DisplayName -match 'SQL Server' -or
          $_.DisplayName -match 'Microsoft SQL Server'
      } |
      Select-Object DisplayName, DisplayVersion, UninstallString
}

if (-not $sqlProducts) {
    Write-Host "`nNo SQL Server components were detected on this computer." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nComponents found:" -ForegroundColor Green
$sqlProducts | ForEach-Object {
    Write-Host "  • $($_.DisplayName)  ($($_.DisplayVersion))"
}
#endregion

#region Silent uninstallation
foreach ($prod in $sqlProducts) {
    $cmd = $prod.UninstallString
    if (-not $cmd) {
        Write-Warning "No uninstall string found for $($prod.DisplayName). Omitted."
        continue
    }

    # Standardize: many products register “…\msiexec.exe /I{GUID}…”.
    if ($cmd -match 'msiexec\.exe.*\/I\{([0-9A-F\-]+)\}') {
        $guid = $Matches[1]
        $cmd  = "msiexec.exe /x{$guid} /quiet /norestart"
    }
    elseif ($cmd -match 'setup\.exe' -and $cmd -notmatch '/quiet') {
        # Add silent parameters compatible with SQL Server setup.exe
        $cmd += ' /quiet /norestart /removeallsharedfeatures /skiprules=RebootRequiredCheck'
    }

    Write-Host "`n→ Uninstalling: $($prod.DisplayName)..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cmd`"" -Wait -Verb RunAs
        Write-Host "   ✓ After the uninstallation of $($prod.DisplayName)."
    } catch {
        Write-Error "   ✗ Error while uninstalling $($prod.DisplayName): $_"
    }
}
#endregion

#region Cleaning of residual folders
Write-Host "`nRemoving residual folders..." -ForegroundColor Cyan
$paths = @(
    "$Env:ProgramFiles\Microsoft SQL Server",
    "$Env:ProgramFiles(x86)\Microsoft SQL Server",
    "$Env:ProgramData\Microsoft\SQL Server"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        try {
            Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
            Write-Host "  • Eliminado $p"
        } catch {
            Write-Warning "  ! No se pudo eliminar ${p}: $_"
        }
    }
} 
#endregion

Write-Host "`nProcess completed. It is recommended to restart the computer." -ForegroundColor Green
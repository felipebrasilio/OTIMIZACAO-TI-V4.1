<#
OTIMIZACAO TI - Modulo de Apps Classicos do Windows
Submenu separado do modulo de IA.
Nao inclui binarios proprietarios do Windows. Para Paint/Snipping/Notepad classicos, coloque os payloads locais em:
payloads\ClassicApps\mspaint\
payloads\ClassicApps\snippingtool\
payloads\ClassicApps\notepad\
#>
[CmdletBinding()]
param(
    [ValidateSet('photoviewer','mspaint','snippingtool','notepad','photoslegacy','all')]
    [string]$App = 'photoviewer',
    [string]$PayloadRoot = '.\payloads\ClassicApps',
    [string]$LogPath = "$env:ProgramData\OtimizacaoTI\Logs\ClassicApps.log"
)
$BaseDir = Join-Path $env:ProgramData 'OtimizacaoTI\ClassicApps'
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
function Log { param([string]$m,[string]$l='INFO') $line='[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$l,$m; Write-Host $line; Add-Content -Path $LogPath -Value $line -Encoding UTF8 -EA SilentlyContinue }
function Assert-Admin { $p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent(); if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ Log 'Execute como administrador.' 'ERROR'; exit 1 } }
function Enable-ClassicPhotoViewer {
    Log 'Habilitando Visualizador de Fotos classico no registro.'
    $base='HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations'
    New-Item $base -Force | Out-Null
    foreach($ext in '.jpg','.jpeg','.png','.bmp','.gif','.tif','.tiff','.jfif','.wdp'){
        New-ItemProperty -Path $base -Name $ext -Value 'PhotoViewer.FileAssoc.Tiff' -PropertyType String -Force | Out-Null
    }
    $app='HKLM:\SOFTWARE\RegisteredApplications'
    New-Item $app -Force | Out-Null
    New-ItemProperty -Path $app -Name 'Windows Photo Viewer' -Value 'SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities' -PropertyType String -Force | Out-Null
    Log 'Visualizador de Fotos classico habilitado. Defina como app padrao em Configuracoes > Apps padrao.' 'OK'
}
function Install-ClassicPayload {
    param([string]$Name,[string]$Exe)
    $src=Join-Path $PayloadRoot $Name
    $dest=Join-Path $BaseDir $Name
    if(-not (Test-Path $src)){
        Log "Payload local nao encontrado para $Name: $src" 'WARN'
        Log "Coloque os arquivos classicos em payloads\ClassicApps\$Name\ e rode novamente." 'WARN'
        return
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
    $exePath=Join-Path $dest $Exe
    if(Test-Path $exePath){
        $shortcut = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) ("$Name Classico.lnk")
        $w = New-Object -ComObject WScript.Shell
        $s = $w.CreateShortcut($shortcut)
        $s.TargetPath = $exePath
        $s.WorkingDirectory = $dest
        $s.Save()
        Log "Atalho criado: $shortcut" 'OK'
    } else { Log "Executavel esperado nao encontrado apos copia: $exePath" 'WARN' }
}
function Install-PhotosLegacy {
    Log 'Tentando instalar Microsoft Photos Legacy via winget.'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if(-not $winget){ Log 'winget nao encontrado. Instale o App Installer/Microsoft Store ou instale Photos Legacy manualmente.' 'WARN'; return }
    $ids = @('Microsoft.PhotosLegacy','9NV2L4XVMCXM')
    foreach($id in $ids){
        Log "Tentando winget install $id"
        $p = Start-Process winget.exe -ArgumentList @('install','--id',$id,'-e','--accept-package-agreements','--accept-source-agreements') -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        if($p -and $p.ExitCode -eq 0){ Log "Photos Legacy instalado usando $id" 'OK'; return }
    }
    Log 'Nao foi possivel instalar Photos Legacy automaticamente. Abra a Microsoft Store e procure por Photos Legacy.' 'WARN'
}
Assert-Admin
Log "Modulo Apps Classicos iniciado. App=$App"
$apps = if($App -eq 'all') { @('photoviewer','mspaint','snippingtool','notepad','photoslegacy') } else { @($App) }
foreach($a in $apps){
    switch($a){
        'photoviewer' { Enable-ClassicPhotoViewer }
        'mspaint' { Install-ClassicPayload -Name 'mspaint' -Exe 'mspaint.exe' }
        'snippingtool' { Install-ClassicPayload -Name 'snippingtool' -Exe 'SnippingTool.exe' }
        'notepad' { Install-ClassicPayload -Name 'notepad' -Exe 'notepad.exe' }
        'photoslegacy' { Install-PhotosLegacy }
    }
}
Log "Modulo Apps Classicos finalizado. App=$App" 'OK'

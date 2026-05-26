<#
OTIMIZACAO TI - Modulo Local de Remocao de Recursos de IA do Windows (V4.1 hardening)
- Dry-run suportado
- Allowlist para deteccao
- Edicao de JSON com parse estrutural (sem replace global)
- Acoes profundas inseguras desativadas por padrao
#>
[CmdletBinding()]
param(
    [ValidateSet('Diagnose','DisablePolicies','RemoveAppxAndRecall','RemoveDeep','PreventReinstall','All','RevertPolicies')]
    [string]$Action = 'Diagnose',
    [string]$LogPath = "$env:ProgramData\OtimizacaoTI\Logs\OtimizacaoTI_AI.log",
    [string]$ConfirmText = '',
    [switch]$SkipRestorePoint,
    [switch]$PurgeFiles,
    [switch]$DryRun,
    [switch]$UnsafeDeepActions
)

$ErrorActionPreference = 'Continue'
$BaseDir = Join-Path $env:ProgramData 'OtimizacaoTI'
$BackupDir = Join-Path $BaseDir 'Backups\AI'
$QuarantineDir = Join-Path $BaseDir 'Quarantine\AI'
$ModuleInstallDir = Join-Path $BaseDir 'Modules'
New-Item -ItemType Directory -Force -Path $BackupDir,$QuarantineDir,$ModuleInstallDir | Out-Null

$script:PlanItems = New-Object System.Collections.Generic.List[object]

function Add-PlanItem {
    param([string]$Area,[string]$Target,[string]$Action,[string]$Result,[string]$Detail='')
    $script:PlanItems.Add([pscustomobject]@{ Area=$Area; Target=$Target; Action=$Action; Result=$Result; Detail=$Detail }) | Out-Null
}
function Write-OTILog {
    param([string]$Message,[ValidateSet('INFO','OK','WARN','ERROR')]$Level='INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}
function Write-PlanReport {
    Write-OTILog '===== RELATORIO DRY-RUN/EXECUCAO ====='
    foreach($i in $script:PlanItems){
        Write-OTILog ("[{0}] {1} | {2} | {3} {4}" -f $i.Result,$i.Area,$i.Action,$i.Target,$i.Detail)
    }
    Write-OTILog '===== FIM RELATORIO ====='
}
function Assert-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-OTILog 'Execute como administrador.' 'ERROR'
        exit 1
    }
}
function Assert-WindowsPowerShell51 {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-OTILog 'PowerShell 7+ nao suportado para este modulo. Use powershell.exe Windows PowerShell 5.1.' 'ERROR'
        exit 1
    }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-OTILog "PowerShell em modo $($ExecutionContext.SessionState.LanguageMode). Necessario FullLanguage." 'ERROR'
        exit 1
    }
}
function Export-RegKeySafe {
    param([string]$RegPath,[string]$Name)
    $file = Join-Path $BackupDir ("{0}_{1}.reg" -f (Get-Date -Format yyyyMMdd_HHmmss), ($Name -replace '[^a-zA-Z0-9_-]','_'))
    if($DryRun){ Add-PlanItem 'RegistryBackup' $RegPath 'Export' 'WouldDo' $file; return }
    & reg.exe export $RegPath $file /y *> $null
    if ($LASTEXITCODE -eq 0) { Write-OTILog "Backup de registro criado: $file" 'OK'; Add-PlanItem 'RegistryBackup' $RegPath 'Export' 'Done' $file }
}
function New-OTIRestorePoint {
    if ($SkipRestorePoint) { Write-OTILog 'Ponto de restauracao ignorado por parametro.' 'WARN'; return }
    if($DryRun){ Add-PlanItem 'RestorePoint' 'SystemRestore' 'Create' 'WouldDo'; return }
    try {
        $vss = Get-Service VSS -ErrorAction SilentlyContinue
        if ($vss -and $vss.StartType -eq 'Disabled') { Set-Service VSS -StartupType Manual -ErrorAction SilentlyContinue }
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Force -ErrorAction SilentlyContinue
        $name = 'OtimizacaoTI-RemoveWindowsAI-' + (Get-Date -Format 'yyyy-MM-dd-HHmm')
        Checkpoint-Computer -Description $name -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OTILog 'Ponto de restauracao criado.' 'OK'
        Add-PlanItem 'RestorePoint' 'SystemRestore' 'Create' 'Done' $name
    } catch {
        Write-OTILog "Nao foi possivel criar ponto de restauracao: $($_.Exception.Message)" 'WARN'
        Add-PlanItem 'RestorePoint' 'SystemRestore' 'Create' 'Failed' $_.Exception.Message
    }
}
function Require-StrongConfirmation {
    param([string]$ForAction)
    if ($ConfirmText -ne 'REMOVER IA') {
        Write-OTILog "Confirmacao forte ausente para $ForAction. Use ConfirmText='REMOVER IA'." 'ERROR'
        exit 2
    }
}
function Require-UnsafeDeepApproval {
    if(-not $UnsafeDeepActions){
        Write-OTILog 'Acoes profundas (CBS/arquivos protegidos) bloqueadas por hardening. Use -UnsafeDeepActions para habilitar.' 'WARN'
        Add-PlanItem 'Safety' 'DeepActions' 'Guard' 'Skipped' 'UnsafeDeepActions ausente'
        return $false
    }
    return $true
}

function Get-AIAllowlist {
    [pscustomobject]@{
        AppxPatterns = @(
            'Microsoft.Copilot',
            'Microsoft.WindowsAI',
            'Microsoft.WindowsRecall',
            'MicrosoftWindows.Client.AIX',
            'Microsoft.AIHub',
            'Copilot',
            'Recall'
        )
        OptionalFeaturePatterns = @(
            'Recall',
            'WindowsAI',
            'WindowsCopilot',
            'AIX'
        )
        TaskPatterns = @(
            'Recall',
            'Copilot',
            'WindowsAI',
            'AIX'
        )
        CBSPatterns = @(
            'Copilot',
            'Recall',
            'WindowsAI',
            'Client.AIX'
        )
        JsonPolicyTargets = @(
            'copilot',
            'recall',
            'windowsai',
            'client.aix'
        )
    }
}
function Test-AllowMatch {
    param([string]$Text,[string[]]$Patterns)
    if([string]::IsNullOrWhiteSpace($Text)){ return $false }
    foreach($p in $Patterns){ if($Text -like "*$p*"){ return $true } }
    return $false
}
function Backup-AIRegistryAreas {
    Export-RegKeySafe 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'HKLM_WindowsAI_Policies'
    Export-RegKeySafe 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'HKCU_WindowsAI_Policies'
    Export-RegKeySafe 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'HKCU_WindowsCopilot_Policies'
    Export-RegKeySafe 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'HKLM_Edge_Policies'
    Export-RegKeySafe 'HKCU\SOFTWARE\Policies\Microsoft\Edge' 'HKCU_Edge_Policies'
    Export-RegKeySafe 'HKLM\SOFTWARE\Policies\Microsoft\office' 'HKLM_Office_Policies'
}
function Set-RegDword {
    param([string]$Path,[string]$Name,[int]$Value)
    if($DryRun){ Add-PlanItem 'Registry' "$Path\$Name" 'SetDword' 'WouldDo' $Value; return }
    try {
        New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Add-PlanItem 'Registry' "$Path\$Name" 'SetDword' 'Done' $Value
    } catch {
        Add-PlanItem 'Registry' "$Path\$Name" 'SetDword' 'Failed' $_.Exception.Message
        Write-OTILog "Falha ao gravar registro ${Path}\\${Name}: $($_.Exception.Message)" 'WARN'
    }
}
function Remove-RegValueSafe {
    param([string]$Path,[string]$Name)
    if($DryRun){ Add-PlanItem 'Registry' "$Path\$Name" 'RemoveValue' 'WouldDo'; return }
    try {
        Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        Add-PlanItem 'Registry' "$Path\$Name" 'RemoveValue' 'Done'
    } catch {
        Add-PlanItem 'Registry' "$Path\$Name" 'RemoveValue' 'Failed' $_.Exception.Message
    }
}
function Disable-AIRegistryKeys {
    Backup-AIRegistryAreas
    foreach($hive in @('HKLM:','HKCU:')) {
        $wai = "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
        Set-RegDword $wai 'DisableAIDataAnalysis' 1
        Set-RegDword $wai 'AllowRecallEnablement' 0
        Set-RegDword $wai 'DisableClickToDo' 1
        Set-RegDword $wai 'TurnOffSavingSnapshots' 1
        Set-RegDword $wai 'DisableSettingsAgent' 1
        Set-RegDword $wai 'DisableAgentConnectors' 1
        Set-RegDword $wai 'DisableAgentWorkspaces' 1
        Set-RegDword $wai 'DisableRemoteAgentConnectors' 1
    }
    foreach($hive in @('HKLM:','HKCU:')) {
        Set-RegDword "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' 1
        Set-RegDword "$hive\SOFTWARE\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
    }
}
function Revert-AIRegistryKeys {
    foreach($hive in @('HKLM:','HKCU:')) {
        $wai = "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
        'DisableAIDataAnalysis','AllowRecallEnablement','DisableClickToDo','TurnOffSavingSnapshots','DisableSettingsAgent','DisableAgentConnectors','DisableAgentWorkspaces','DisableRemoteAgentConnectors' | ForEach-Object { Remove-RegValueSafe $wai $_ }
        Remove-RegValueSafe "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot'
        Remove-RegValueSafe "$hive\SOFTWARE\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions'
    }
}

function Set-JsonAiFlagsDisabled {
    param([object]$Node,[string[]]$Targets)
    $changed = $false
    if($null -eq $Node){ return $false }

    if($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])){
        foreach($item in $Node){ if(Set-JsonAiFlagsDisabled -Node $item -Targets $Targets){ $changed = $true } }
        return $changed
    }

    if($Node -is [pscustomobject]){
        $props = @($Node.PSObject.Properties.Name)
        $idText = ''
        foreach($k in @('id','name','feature','policy','component','key')){
            if($props -contains $k){ $idText += ' ' + [string]$Node.$k }
            if($props -contains ($k.Substring(0,1).ToUpper()+$k.Substring(1))){ $idText += ' ' + [string]$Node.($k.Substring(0,1).ToUpper()+$k.Substring(1)) }
        }
        $isAiTarget = Test-AllowMatch -Text $idText.ToLowerInvariant() -Patterns $Targets
        if($isAiTarget){
            foreach($p in @('enabled','Enabled','isEnabled','IsEnabled')){
                if($props -contains $p -and $Node.$p -eq $true){
                    $Node.$p = $false
                    $changed = $true
                }
            }
        }
        foreach($p in $Node.PSObject.Properties){ if(Set-JsonAiFlagsDisabled -Node $p.Value -Targets $Targets){ $changed = $true } }
    }
    return $changed
}
function Disable-CopilotPoliciesJson {
    $allow = Get-AIAllowlist
    $targets = $allow.JsonPolicyTargets
    $candidates = @(
        Join-Path $env:windir 'System32\IntegratedServicesRegionPolicySet.json',
        Join-Path $env:windir 'SysWOW64\IntegratedServicesRegionPolicySet.json'
    ) | Where-Object { Test-Path $_ }

    foreach($file in $candidates){
        try {
            $raw = Get-Content $file -Raw -ErrorAction Stop
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
            $changed = Set-JsonAiFlagsDisabled -Node $obj -Targets $targets
            if($changed){
                if($DryRun){ Add-PlanItem 'JsonPolicy' $file 'DisableAiFlags' 'WouldDo' }
                else {
                    Copy-Item $file (Join-Path $BackupDir ((Split-Path $file -Leaf) + '.' + (Get-Date -Format yyyyMMdd_HHmmss) + '.bak')) -Force
                    $obj | ConvertTo-Json -Depth 100 | Set-Content -Path $file -Encoding UTF8
                    Add-PlanItem 'JsonPolicy' $file 'DisableAiFlags' 'Done'
                }
            } else {
                Add-PlanItem 'JsonPolicy' $file 'DisableAiFlags' 'Skipped' 'Nenhuma chave alvo encontrada'
            }
        } catch {
            Add-PlanItem 'JsonPolicy' $file 'DisableAiFlags' 'Failed' $_.Exception.Message
            Write-OTILog "Falha ao processar ${file}: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Get-AIAppxPackages {
    $allow = Get-AIAllowlist
    $all = @()
    try { $all += Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue } catch {}
    try { $all += Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue } catch {}

    $all | Where-Object {
        $name = ($_.Name + ' ' + $_.PackageFullName + ' ' + $_.PackageName + ' ' + $_.DisplayName)
        Test-AllowMatch -Text $name -Patterns $allow.AppxPatterns
    } | Sort-Object PackageFullName,PackageName -Unique
}
function Remove-AIAppxPackages {
    $packages = Get-AIAppxPackages
    if(-not $packages){ Add-PlanItem 'Appx' 'All' 'Remove' 'Skipped' 'Nenhum pacote alvo detectado'; return }
    foreach($pkg in $packages){
        $id = if($pkg.PackageFullName){$pkg.PackageFullName}else{$pkg.PackageName}
        if($DryRun){ Add-PlanItem 'Appx' $id 'Remove' 'WouldDo'; continue }
        if($pkg.PackageFullName){ try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue; Add-PlanItem 'Appx' $id 'Remove-AppxPackage' 'Done' } catch { Add-PlanItem 'Appx' $id 'Remove-AppxPackage' 'Failed' $_.Exception.Message } }
        if($pkg.PackageName){ try { Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null; Add-PlanItem 'Appx' $id 'Remove-Provisioned' 'Done' } catch { Add-PlanItem 'Appx' $id 'Remove-Provisioned' 'Failed' $_.Exception.Message } }
        Prevent-AppxPackageReinstall -PackageIdentity $id
    }
}
function Prevent-AppxPackageReinstall {
    param([string]$PackageIdentity)
    if([string]::IsNullOrWhiteSpace($PackageIdentity)){ return }
    $safe = $PackageIdentity -replace '[\\/:*?"<>|]','_'
    $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$safe"
    if($DryRun){ Add-PlanItem 'ReinstallBlock' $safe 'RegistryMark' 'WouldDo'; return }
    try {
        New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $path -Name 'OtimizacaoTI' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Add-PlanItem 'ReinstallBlock' $safe 'RegistryMark' 'Done'
    } catch {
        Add-PlanItem 'ReinstallBlock' $safe 'RegistryMark' 'Failed' $_.Exception.Message
    }
}
function Remove-RecallOptionalFeature {
    $allow = Get-AIAllowlist
    try {
        $features = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object {
            Test-AllowMatch -Text $_.FeatureName -Patterns $allow.OptionalFeaturePatterns
        }
        foreach($f in $features){
            if($DryRun){ Add-PlanItem 'OptionalFeature' $f.FeatureName 'Disable-Remove' 'WouldDo' $f.State; continue }
            Disable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Add-PlanItem 'OptionalFeature' $f.FeatureName 'Disable-Remove' 'Done' $f.State
        }
    } catch {
        Add-PlanItem 'OptionalFeature' 'All' 'Disable-Remove' 'Failed' $_.Exception.Message
    }
}
function Remove-RecallScheduledTasks {
    $allow = Get-AIAllowlist
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $t = ($_.TaskName + ' ' + $_.TaskPath)
            Test-AllowMatch -Text $t -Patterns $allow.TaskPatterns
        } | ForEach-Object {
            $id = "$($_.TaskPath)$($_.TaskName)"
            if($DryRun){ Add-PlanItem 'ScheduledTask' $id 'Unregister' 'WouldDo' }
            else {
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                Add-PlanItem 'ScheduledTask' $id 'Unregister' 'Done'
            }
        }
    } catch {
        Add-PlanItem 'ScheduledTask' 'All' 'Unregister' 'Failed' $_.Exception.Message
    }
}
function Remove-AICBSPackages {
    if(-not (Require-UnsafeDeepApproval)){ return }
    $allow = Get-AIAllowlist
    $out = & dism.exe /Online /Get-Packages /English 2>&1
    Add-Content -Path $LogPath -Value $out -Encoding UTF8
    $ids = $out | Select-String -Pattern 'Package Identity\s*:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } | Where-Object {
        Test-AllowMatch -Text $_ -Patterns $allow.CBSPatterns
    } | Sort-Object -Unique
    foreach($id in $ids){
        if($DryRun){ Add-PlanItem 'CBS' $id 'Remove-Package' 'WouldDo'; continue }
        & dism.exe /Online /Remove-Package /PackageName:$id /NoRestart *> $null
        if($LASTEXITCODE -eq 0){ Add-PlanItem 'CBS' $id 'Remove-Package' 'Done' }
        else { Add-PlanItem 'CBS' $id 'Remove-Package' 'Failed' "Exit=$LASTEXITCODE" }
    }
}
function Remove-AIFiles {
    if(-not (Require-UnsafeDeepApproval)){ return }
    $allow = Get-AIAllowlist
    $roots = @(
        Join-Path $env:windir 'SystemApps',
        Join-Path $env:ProgramFiles 'WindowsApps',
        Join-Path $env:ProgramData 'Microsoft\Windows',
        Join-Path $env:LOCALAPPDATA 'Packages'
    ) | Where-Object { Test-Path $_ }

    foreach($root in $roots){
        Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object {
            Test-AllowMatch -Text $_.Name -Patterns $allow.AppxPatterns
        } | ForEach-Object {
            if($DryRun){ Add-PlanItem 'FileSystem' $_.FullName 'Quarantine/Remove' 'WouldDo' }
            else {
                try {
                    if($PurgeFiles){ Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; Add-PlanItem 'FileSystem' $_.FullName 'Remove' 'Done' }
                    else {
                        $dest = Join-Path $QuarantineDir (($_.FullName -replace '[:\\/ ]','_'))
                        Move-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
                        Add-PlanItem 'FileSystem' $_.FullName 'Quarantine' 'Done' $dest
                    }
                } catch {
                    Add-PlanItem 'FileSystem' $_.FullName 'Quarantine/Remove' 'Failed' $_.Exception.Message
                }
            }
        }
    }
}
function Install-UpdateCleanupTask {
    $taskName = 'OtimizacaoTI_RemoveWindowsAI_UpdateCleanup'
    $actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action PreventReinstall -LogPath `"$LogPath`" -SkipRestorePoint"
    if($DryRun){ Add-PlanItem 'ScheduledTask' $taskName 'Register' 'WouldDo' $actionArgs; return }
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArgs
        $trigger1 = New-ScheduledTaskTrigger -AtStartup
        $trigger2 = New-ScheduledTaskTrigger -Daily -At 12:00
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Force | Out-Null
        Add-PlanItem 'ScheduledTask' $taskName 'Register' 'Done'
    } catch {
        Add-PlanItem 'ScheduledTask' $taskName 'Register' 'Failed' $_.Exception.Message
    }
}
function Prevent-AIPackageReinstall {
    Get-AIAppxPackages | ForEach-Object {
        Prevent-AppxPackageReinstall -PackageIdentity ($(if($_.PackageFullName){$_.PackageFullName}else{$_.PackageName}))
    }
    Install-UpdateCleanupTask
}
function Diagnose-AI {
    Write-OTILog '===== DIAGNOSTICO DE RECURSOS DE IA ====='
    $pkgs = Get-AIAppxPackages
    if($pkgs){ $pkgs | ForEach-Object { Add-PlanItem 'Diagnose' 'AppxTarget' 'Detect' 'Done' ($(if($_.PackageFullName){$_.PackageFullName}else{$_.PackageName})) } }
    else { Add-PlanItem 'Diagnose' 'AppxTarget' 'Detect' 'Skipped' 'Nenhum pacote alvo' }
    Write-OTILog '===== FIM DIAGNOSTICO DE IA ====='
}

Assert-Admin
Assert-WindowsPowerShell51
Write-OTILog "Modulo IA iniciado. Action=$Action DryRun=$DryRun UnsafeDeepActions=$UnsafeDeepActions"

switch($Action){
    'Diagnose' { Diagnose-AI }
    'DisablePolicies' { New-OTIRestorePoint; Disable-AIRegistryKeys; Disable-CopilotPoliciesJson; Diagnose-AI }
    'RemoveAppxAndRecall' { if(-not $DryRun){ Require-StrongConfirmation 'RemoveAppxAndRecall' }; New-OTIRestorePoint; Disable-AIRegistryKeys; Disable-CopilotPoliciesJson; Remove-RecallOptionalFeature; Remove-RecallScheduledTasks; Remove-AIAppxPackages; Prevent-AIPackageReinstall; Diagnose-AI }
    'RemoveDeep' { if(-not $DryRun){ Require-StrongConfirmation 'RemoveDeep' }; New-OTIRestorePoint; Remove-AICBSPackages; Remove-AIFiles; Prevent-AIPackageReinstall; Diagnose-AI }
    'PreventReinstall' { Prevent-AIPackageReinstall; Diagnose-AI }
    'All' { if(-not $DryRun){ Require-StrongConfirmation 'All' }; New-OTIRestorePoint; Disable-AIRegistryKeys; Disable-CopilotPoliciesJson; Remove-RecallOptionalFeature; Remove-RecallScheduledTasks; Remove-AIAppxPackages; Remove-AICBSPackages; Remove-AIFiles; Prevent-AIPackageReinstall; Diagnose-AI }
    'RevertPolicies' { New-OTIRestorePoint; Revert-AIRegistryKeys; Diagnose-AI }
}

Write-PlanReport
Write-OTILog "Modulo IA finalizado. Action=$Action" 'OK'

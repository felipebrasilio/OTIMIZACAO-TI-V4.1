<#
.SYNOPSIS
    Inventario Corporativo N3 LIVE V4 - Painel web local com inventario, acoes administrativas e otimizacao.

.DESCRIPTION
    Inicia um servidor HTTP local em PowerShell para exibir inventario em tempo real e executar acoes administrativas:
    - Atualizar inventario local/remoto
    - Abrir admin share \\HOST\C$
    - Reiniciar/desligar computador
    - Listar usuarios, perfis e sessoes
    - Matar/reiniciar processos
    - Iniciar/parar/reiniciar servicos
    - Desinstalar software
    - Desinstalar software com limpeza segura de residuos
    - Executar modulos de otimizacao: limpeza, performance, rede, impressora e completo

.NOTAS
    Execute como Administrador.
    URL padrao: http://127.0.0.1:8787/
#>

[CmdletBinding()]
param(
    [int]$Porta = 8787,
    [string]$OutputPath = "C:\Inventario",
    [switch]$NaoAbrirNavegador
)

$ErrorActionPreference = "Stop"

function Test-Admin {
    try {
        $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identidade)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function New-Pasta {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) {
        New-Item -Path $Caminho -ItemType Directory -Force | Out-Null
    }
}

function Send-Http {
    param(
        [System.Net.HttpListenerContext]$Contexto,
        [string]$Conteudo,
        [string]$ContentType = "application/json; charset=utf-8",
        [int]$StatusCode = 200
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Conteudo)
    $Contexto.Response.StatusCode = $StatusCode
    $Contexto.Response.ContentType = $ContentType
    $Contexto.Response.ContentLength64 = $bytes.Length
    $Contexto.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Contexto.Response.OutputStream.Close()
}

function ConvertTo-JsonSeguro {
    param($Objeto)
    try { return ($Objeto | ConvertTo-Json -Depth 24 -Compress) }
    catch { return (@{ erro = $_.Exception.Message } | ConvertTo-Json -Compress) }
}

function Get-QueryParams {
    param([string]$Query)
    $hash = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) { return $hash }
    foreach ($par in $Query.TrimStart("?").Split("&")) {
        if ([string]::IsNullOrWhiteSpace($par)) { continue }
        $partes = $par.Split("=", 2)
        $chave = [System.Uri]::UnescapeDataString($partes[0])
        $valor = ""
        if ($partes.Count -gt 1) { $valor = [System.Uri]::UnescapeDataString($partes[1].Replace("+", " ")) }
        $hash[$chave] = $valor
    }
    return $hash
}

function Get-BodyJson {
    param([System.Net.HttpListenerRequest]$Request)
    try {
        $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
        $body = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($body)) { return [pscustomobject]@{} }
        return ($body | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{}
    }
}

function Get-PortaDisponivel {
    param([int]$PortaInicial)
    for ($p = $PortaInicial; $p -lt ($PortaInicial + 60); $p++) {
        try {
            $listenerTeste = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $p)
            $listenerTeste.Start()
            $listenerTeste.Stop()
            return $p
        }
        catch {}
    }
    throw "Nenhuma porta disponivel encontrada a partir de $PortaInicial."
}

$ScriptInventario = {
    param([string]$Alvo)

    $ErrorActionPreference = "SilentlyContinue"

    function Emitir-Progresso {
        param([int]$Percentual, [string]$Etapa)
        [pscustomobject]@{
            __tipo = "progresso"
            Percentual = $Percentual
            Etapa = $Etapa
            DataHora = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    function Emitir-Resultado {
        param($Dados)
        [pscustomobject]@{
            __tipo = "resultado"
            Dados = $Dados
        }
    }

    function Add-Erro {
        param([ref]$Lista, [string]$Secao, [string]$Erro)
        $atual = @()
        if ($null -ne $Lista.Value) { $atual = @($Lista.Value) }
        $atual += [pscustomobject]@{ Secao = $Secao; Erro = $Erro; DataHora = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
        $Lista.Value = $atual
    }

    function Test-Local {
        param([string]$Nome)
        if ([string]::IsNullOrWhiteSpace($Nome)) { return $true }
        $possiveis = @(".", "localhost", "127.0.0.1", "::1", $env:COMPUTERNAME)
        try { $possiveis += [System.Net.Dns]::GetHostName() } catch {}
        return ($possiveis -contains $Nome)
    }

    function Normalize-Alvo {
        param([string]$Nome)

        if ([string]::IsNullOrWhiteSpace($Nome)) { return $env:COMPUTERNAME }

        $n = $Nome.Trim()
        $n = $n -replace "^[\\/]+", ""
        if ($n -match "\\") { $n = ($n -split "\\")[0] }
        if ($n -match "/") { $n = ($n -split "/")[0] }
        $n = $n.Trim()

        if ([string]::IsNullOrWhiteSpace($n)) { return $env:COMPUTERNAME }
        return $n
    }

    function Ensure-TrustedHostLocal {
        param([string]$HostAlvo)
        try {
            if ([string]::IsNullOrWhiteSpace($HostAlvo)) { return $false }
            $isIp = [bool]([System.Net.IPAddress]::TryParse($HostAlvo, [ref]([System.Net.IPAddress]$null)))
            if (-not $isIp) { return $false }
            $cur = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
            if ([string]::IsNullOrWhiteSpace($cur)) {
                Set-Item WSMan:\localhost\Client\TrustedHosts -Value $HostAlvo -Force -ErrorAction SilentlyContinue
                return $true
            }
            if ($cur -notmatch "(^|,)\Q$HostAlvo\E($|,)") {
                Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($cur + "," + $HostAlvo) -Force -ErrorAction SilentlyContinue
                return $true
            }
        } catch {}
        return $false
    }

    function Format-Bytes {
        param([Nullable[double]]$Bytes)
        if ($null -eq $Bytes) { return "N/D" }
        if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
        if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "{0:N0} B" -f $Bytes
    }

    function Convert-InstallDate {
        param($Valor)
        if ($null -eq $Valor -or "$Valor".Trim() -eq "") { return "N/D" }
        $texto = [string]$Valor
        if ($texto -match "^\d{8}$") {
            try { return ([datetime]::ParseExact($texto, "yyyyMMdd", $null)).ToString("dd/MM/yyyy") } catch { return $texto }
        }
        return $texto
    }

    function Convert-DigitalProductIdParaChave {
        param([byte[]]$DigitalProductId)
        try {
            if ($null -eq $DigitalProductId -or $DigitalProductId.Length -lt 67) { return "N/D" }
            $keyOffset = 52
            $chars = "BCDFGHJKMPQRTVWXY2346789"
            $chave = ""
            for ($i = 24; $i -ge 0; $i--) {
                $cur = 0
                for ($j = 14; $j -ge 0; $j--) {
                    $cur = ($cur * 256) -bxor $DigitalProductId[$j + $keyOffset]
                    $DigitalProductId[$j + $keyOffset] = [math]::Floor($cur / 24)
                    $cur = $cur % 24
                }
                $chave = $chars[$cur] + $chave
            }
            $partes = @()
            for ($i = 0; $i -lt 25; $i += 5) { $partes += $chave.Substring($i, 5) }
            return ($partes -join "-")
        }
        catch { return "N/D" }
    }

    function Get-ChaveWindowsLocal {
        $resultado = [ordered]@{
            ProductName = "N/D"
            ProductId = "N/D"
            ChaveWindows = "N/D"
            OrigemChave = "N/D"
            CanalLicenca = "N/D"
        }

        try {
            $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
            if ($reg.ProductName) { $resultado.ProductName = $reg.ProductName }
            if ($reg.ProductId) { $resultado.ProductId = $reg.ProductId }
            if ($reg.DigitalProductId) {
                $resultado.ChaveWindows = Convert-DigitalProductIdParaChave -DigitalProductId ([byte[]]$reg.DigitalProductId)
                $resultado.OrigemChave = "Registro DigitalProductId"
            }
        }
        catch {}

        try {
            $sl = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
            if ($sl.OA3xOriginalProductKey) {
                $resultado.ChaveWindows = $sl.OA3xOriginalProductKey
                $resultado.OrigemChave = "BIOS/UEFI OA3xOriginalProductKey"
            }
        }
        catch {}

        try {
            $produto = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
                Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 } |
                Select-Object -First 1
            if ($produto) { $resultado.CanalLicenca = $produto.Description }
        }
        catch {}

        return [pscustomobject]$resultado
    }

    function Get-CimLocal {
        param([string]$ClassName, [string]$Namespace = "root/cimv2", [string]$Filter = "")
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = "Stop" }
        if ($Filter) { $params.Filter = $Filter }
        return Get-CimInstance @params
    }

    function Get-SoftwareInstaladoLocal {
        $paths = @(
            [pscustomobject]@{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arquitetura = "64 bits/nativo"; Escopo = "Maquina" },
            [pscustomobject]@{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arquitetura = "32 bits"; Escopo = "Maquina" },
            [pscustomobject]@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Arquitetura = "Usuario"; Escopo = "Usuario atual" }
        )

        $lista = foreach ($item in $paths) {
            try {
                if (Test-Path $item.Path) {
                    Get-ItemProperty -Path $item.Path -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -and "$($_.DisplayName)".Trim() -ne "" } |
                        ForEach-Object {
                            [pscustomobject]@{
                                Nome = $_.DisplayName
                                Versao = if ($_.DisplayVersion) { $_.DisplayVersion } else { "N/D" }
                                Fabricante = if ($_.Publisher) { $_.Publisher } else { "N/D" }
                                DataInstalacao = Convert-InstallDate $_.InstallDate
                                Arquitetura = $item.Arquitetura
                                Escopo = $item.Escopo
                                InstallLocation = if ($_.InstallLocation) { $_.InstallLocation } else { "N/D" }
                                UninstallString = if ($_.UninstallString) { $_.UninstallString } else { "N/D" }
                                QuietUninstallString = if ($_.QuietUninstallString) { $_.QuietUninstallString } else { "N/D" }
                                Registro = $_.PSPath
                            }
                        }
                }
            }
            catch {}
        }

        return @($lista | Sort-Object Nome, Versao, Fabricante -Unique)
    }

    function Get-UsuariosLocal {
        $resultado = [ordered]@{
            UsuariosLocais = @()
            Perfis = @()
            Sessoes = @()
            GruposAdministradores = @()
        }

        try {
            $resultado.UsuariosLocais = @(Get-LocalUser -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Nome = $_.Name
                    NomeCompleto = $_.FullName
                    Habilitado = $_.Enabled
                    UltimoLogon = $_.LastLogon
                    Expira = $_.AccountExpires
                    PasswordRequired = $_.PasswordRequired
                    PasswordLastSet = $_.PasswordLastSet
                    SID = $_.SID.Value
                    Descricao = $_.Description
                }
            })
        }
        catch {
            try {
                $resultado.UsuariosLocais = @(Get-CimLocal -ClassName Win32_UserAccount -Filter "LocalAccount=True" | ForEach-Object {
                    [pscustomobject]@{
                        Nome = $_.Name
                        NomeCompleto = $_.FullName
                        Habilitado = -not $_.Disabled
                        UltimoLogon = "N/D"
                        Expira = "N/D"
                        PasswordRequired = "N/D"
                        PasswordLastSet = "N/D"
                        SID = $_.SID
                        Descricao = $_.Description
                    }
                })
            }
            catch {}
        }

        try {
            $resultado.Perfis = @(Get-CimLocal -ClassName Win32_UserProfile | ForEach-Object {
                [pscustomobject]@{
                    SID = $_.SID
                    Caminho = $_.LocalPath
                    Carregado = $_.Loaded
                    Especial = $_.Special
                    UltimoUso = $_.LastUseTime
                    Status = $_.Status
                }
            })
        }
        catch {}

        try {
            $linhas = @(quser 2>$null)
            if ($linhas.Count -gt 1) {
                $resultado.Sessoes = @($linhas | Select-Object -Skip 1 | ForEach-Object {
                    $linha = ($_ -replace "^\s+", "") -replace "\s{2,}", "|"
                    $partes = $linha.Split("|")
                    [pscustomobject]@{
                        Usuario = if ($partes.Count -gt 0) { $partes[0].TrimStart(">") } else { "N/D" }
                        Sessao = if ($partes.Count -gt 1) { $partes[1] } else { "N/D" }
                        ID = if ($partes.Count -gt 2) { $partes[2] } else { "N/D" }
                        Estado = if ($partes.Count -gt 3) { $partes[3] } else { "N/D" }
                        Ocioso = if ($partes.Count -gt 4) { $partes[4] } else { "N/D" }
                        Logon = if ($partes.Count -gt 5) { $partes[5] } else { "N/D" }
                    }
                })
            }
        }
        catch {}

        try {
            $grupoAdmin = $null
            try { $grupoAdmin = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop } catch {}
            if ($grupoAdmin) {
                $resultado.GruposAdministradores = @(Get-LocalGroupMember -Group $grupoAdmin.Name -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{ Nome = $_.Name; Tipo = $_.ObjectClass; Origem = $_.PrincipalSource; SID = $_.SID.Value }
                })
            }
        }
        catch {}

        return [pscustomobject]$resultado
    }

    function Get-SegurancaLocal {
        $resultado = [ordered]@{
            Defender = @()
            BitLocker = @()
            TPM = @()
            SecureBoot = @()
            Firewall = @()
            RDP = @()
            Compartilhamentos = @()
        }

        try {
            $def = Get-MpComputerStatus -ErrorAction Stop
            $resultado.Defender = @([pscustomobject]@{
                AntivirusAtivo = $def.AntivirusEnabled
                TempoReal = $def.RealTimeProtectionEnabled
                ServicoAtivo = $def.AMServiceEnabled
                Assinatura = $def.AntivirusSignatureVersion
                AtualizacaoAssinatura = $def.AntivirusSignatureLastUpdated
                Status = if ($def.AntivirusEnabled -and $def.RealTimeProtectionEnabled) { "OK" } else { "Atencao" }
            })
        }
        catch { $resultado.Defender = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $resultado.BitLocker = @(Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Volume = $_.MountPoint
                    Protecao = $_.ProtectionStatus
                    StatusVolume = $_.VolumeStatus
                    CriptografiaPercentual = $_.EncryptionPercentage
                    Metodo = $_.EncryptionMethod
                    Status = if ($_.ProtectionStatus -eq "On") { "OK" } else { "Atencao" }
                }
            })
        }
        catch { $resultado.BitLocker = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $tpm = Get-Tpm -ErrorAction Stop
            $resultado.TPM = @([pscustomobject]@{
                Presente = $tpm.TpmPresent
                Pronto = $tpm.TpmReady
                Habilitado = $tpm.TpmEnabled
                Fabricante = $tpm.ManufacturerIdTxt
                Status = if ($tpm.TpmPresent -and $tpm.TpmReady) { "OK" } else { "Atencao" }
            })
        }
        catch { $resultado.TPM = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $sb = Confirm-SecureBootUEFI -ErrorAction Stop
            $resultado.SecureBoot = @([pscustomobject]@{ SecureBootAtivo = $sb; Status = if ($sb) { "OK" } else { "Atencao" } })
        }
        catch { $resultado.SecureBoot = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $resultado.Firewall = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Perfil = $_.Name
                    Ativo = $_.Enabled
                    EntradaPadrao = $_.DefaultInboundAction
                    SaidaPadrao = $_.DefaultOutboundAction
                    Status = if ($_.Enabled) { "OK" } else { "Critico" }
                }
            })
        }
        catch { $resultado.Firewall = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $rdp = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop
            $habilitado = ($rdp.fDenyTSConnections -eq 0)
            $resultado.RDP = @([pscustomobject]@{ RDPHabilitado = $habilitado; Status = if ($habilitado) { "Atencao" } else { "OK" } })
        }
        catch { $resultado.RDP = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $resultado.Compartilhamentos = @(Get-CimInstance -ClassName Win32_Share -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Nome = $_.Name
                    Caminho = $_.Path
                    Descricao = $_.Description
                    Administrativo = if ($_.Name -match "\$$") { "Sim" } else { "Nao" }
                }
            })
        }
        catch { $resultado.Compartilhamentos = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        return [pscustomobject]$resultado
    }

    function Get-PatchesLocal {
        $resultado = [ordered]@{ Hotfixes = @(); RebootPendente = @(); ServicosAtualizacao = @() }

        try {
            $resultado.Hotfixes = @(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 30 | ForEach-Object {
                [pscustomobject]@{ HotFixID = $_.HotFixID; Descricao = $_.Description; InstaladoPor = $_.InstalledBy; InstaladoEm = $_.InstalledOn }
            })
        }
        catch { $resultado.Hotfixes = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $motivos = New-Object System.Collections.Generic.List[string]
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $motivos.Add("Component Based Servicing") }
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $motivos.Add("Windows Update") }
            try {
                $sess = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction Stop
                if ($sess.PendingFileRenameOperations) { $motivos.Add("PendingFileRenameOperations") }
            }
            catch {}
            $pendente = $motivos.Count -gt 0
            $resultado.RebootPendente = @([pscustomobject]@{
                Pendente = $pendente
                Motivos = if ($pendente) { $motivos -join ", " } else { "Nenhum indicio encontrado" }
                Status = if ($pendente) { "Atencao" } else { "OK" }
            })
        }
        catch { $resultado.RebootPendente = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        try {
            $nomes = @("wuauserv", "bits", "eventlog", "UsoSvc")
            $resultado.ServicosAtualizacao = @(Get-Service -Name $nomes -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{ Nome = $_.Name; DisplayName = $_.DisplayName; StatusServico = $_.Status; Status = if ($_.Status -eq "Running") { "OK" } else { "Atencao" } }
            })
        }
        catch { $resultado.ServicosAtualizacao = @([pscustomobject]@{ Status = "N/D"; Detalhe = $_.Exception.Message }) }

        return [pscustomobject]$resultado
    }

    function Get-EventosLocal {
        param([int]$Horas = 72)
        $inicio = (Get-Date).AddHours(-1 * $Horas)
        $eventos = New-Object System.Collections.Generic.List[object]
        foreach ($log in @("System", "Application")) {
            try {
                $itens = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1,2; StartTime = $inicio } -MaxEvents 250 -ErrorAction Stop
                foreach ($item in $itens) {
                    $msg = ($item.Message -replace "`r|`n", " ") -replace "\s+", " "
                    if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 220) + "..." }
                    $eventos.Add([pscustomobject]@{
                        Log = $log
                        Nivel = if ($item.Level -eq 1) { "Critico" } elseif ($item.Level -eq 2) { "Erro" } else { $item.LevelDisplayName }
                        Origem = $item.ProviderName
                        EventID = $item.Id
                        DataHora = $item.TimeCreated
                        Mensagem = $msg
                    })
                }
            }
            catch {
                $eventos.Add([pscustomobject]@{ Log = $log; Nivel = "N/D"; Origem = "N/D"; EventID = "N/D"; DataHora = Get-Date; Mensagem = $_.Exception.Message })
            }
        }
        return @($eventos | Sort-Object DataHora -Descending | Select-Object -First 150)
    }

    function Get-Score {
        param($Dados)
        $score = 100
        $motivos = New-Object System.Collections.Generic.List[string]
        try { if (@($Dados.Armazenamento.Volumes | Where-Object { $_.LivrePercentualNumero -ne $null -and $_.LivrePercentualNumero -lt 10 }).Count -gt 0) { $score -= 20; $motivos.Add("Disco com menos de 10% livre") } } catch {}
        try { $def = @($Dados.Seguranca.Defender | Select-Object -First 1); if ($def.Status -eq "Atencao" -or $def.Status -eq "Critico") { $score -= 15; $motivos.Add("Defender com alerta") } } catch {}
        try { if (@($Dados.Seguranca.Firewall | Where-Object { $_.Status -eq "Critico" }).Count -gt 0) { $score -= 10; $motivos.Add("Firewall desativado") } } catch {}
        try { $reboot = @($Dados.Patches.RebootPendente | Select-Object -First 1); if ($reboot.Pendente -eq $true) { $score -= 10; $motivos.Add("Reboot pendente") } } catch {}
        try { $sis = @($Dados.Sistema | Select-Object -First 1); if ($sis.UptimeDias -gt 30) { $score -= 10; $motivos.Add("Uptime superior a 30 dias") } } catch {}
        try { if (@($Dados.Eventos | Where-Object { $_.Nivel -eq "Critico" }).Count -gt 0) { $score -= 10; $motivos.Add("Eventos criticos recentes") } } catch {}
        try { if (@($Dados.Servicos.AutomaticosParados).Count -gt 0) { $score -= 10; $motivos.Add("Servicos automaticos parados") } } catch {}
        if ($score -lt 0) { $score = 0 }
        $status = if ($score -ge 80) { "OK" } elseif ($score -ge 60) { "Atencao" } else { "Critico" }
        if ($motivos.Count -eq 0) { $motivos.Add("Nenhum alerta relevante identificado") }
        [pscustomobject]@{ Score = $score; Status = $status; Motivos = ($motivos -join "; ") }
    }

    $ColetorLocal = {
        $erros = @()
        $errosRef = [ref]$erros
        $inicio = Get-Date

        $sistema = @()
        $hardwareBase = @()
        $processador = @()
        $memoriaResumo = @()
        $memoriaSlots = @()
        $video = @()
        $monitores = @()
        $usbDispositivos = @()
        $tipoEquipamento = @()
        $discos = @()
        $volumes = @()
        $redeIp = @()
        $adaptadores = @()
        $software = @()
        $servicosAtivos = @()
        $servicosParados = @()
        $processosTop = @()
        $usuarios = [pscustomobject]@{ UsuariosLocais=@(); Perfis=@(); Sessoes=@(); GruposAdministradores=@() }
        $seguranca = [pscustomobject]@{ Defender=@(); BitLocker=@(); TPM=@(); SecureBoot=@(); Firewall=@(); RDP=@(); Compartilhamentos=@() }
        $patches = [pscustomobject]@{ Hotfixes=@(); RebootPendente=@(); ServicosAtualizacao=@() }
        $eventos = @()

        try {
            $os = Get-CimLocal -ClassName Win32_OperatingSystem
            $cs = Get-CimLocal -ClassName Win32_ComputerSystem
            $uptime = if ($os.LastBootUpTime) { New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date) } else { $null }
            $sistema = @([pscustomobject]@{
                Computador = $os.CSName
                DominioOuWorkgroup = $cs.Domain
                ParteDeDominio = $cs.PartOfDomain
                Sistema = $os.Caption
                Versao = $os.Version
                Build = $os.BuildNumber
                Arquitetura = $os.OSArchitecture
                Instalacao = $os.InstallDate
                UltimoBoot = $os.LastBootUpTime
                Uptime = if ($uptime) { "{0} dias, {1} horas, {2} minutos" -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { "N/D" }
                UptimeDias = if ($uptime) { [int]$uptime.TotalDays } else { 0 }
                UsuarioLogado = $cs.UserName
                ChaveWindows = (Get-ChaveWindowsLocal).ChaveWindows
                ProductId = (Get-ChaveWindowsLocal).ProductId
                OrigemChaveWindows = (Get-ChaveWindowsLocal).OrigemChave
                CanalLicenca = (Get-ChaveWindowsLocal).CanalLicenca
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Sistema" -Erro $_.Exception.Message }

        try {
            $cs = Get-CimLocal -ClassName Win32_ComputerSystem
            $bios = Get-CimLocal -ClassName Win32_BIOS
            $bb = Get-CimLocal -ClassName Win32_BaseBoard
            $produto = Get-CimLocal -ClassName Win32_ComputerSystemProduct
            $isVm = ($cs.Model -match "Virtual|VMware|VirtualBox|KVM|Hyper-V|QEMU" -or $cs.Manufacturer -match "VMware|VirtualBox|QEMU|Xen")
            $hardwareBase = @([pscustomobject]@{
                Fabricante = $cs.Manufacturer
                Modelo = $cs.Model
                Tipo = if ($isVm) { "Virtual" } else { "Fisico" }
                Serial = $bios.SerialNumber
                UUID = $produto.UUID
                BIOS = $bios.SMBIOSBIOSVersion
                BIOSData = $bios.ReleaseDate
                PlacaMae = "$($bb.Manufacturer) $($bb.Product)"
                PlacaMaeSerial = $bb.SerialNumber
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Hardware Base" -Erro $_.Exception.Message }

        try {
            $processador = @(Get-CimLocal -ClassName Win32_Processor | ForEach-Object {
                [pscustomobject]@{ Nome=$_.Name; Fabricante=$_.Manufacturer; Nucleos=$_.NumberOfCores; Threads=$_.NumberOfLogicalProcessors; ClockMHz=$_.MaxClockSpeed; Socket=$_.SocketDesignation; VirtualizacaoFirmware=$_.VirtualizationFirmwareEnabled }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Processador" -Erro $_.Exception.Message }

        try {
            $modulos = @(Get-CimLocal -ClassName Win32_PhysicalMemory | ForEach-Object {
                [pscustomobject]@{ Banco=$_.BankLabel; Slot=$_.DeviceLocator; Fabricante=$_.Manufacturer; PartNumber=$_.PartNumber; Serial=$_.SerialNumber; Capacidade=(Format-Bytes $_.Capacity); CapacidadeBytes=$_.Capacity; VelocidadeMHz=$_.Speed }
            })
            $arrays = @(Get-CimLocal -ClassName Win32_PhysicalMemoryArray)
            $slotsTotais = ($arrays | Measure-Object -Property MemoryDevices -Sum).Sum
            if (-not $slotsTotais) { $slotsTotais = $modulos.Count }
            $totalBytes = ($modulos | Measure-Object -Property CapacidadeBytes -Sum).Sum
            $memoriaResumo = @([pscustomobject]@{ Total=(Format-Bytes $totalBytes); SlotsTotais=$slotsTotais; SlotsUsados=$modulos.Count; SlotsVazios=[math]::Max(0, $slotsTotais - $modulos.Count) })
            $memoriaSlots = $modulos
        } catch { Add-Erro -Lista $errosRef -Secao "Memoria" -Erro $_.Exception.Message }

        try {
            $video = @(Get-CimLocal -ClassName Win32_VideoController | ForEach-Object {
                [pscustomobject]@{ Nome=$_.Name; Driver=$_.DriverVersion; Memoria=if($_.AdapterRAM){Format-Bytes $_.AdapterRAM}else{"N/D"}; Resolucao="$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"; Status=$_.Status }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Video" -Erro $_.Exception.Message }

        try {
            $monitorMap = @{}
            try {
                $wmiMon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
                foreach ($m in $wmiMon) {
                    $inst = [string]$m.InstanceName
                    $serial = (($m.SerialNumberID | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $marca = (($m.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $modelo = (($m.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $monitorMap[$inst] = [pscustomobject]@{
                        Marca  = if ($marca) { $marca } else { "N/D" }
                        Modelo = if ($modelo) { $modelo } else { "N/D" }
                        Serie  = if ($serial) { $serial } else { "N/D" }
                    }
                }
            } catch {}
            $monitores = @(Get-CimLocal -ClassName Win32_DesktopMonitor | ForEach-Object {
                $inst = [string]$_.PNPDeviceID
                $meta = $null
                foreach ($k in $monitorMap.Keys) { if ($k -like "*$inst*") { $meta = $monitorMap[$k]; break } }
                [pscustomobject]@{
                    Nome        = if ($_.Name) { $_.Name } else { "N/D" }
                    Marca       = if ($meta) { $meta.Marca } else { "N/D" }
                    Modelo      = if ($meta) { $meta.Modelo } else { "N/D" }
                    Serie       = if ($meta) { $meta.Serie } else { "N/D" }
                    PNPDeviceID = if ($_.PNPDeviceID) { $_.PNPDeviceID } else { "N/D" }
                    Status      = if ($_.Status) { $_.Status } else { "N/D" }
                }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Monitores" -Erro $_.Exception.Message }

        try {
            $usbDispositivos = @(Get-CimLocal -ClassName Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like "USB\\*" } | Select-Object -First 400 | ForEach-Object {
                [pscustomobject]@{
                    Nome       = if ($_.Name) { $_.Name } else { "N/D" }
                    Tipo       = if ($_.PNPClass) { $_.PNPClass } elseif ($_.ClassGuid) { $_.ClassGuid } else { "N/D" }
                    Fabricante = if ($_.Manufacturer) { $_.Manufacturer } else { "N/D" }
                    DeviceID   = if ($_.DeviceID) { $_.DeviceID } else { "N/D" }
                    Status     = if ($_.Status) { $_.Status } else { "N/D" }
                }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "USB" -Erro $_.Exception.Message }

        try {
            $enc = Get-CimLocal -ClassName Win32_SystemEnclosure | Select-Object -First 1
            $cts = @($enc.ChassisTypes)
            $isNotebook = $false
            foreach ($ct in $cts) { if ($ct -in @(8,9,10,11,14,18,21,30,31,32)) { $isNotebook = $true; break } }
            $tipoEquipamento = @([pscustomobject]@{
                TipoEquipamento = if ($isNotebook) { "Notebook" } else { "Desktop" }
                ChassisTypes    = if ($cts.Count -gt 0) { ($cts -join ", ") } else { "N/D" }
                Fabricante      = if ($enc.Manufacturer) { $enc.Manufacturer } else { "N/D" }
                Serial          = if ($enc.SerialNumber) { $enc.SerialNumber } else { "N/D" }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Tipo Equipamento" -Erro $_.Exception.Message }

        try {
            $monitorMap = @{}
            try {
                $wmiMon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
                foreach ($m in $wmiMon) {
                    $inst = [string]$m.InstanceName
                    $serial = (($m.SerialNumberID | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $marca = (($m.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $modelo = (($m.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join "").Trim()
                    $monitorMap[$inst] = [pscustomobject]@{
                        Marca  = if ($marca) { $marca } else { "N/D" }
                        Modelo = if ($modelo) { $modelo } else { "N/D" }
                        Serie  = if ($serial) { $serial } else { "N/D" }
                    }
                }
            } catch {}

            $monitores = @(Get-CimLocal -ClassName Win32_DesktopMonitor | ForEach-Object {
                $inst = [string]$_.PNPDeviceID
                $meta = $null
                foreach ($k in $monitorMap.Keys) {
                    if ($k -like "*$inst*") { $meta = $monitorMap[$k]; break }
                }
                [pscustomobject]@{
                    Nome        = if ($_.Name) { $_.Name } else { "N/D" }
                    Marca       = if ($meta) { $meta.Marca } else { "N/D" }
                    Modelo      = if ($meta) { $meta.Modelo } else { "N/D" }
                    Serie       = if ($meta) { $meta.Serie } else { "N/D" }
                    PNPDeviceID = if ($_.PNPDeviceID) { $_.PNPDeviceID } else { "N/D" }
                    Status      = if ($_.Status) { $_.Status } else { "N/D" }
                }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Monitores" -Erro $_.Exception.Message }

        try {
            $usbDispositivos = @(Get-CimLocal -ClassName Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like "USB\\*" } | Select-Object -First 400 | ForEach-Object {
                [pscustomobject]@{
                    Nome       = if ($_.Name) { $_.Name } else { "N/D" }
                    Tipo       = if ($_.PNPClass) { $_.PNPClass } elseif ($_.ClassGuid) { $_.ClassGuid } else { "N/D" }
                    Fabricante = if ($_.Manufacturer) { $_.Manufacturer } else { "N/D" }
                    DeviceID   = if ($_.DeviceID) { $_.DeviceID } else { "N/D" }
                    Status     = if ($_.Status) { $_.Status } else { "N/D" }
                }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "USB" -Erro $_.Exception.Message }

        try {
            $enc = Get-CimLocal -ClassName Win32_SystemEnclosure | Select-Object -First 1
            $cts = @($enc.ChassisTypes)
            $isNotebook = $false
            foreach ($ct in $cts) { if ($ct -in @(8,9,10,11,14,18,21,30,31,32)) { $isNotebook = $true; break } }
            $tipoEquipamento = @([pscustomobject]@{
                TipoEquipamento = if ($isNotebook) { "Notebook" } else { "Desktop" }
                ChassisTypes    = if ($cts.Count -gt 0) { ($cts -join ", ") } else { "N/D" }
                Fabricante      = if ($enc.Manufacturer) { $enc.Manufacturer } else { "N/D" }
                Serial          = if ($enc.SerialNumber) { $enc.SerialNumber } else { "N/D" }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Tipo Equipamento" -Erro $_.Exception.Message }

        try {
            $discos = @(Get-CimLocal -ClassName Win32_DiskDrive | ForEach-Object {
                [pscustomobject]@{ Modelo=$_.Model; Serial=$_.SerialNumber; Interface=$_.InterfaceType; Midia=$_.MediaType; Tamanho=(Format-Bytes $_.Size); Particoes=$_.Partitions; Status=$_.Status }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Discos" -Erro $_.Exception.Message }

        try {
            $volumes = @(Get-CimLocal -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                $pct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { $null }
                [pscustomobject]@{ Unidade=$_.DeviceID; Volume=$_.VolumeName; SistemaArquivos=$_.FileSystem; Tamanho=(Format-Bytes $_.Size); Livre=(Format-Bytes $_.FreeSpace); LivrePercentual=if($null -ne $pct){"$pct%"}else{"N/D"}; LivrePercentualNumero=$pct; Status=if($null -ne $pct -and $pct -lt 10){"Critico"}elseif($null -ne $pct -and $pct -lt 20){"Atencao"}else{"OK"} }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Volumes" -Erro $_.Exception.Message }

        try {
            $redeIp = @(Get-CimLocal -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | ForEach-Object {
                [pscustomobject]@{ Descricao=$_.Description; MAC=$_.MACAddress; DHCP=$_.DHCPEnabled; IP=($_.IPAddress -join ", "); Mascara=($_.IPSubnet -join ", "); Gateway=($_.DefaultIPGateway -join ", "); DNS=($_.DNSServerSearchOrder -join ", "); DominioDNS=$_.DNSDomain }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Rede IP" -Erro $_.Exception.Message }

        try {
            $adaptadores = @(Get-CimLocal -ClassName Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true } | ForEach-Object {
                [pscustomobject]@{ Nome=$_.Name; Fabricante=$_.Manufacturer; MAC=$_.MACAddress; Conexao=$_.NetConnectionID; Status=$_.NetConnectionStatus; Velocidade=if($_.Speed){Format-Bytes $_.Speed}else{"N/D"}; Ativo=$_.NetEnabled }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Adaptadores" -Erro $_.Exception.Message }

        try { $software = @(Get-SoftwareInstaladoLocal) } catch { Add-Erro -Lista $errosRef -Secao "Software" -Erro $_.Exception.Message }
        try { $usuarios = Get-UsuariosLocal } catch { Add-Erro -Lista $errosRef -Secao "Usuarios" -Erro $_.Exception.Message }
        try { $seguranca = Get-SegurancaLocal } catch { Add-Erro -Lista $errosRef -Secao "Seguranca" -Erro $_.Exception.Message }
        try { $patches = Get-PatchesLocal } catch { Add-Erro -Lista $errosRef -Secao "Patches" -Erro $_.Exception.Message }
        try { $eventos = @(Get-EventosLocal -Horas 72) } catch { Add-Erro -Lista $errosRef -Secao "Eventos" -Erro $_.Exception.Message }

        try {
            $servicosAtivos = @(Get-CimLocal -ClassName Win32_Service -Filter "State='Running'" | Sort-Object DisplayName | Select-Object -First 300 | ForEach-Object {
                [pscustomobject]@{ Nome=$_.Name; DisplayName=$_.DisplayName; Estado=$_.State; StartMode=$_.StartMode; Conta=$_.StartName }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Servicos Ativos" -Erro $_.Exception.Message }

        try {
            $servicosParados = @(Get-CimLocal -ClassName Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Sort-Object DisplayName | ForEach-Object {
                [pscustomobject]@{ Nome=$_.Name; DisplayName=$_.DisplayName; Estado=$_.State; StartMode=$_.StartMode; Conta=$_.StartName; Status="Atencao" }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Servicos Automaticos Parados" -Erro $_.Exception.Message }

        try {
            $processosTop = @(Get-CimLocal -ClassName Win32_Process | Sort-Object WorkingSetSize -Descending | Select-Object -First 25 | ForEach-Object {
                [pscustomobject]@{ PID=$_.ProcessId; Nome=$_.Name; Memoria=(Format-Bytes $_.WorkingSetSize); WorkingSetBytes=$_.WorkingSetSize; Caminho=$_.ExecutablePath; LinhaComando=if($_.CommandLine -and $_.CommandLine.Length -gt 180){$_.CommandLine.Substring(0,180)+"..."}else{$_.CommandLine} }
            })
        } catch { Add-Erro -Lista $errosRef -Secao "Processos" -Erro $_.Exception.Message }

        $dados = [pscustomobject]@{
            Computador = if($sistema.Count -gt 0 -and $sistema[0].Computador){$sistema[0].Computador}else{$env:COMPUTERNAME}
            DataGeracao = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
            Inicio = $inicio
            Fim = Get-Date
            DuracaoSegundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 2)
            StatusColeta = if($erros.Count -gt 0){"Concluido com alertas"}else{"OK"}
            Sistema = $sistema
            Hardware = [pscustomobject]@{ Base=$hardwareBase; Processador=$processador; MemoriaResumo=$memoriaResumo; MemoriaSlots=$memoriaSlots; Video=$video; Monitores=$monitores; USB=$usbDispositivos; TipoEquipamento=$tipoEquipamento }
            Armazenamento = [pscustomobject]@{ Discos=$discos; Volumes=$volumes }
            Rede = [pscustomobject]@{ IP=$redeIp; Adaptadores=$adaptadores }
            Software = $software
            Usuarios = $usuarios
            Seguranca = $seguranca
            Patches = $patches
            Servicos = [pscustomobject]@{ Ativos=$servicosAtivos; AutomaticosParados=$servicosParados; TopProcessosMemoria=$processosTop }
            Eventos = $eventos
            Erros = $erros
        }
        $dados | Add-Member -MemberType NoteProperty -Name Resumo -Value (Get-Score -Dados $dados)
        return $dados
    }

    $Alvo = Normalize-Alvo $Alvo
    $local = Test-Local $Alvo
    $erros = @()
    $errosRef = [ref]$erros

    Emitir-Progresso 4 "Iniciando coleta para $Alvo"
    Start-Sleep -Milliseconds 180

    $diagnostico = [ordered]@{ Alvo=$Alvo; Local=$local; DNSResolvido=$false; EnderecoResolvido="N/D"; Ping=$false; WinRM=$false; Porta5985=$false; Porta5986=$false; Status="N/D"; Observacao="" }

    try {
        if ($local) {
            $diagnostico.DNSResolvido = $true
            $diagnostico.EnderecoResolvido = "Local"
            $diagnostico.Ping = $true
            $diagnostico.WinRM = $true
            $diagnostico.Porta5985 = $true
            $diagnostico.Status = "OK"
            $diagnostico.Observacao = "Coleta local"
        }
        else {
            try {
                $addr = [System.Net.Dns]::GetHostAddresses($Alvo) | Select-Object -First 1
                if ($addr) { $diagnostico.DNSResolvido = $true; $diagnostico.EnderecoResolvido = $addr.IPAddressToString }
            } catch { $diagnostico.Observacao = "Falha DNS: $($_.Exception.Message)" }

            try { $diagnostico.Ping = Test-Connection -ComputerName $Alvo -Count 1 -Quiet -ErrorAction SilentlyContinue } catch {}

            foreach ($porta in @(5985, 5986)) {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $async = $tcp.BeginConnect($Alvo, $porta, $null, $null)
                    $ok = $async.AsyncWaitHandle.WaitOne(900, $false)
                    if ($ok) { $tcp.EndConnect($async) }
                    $tcp.Close()
                    if ($porta -eq 5985) { $diagnostico.Porta5985 = $ok }
                    if ($porta -eq 5986) { $diagnostico.Porta5986 = $ok }
                } catch {}
            }

            try { Test-WSMan -ComputerName $Alvo -ErrorAction Stop | Out-Null; $diagnostico.WinRM = $true } catch {}
            if (-not $diagnostico.WinRM) {
                $trusted = Ensure-TrustedHostLocal -HostAlvo $Alvo
                if ($trusted) {
                    Start-Sleep -Milliseconds 300
                    try { Test-WSMan -ComputerName $Alvo -Authentication Negotiate -ErrorAction Stop | Out-Null; $diagnostico.WinRM = $true; $diagnostico.Observacao = "TrustedHosts ajustado automaticamente para acesso por IP." } catch {}
                }
            }
            if (-not $diagnostico.DNSResolvido) {
                $diagnostico.Status = "Falha DNS"
            }
            elseif (-not $diagnostico.WinRM) {
                $diagnostico.Status = "Sem WinRM/CIM remoto"
                if ($diagnostico.Porta5985 -or $diagnostico.Porta5986) {
                    $diagnostico.Observacao = "Porta WinRM responde, mas Test-WSMan falhou. Para IP/workgroup, valide TrustedHosts, credencial e politica de remoting."
                }
                else {
                    $diagnostico.Observacao = "WinRM nao respondeu. Verifique VPN/rede, firewall, servico WinRM e permissao administrativa."
                }
            }
            else { $diagnostico.Status = "OK" }
        }
    }
    catch { Add-Erro -Lista $errosRef -Secao "Conectividade" -Erro $_.Exception.Message }

    Emitir-Progresso 14 "Conectividade validada"

    if (-not $local -and -not $diagnostico.WinRM) {
        Add-Erro -Lista $errosRef -Secao "Remoto" -Erro "Nao foi possivel coletar remotamente. Verifique VPN/rede, DNS, WinRM, firewall e permissoes."
        $dadosFalha = [pscustomobject]@{
            Computador=$Alvo; DataGeracao=(Get-Date).ToString("dd/MM/yyyy HH:mm:ss"); DuracaoSegundos=0; StatusColeta="Falha"
            Diagnostico=[pscustomobject]$diagnostico
            Resumo=[pscustomobject]@{ Score=0; Status="Critico"; Motivos="Falha de conectividade remota" }
            Sistema=@(); Hardware=[pscustomobject]@{ Base=@(); Processador=@(); MemoriaResumo=@(); MemoriaSlots=@(); Video=@(); Monitores=@(); USB=@(); TipoEquipamento=@() }
            Armazenamento=[pscustomobject]@{ Discos=@(); Volumes=@() }
            Rede=[pscustomobject]@{ IP=@(); Adaptadores=@() }
            Software=@()
            Usuarios=[pscustomobject]@{ UsuariosLocais=@(); Perfis=@(); Sessoes=@(); GruposAdministradores=@() }
            Seguranca=[pscustomobject]@{ Defender=@(); BitLocker=@(); TPM=@(); SecureBoot=@(); Firewall=@(); RDP=@(); Compartilhamentos=@() }
            Patches=[pscustomobject]@{ Hotfixes=@(); RebootPendente=@(); ServicosAtualizacao=@() }
            Servicos=[pscustomobject]@{ Ativos=@(); AutomaticosParados=@(); TopProcessosMemoria=@() }
            Eventos=@(); Erros=$erros
        }
        Emitir-Progresso 100 "Falha de conectividade remota"
        Emitir-Resultado $dadosFalha
        return
    }

    Emitir-Progresso 25 "Coletando inventario"
    try {
        if ($local) {
            $dados = & $ColetorLocal
        }
        else {
            Emitir-Progresso 35 "Executando coleta remota via WinRM"

            $funcoesRemotas = @(
                "function Add-Erro { $(${function:Add-Erro}) }",
                "function Format-Bytes { $(${function:Format-Bytes}) }",
                "function Convert-InstallDate { $(${function:Convert-InstallDate}) }",
                "function Convert-DigitalProductIdParaChave { $(${function:Convert-DigitalProductIdParaChave}) }",
                "function Get-ChaveWindowsLocal { $(${function:Get-ChaveWindowsLocal}) }",
                "function Get-CimLocal { $(${function:Get-CimLocal}) }",
                "function Get-SoftwareInstaladoLocal { $(${function:Get-SoftwareInstaladoLocal}) }",
                "function Get-UsuariosLocal { $(${function:Get-UsuariosLocal}) }",
                "function Get-SegurancaLocal { $(${function:Get-SegurancaLocal}) }",
                "function Get-PatchesLocal { $(${function:Get-PatchesLocal}) }",
                "function Get-EventosLocal { $(${function:Get-EventosLocal}) }",
                "function Get-Score { $(${function:Get-Score}) }"
            )

            $codigoRemoto = ($funcoesRemotas -join "`r`n") + "`r`n" + "& {" + $ColetorLocal.ToString() + "`r`n}"
            $scriptRemoto = [scriptblock]::Create($codigoRemoto)

            $sessOpt = New-PSSessionOption -OpenTimeout 120000 -OperationTimeout 180000
            try {
                $dados = Invoke-Command -ComputerName $Alvo -Authentication Negotiate -SessionOption $sessOpt -ScriptBlock $scriptRemoto -ErrorAction Stop
            } catch {
                $trusted = Ensure-TrustedHostLocal -HostAlvo $Alvo
                if ($trusted) {
                    $dados = Invoke-Command -ComputerName $Alvo -Authentication Negotiate -SessionOption $sessOpt -ScriptBlock $scriptRemoto -ErrorAction Stop
                } else {
                    throw
                }
            }
        }
        $dados | Add-Member -MemberType NoteProperty -Name Diagnostico -Value ([pscustomobject]$diagnostico) -Force
        Emitir-Progresso 100 "Coleta concluida"
        Emitir-Resultado $dados
    }
    catch {
        Add-Erro -Lista $errosRef -Secao "Coleta" -Erro $_.Exception.Message
        $dadosErro = [pscustomobject]@{
            Computador=$Alvo; DataGeracao=(Get-Date).ToString("dd/MM/yyyy HH:mm:ss"); StatusColeta="Erro"
            Diagnostico=[pscustomobject]$diagnostico
            Resumo=[pscustomobject]@{ Score=0; Status="Critico"; Motivos=$_.Exception.Message }
            Sistema=@(); Hardware=[pscustomobject]@{ Base=@(); Processador=@(); MemoriaResumo=@(); MemoriaSlots=@(); Video=@(); Monitores=@(); USB=@(); TipoEquipamento=@() }
            Armazenamento=[pscustomobject]@{ Discos=@(); Volumes=@() }
            Rede=[pscustomobject]@{ IP=@(); Adaptadores=@() }
            Software=@()
            Usuarios=[pscustomobject]@{ UsuariosLocais=@(); Perfis=@(); Sessoes=@(); GruposAdministradores=@() }
            Seguranca=[pscustomobject]@{ Defender=@(); BitLocker=@(); TPM=@(); SecureBoot=@(); Firewall=@(); RDP=@(); Compartilhamentos=@() }
            Patches=[pscustomobject]@{ Hotfixes=@(); RebootPendente=@(); ServicosAtualizacao=@() }
            Servicos=[pscustomobject]@{ Ativos=@(); AutomaticosParados=@(); TopProcessosMemoria=@() }
            Eventos=@(); Erros=$erros
        }
        Emitir-Progresso 100 "Erro na coleta"
        Emitir-Resultado $dadosErro
    }
}

$ScriptAcao = {
    param([string]$Alvo, [string]$Acao, [object]$Parametros)

    $ErrorActionPreference = "Continue"

    function Emit-Log {
        param([string]$Mensagem, [string]$Nivel = "INFO")
        [pscustomobject]@{ __tipo="log"; Nivel=$Nivel; Mensagem=$Mensagem; DataHora=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    }

    function Emit-Prog {
        param([int]$Percentual, [string]$Etapa)
        [pscustomobject]@{ __tipo="progresso"; Percentual=$Percentual; Etapa=$Etapa; DataHora=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    }

    function Emit-Result {
        param($Resultado)
        [pscustomobject]@{ __tipo="resultado"; Resultado=$Resultado }
    }

    function Test-LocalTarget {
        param([string]$Nome)
        if ([string]::IsNullOrWhiteSpace($Nome)) { return $true }
        $possiveis = @(".", "localhost", "127.0.0.1", "::1", $env:COMPUTERNAME)
        try { $possiveis += [System.Net.Dns]::GetHostName() } catch {}
        return ($possiveis -contains $Nome)
    }

    function Invoke-Target {
        param([scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
        $local = Test-LocalTarget $Alvo
        if ($local) { return & $ScriptBlock @ArgumentList }
        return Invoke-Command -ComputerName $Alvo -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }

    function Get-SafeResidualCandidates {
        param([string]$Nome, [string]$Fabricante, [string]$InstallLocation)

        $candidatos = New-Object System.Collections.Generic.List[string]
        $nomes = @($Nome, ($Nome -replace "[^\w\s\.-]", ""), ($Nome -replace "\s+", "")) | Where-Object { $_ -and $_.Trim().Length -ge 3 } | Select-Object -Unique

        if ($InstallLocation -and $InstallLocation -ne "N/D" -and (Test-Path -LiteralPath $InstallLocation)) {
            $candidatos.Add($InstallLocation)
        }

        $bases = @(
            $env:ProgramFiles,
            ${env:ProgramFiles(x86)},
            $env:ProgramData
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

        foreach ($base in $bases) {
            foreach ($n in $nomes) {
                try {
                    Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "*$n*" } |
                        ForEach-Object { $candidatos.Add($_.FullName) }
                } catch {}
            }
        }

        try {
            $usersBase = Join-Path $env:SystemDrive "Users"
            Get-ChildItem -LiteralPath $usersBase -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") } |
                ForEach-Object {
                    $u = $_.FullName
                    foreach ($rel in @("AppData\Local", "AppData\Roaming")) {
                        $base = Join-Path $u $rel
                        if (Test-Path -LiteralPath $base) {
                            foreach ($n in $nomes) {
                                Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -like "*$n*" } |
                                    ForEach-Object { $candidatos.Add($_.FullName) }
                            }
                        }
                    }
                }
        } catch {}

        return @($candidatos | Where-Object { $_ -and $_.Length -gt 5 } | Select-Object -Unique)
    }

    function Normalize-AlvoAcao {
        param([string]$Nome)
        if ([string]::IsNullOrWhiteSpace($Nome)) { return $env:COMPUTERNAME }
        $n = $Nome.Trim()
        $n = $n -replace "^[\\/]+", ""
        if ($n -match "\\") { $n = ($n -split "\\")[0] }
        if ($n -match "/") { $n = ($n -split "/")[0] }
        if ([string]::IsNullOrWhiteSpace($n)) { return $env:COMPUTERNAME }
        return $n
    }

    $Alvo = Normalize-AlvoAcao $Alvo

    $inicio = Get-Date
    Emit-Prog 3 "Preparando acao $Acao em $Alvo"
    Emit-Log "Acao solicitada: $Acao | Alvo: $Alvo"

    try {
        switch ($Acao) {
            "open_share" {
                $hostAlvo = if ([string]::IsNullOrWhiteSpace($Alvo)) { $env:COMPUTERNAME } else { $Alvo }
                $local = Test-LocalTarget $hostAlvo
                $path = if ($local) { "C:\" } else { "\\$hostAlvo\c$" }
                Emit-Prog 50 "Abrindo $path"
                Start-Process explorer.exe $path
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Pasta aberta"; Caminho=$path })
            }

            "restart_pc" {
                $segundos = [int]($Parametros.delaySeconds)
                if ($segundos -lt 0) { $segundos = 0 }
                Emit-Prog 40 "Agendando reinicio"
                Invoke-Target -ArgumentList @($segundos) -ScriptBlock {
                    param($s)
                    shutdown.exe /r /t $s /c "Inventario Corporativo N3 LIVE: reinicio solicitado pelo operador."
                }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Reinicio solicitado"; Delay=$segundos })
            }

            "shutdown_pc" {
                $segundos = [int]($Parametros.delaySeconds)
                if ($segundos -lt 0) { $segundos = 0 }
                Emit-Prog 40 "Agendando desligamento"
                Invoke-Target -ArgumentList @($segundos) -ScriptBlock {
                    param($s)
                    shutdown.exe /s /t $s /c "Inventario Corporativo N3 LIVE: desligamento solicitado pelo operador."
                }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Desligamento solicitado"; Delay=$segundos })
            }

            "abort_shutdown" {
                Emit-Prog 40 "Cancelando desligamento/reinicio"
                Invoke-Target -ScriptBlock { shutdown.exe /a }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Agendamento de shutdown/restart cancelado quando existente" })
            }

            "kill_process" {
                $pid = [int]$Parametros.pid
                Emit-Prog 40 "Encerrando processo PID $pid"
                Invoke-Target -ArgumentList @($pid) -ScriptBlock {
                    param($p)
                    Stop-Process -Id $p -Force -ErrorAction Stop
                    "Processo $p encerrado."
                }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Processo encerrado"; PID=$pid })
            }

            "restart_process" {
                $pid = [int]$Parametros.pid
                $path = [string]$Parametros.path
                Emit-Prog 30 "Reiniciando processo PID $pid"
                Invoke-Target -ArgumentList @($pid, $path) -ScriptBlock {
                    param($p, $exe)
                    if ([string]::IsNullOrWhiteSpace($exe) -or $exe -eq "N/D" -or -not (Test-Path -LiteralPath $exe)) {
                        $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$p" -ErrorAction SilentlyContinue
                        if ($proc -and $proc.ExecutablePath) { $exe = $proc.ExecutablePath }
                    }
                    if ([string]::IsNullOrWhiteSpace($exe) -or $exe -eq "N/D" -or -not (Test-Path -LiteralPath $exe)) {
                        throw "Caminho do executavel nao encontrado. Use apenas matar processo."
                    }
                    Stop-Process -Id $p -Force -ErrorAction Stop
                    Start-Sleep -Seconds 1
                    Start-Process -FilePath $exe
                    "Processo reiniciado por caminho: $exe"
                }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Processo reiniciado"; PID=$pid })
            }

            "start_service" {
                $nome = [string]$Parametros.name
                Emit-Prog 40 "Iniciando servico $nome"
                Invoke-Target -ArgumentList @($nome) -ScriptBlock { param($n) Start-Service -Name $n -ErrorAction Stop }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Servico iniciado"; Servico=$nome })
            }

            "stop_service" {
                $nome = [string]$Parametros.name
                Emit-Prog 40 "Parando servico $nome"
                Invoke-Target -ArgumentList @($nome) -ScriptBlock { param($n) Stop-Service -Name $n -Force -ErrorAction Stop }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Servico parado"; Servico=$nome })
            }

            "restart_service" {
                $nome = [string]$Parametros.name
                Emit-Prog 40 "Reiniciando servico $nome"
                Invoke-Target -ArgumentList @($nome) -ScriptBlock { param($n) Restart-Service -Name $n -Force -ErrorAction Stop }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Servico reiniciado"; Servico=$nome })
            }

            "set_service_startup" {
                $nome = [string]$Parametros.name
                $tipo = [string]$Parametros.startup
                if ($tipo -notin @("Automatic","Manual","Disabled")) { throw "Tipo de inicializacao invalido: $tipo" }
                Emit-Prog 40 "Alterando inicializacao do servico $nome para $tipo"
                Invoke-Target -ArgumentList @($nome, $tipo) -ScriptBlock { param($n,$t) Set-Service -Name $n -StartupType $t -ErrorAction Stop }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Startup alterado"; Servico=$nome; Startup=$tipo })
            }

            "uninstall_software" {
                $nome = [string]$Parametros.name
                $uninstall = [string]$Parametros.uninstallString
                $quiet = [string]$Parametros.quietUninstallString
                $installLocation = [string]$Parametros.installLocation
                $registro = [string]$Parametros.registro
                $limpar = [bool]$Parametros.cleanup
                Emit-Log "Software: $nome"
                Emit-Prog 20 "Preparando desinstalacao de $nome"

                Invoke-Target -ArgumentList @($nome, $uninstall, $quiet, $installLocation, $registro, $limpar) -ScriptBlock {
                    param($nome,$uninstall,$quiet,$installLocation,$registro,$limpar)

                    function Invoke-UninstallString {
                        param([string]$Cmd)
                        if ([string]::IsNullOrWhiteSpace($Cmd) -or $Cmd -eq "N/D") { throw "UninstallString vazio." }

                        $cmdTrim = $Cmd.Trim()
                        if ($cmdTrim -match "MsiExec(\.exe)?") {
                            $guid = [regex]::Match($cmdTrim, "\{[0-9A-Fa-f\-]{36}\}")
                            if ($guid.Success) {
                                $args = "/x $($guid.Value) /qn /norestart"
                                $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru
                                return $p.ExitCode
                            }
                        }

                        if ($cmdTrim.StartsWith('"')) {
                            $fim = $cmdTrim.IndexOf('"', 1)
                            $exe = $cmdTrim.Substring(1, $fim - 1)
                            $args = $cmdTrim.Substring($fim + 1).Trim()
                        }
                        else {
                            $partes = $cmdTrim.Split(" ", 2)
                            $exe = $partes[0]
                            $args = if ($partes.Count -gt 1) { $partes[1] } else { "" }
                        }

                        if (-not (Test-Path -LiteralPath $exe)) {
                            $exe = ($exe -replace '"','')
                        }

                        $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
                        return $p.ExitCode
                    }

                    function Get-SafeResidualCandidatesInner {
                        param([string]$Nome, [string]$InstallLocation)
                        $candidatos = New-Object System.Collections.Generic.List[string]
                        if ($InstallLocation -and $InstallLocation -ne "N/D" -and (Test-Path -LiteralPath $InstallLocation)) { $candidatos.Add($InstallLocation) }
                        $nomes = @($Nome, ($Nome -replace "[^\w\s\.-]", ""), ($Nome -replace "\s+", "")) | Where-Object { $_ -and $_.Trim().Length -ge 3 } | Select-Object -Unique
                        $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
                        foreach ($base in $bases) {
                            foreach ($n in $nomes) {
                                Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -like "*$n*" } |
                                    ForEach-Object { $candidatos.Add($_.FullName) }
                            }
                        }
                        try {
                            $usersBase = Join-Path $env:SystemDrive "Users"
                            Get-ChildItem -LiteralPath $usersBase -Directory -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") } |
                                ForEach-Object {
                                    foreach ($rel in @("AppData\Local", "AppData\Roaming")) {
                                        $base = Join-Path $_.FullName $rel
                                        if (Test-Path -LiteralPath $base) {
                                            foreach ($n in $nomes) {
                                                Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                                                    Where-Object { $_.Name -like "*$n*" } |
                                                    ForEach-Object { $candidatos.Add($_.FullName) }
                                            }
                                        }
                                    }
                                }
                        } catch {}
                        return @($candidatos | Where-Object { $_ -and $_.Length -gt 5 } | Select-Object -Unique)
                    }

                    $cmd = if ($quiet -and $quiet -ne "N/D") { $quiet } else { $uninstall }
                    $exitCode = Invoke-UninstallString -Cmd $cmd
                    $removidos = @()

                    if ($limpar) {
                        Start-Sleep -Seconds 2
                        $cands = Get-SafeResidualCandidatesInner -Nome $nome -InstallLocation $installLocation
                        foreach ($c in $cands) {
                            try {
                                if (Test-Path -LiteralPath $c) {
                                    Remove-Item -LiteralPath $c -Recurse -Force -ErrorAction SilentlyContinue
                                    $removidos += $c
                                }
                            } catch {}
                        }

                        if ($registro -and $registro -ne "N/D") {
                            try {
                                Remove-Item -LiteralPath $registro -Recurse -Force -ErrorAction SilentlyContinue
                                $removidos += "Registro: $registro"
                            } catch {}
                        }
                    }

                    [pscustomobject]@{ ExitCode=$exitCode; ResidualRemovido=$removidos }
                } | ForEach-Object { Emit-Log ("Resultado desinstalacao: " + ($_ | Out-String)) }

                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Desinstalacao concluida. Atualize o inventario para validar."; Software=$nome; Limpeza=$limpar })
            }

            "opt_clean" {
                Emit-Prog 8 "Iniciando limpeza profunda"
                Invoke-Target -ScriptBlock {
                    $log = New-Object System.Collections.Generic.List[string]
                    foreach ($pname in @("chrome","msedge","brave","firefox","opera","vivaldi")) { Get-Process -Name $pname -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
                    $log.Add("Navegadores encerrados quando estavam em execucao.")

                    $paths = @($env:TEMP,$env:TMP,(Join-Path $env:windir "Temp"))
                    foreach($p in $paths){
                        if(Test-Path -LiteralPath $p){
                            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
                        }
                    }
                    $log.Add("TEMP do Windows e usuario atual limpos.")

                    $base=Join-Path $env:SystemDrive "Users"
                    $skip=@("Public","Default","Default User","All Users")
                    $users=Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue
                    foreach($u in $users){
                        if($skip -contains $u.Name){continue}
                        foreach($r in @("AppData\Local\Temp","AppData\Local\Microsoft\Windows\INetCache","AppData\Local\Microsoft\Windows\WebCache","AppData\Local\CrashDumps")){
                            $p=Join-Path $u.FullName $r
                            if(Test-Path -LiteralPath $p){
                                Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
                            }
                        }
                    }
                    $log.Add("Temporarios dos perfis processados.")

                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    ipconfig /flushdns | Out-Null
                    dism /Online /Cleanup-Image /StartComponentCleanup | Out-Null
                    $log.Add("Lixeira, DNS e StartComponentCleanup processados.")
                    $log
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Limpeza profunda finalizada" })
            }

            "opt_performance" {
                Emit-Prog 8 "Iniciando otimizacao de desempenho"
                Invoke-Target -ScriptBlock {
                    $log = New-Object System.Collections.Generic.List[string]
                    try {
                        $out=powercfg -duplicatescheme E9A42B02-D5DF-448D-AA00-03F14749EB61
                        $txt=$out -join " "
                        $m=[regex]::Match($txt,"[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")
                        if($m.Success){ powercfg /setactive $m.Value | Out-Null; $log.Add("Plano desempenho maximo ativo: $($m.Value)") }
                    } catch { $log.Add("Plano desempenho maximo nao aplicado: $($_.Exception.Message)") }

                    powercfg /change disk-timeout-ac 0 | Out-Null
                    powercfg /change standby-timeout-ac 0 | Out-Null
                    powercfg /change hibernate-timeout-ac 0 | Out-Null
                    $log.Add("Timeouts de energia AC ajustados.")

                    dism /Online /Cleanup-Image /RestoreHealth | Out-Null
                    $log.Add("DISM RestoreHealth finalizado.")

                    sfc /scannow | Out-Null
                    $log.Add("SFC finalizado.")

                    $vols=Get-Volume -ErrorAction SilentlyContinue
                    foreach($v in $vols){ if($v.DriveLetter -and $v.DriveType -eq "Fixed"){ Optimize-Volume -DriveLetter $v.DriveLetter -Verbose -ErrorAction SilentlyContinue | Out-Null } }
                    $log.Add("Optimize-Volume processado.")

                    gpupdate /force | Out-Null
                    ipconfig /flushdns | Out-Null
                    $log.Add("GPUpdate e flushdns finalizados.")
                    $log
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Otimizacao de desempenho finalizada" })
            }

            "opt_network" {
                Emit-Prog 8 "Iniciando reparo de rede"
                Invoke-Target -ScriptBlock {
                    $log = New-Object System.Collections.Generic.List[string]
                    ipconfig /flushdns | Out-Null; $log.Add("DNS limpo.")
                    ipconfig /registerdns | Out-Null; $log.Add("DNS registrado.")
                    arp -d * | Out-Null; $log.Add("ARP limpo.")
                    netsh interface ip delete arpcache | Out-Null
                    netsh interface ip delete destinationcache | Out-Null
                    nbtstat -R | Out-Null
                    nbtstat -RR | Out-Null
                    netsh int ip reset | Out-Null
                    netsh winsock reset catalog | Out-Null
                    netsh winsock reset | Out-Null
                    netsh winhttp reset proxy | Out-Null
                    ipconfig /all | Out-Null
                    $log.Add("Reset TCP/IP, Winsock e proxy WinHTTP finalizados. Reinicio recomendado.")
                    $log
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Reparo de rede finalizado. Reinicio recomendado." })
            }

            "opt_printer" {
                Emit-Prog 8 "Iniciando reparo de impressora"
                Invoke-Target -ScriptBlock {
                    $log = New-Object System.Collections.Generic.List[string]
                    try {
                        $printers=Get-Printer -ErrorAction Stop
                        foreach($p in $printers){
                            $jobs=Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue
                            foreach($j in $jobs){ Remove-PrintJob -PrinterName $p.Name -ID $j.ID -ErrorAction SilentlyContinue }
                        }
                        $log.Add("Filas de impressao processadas.")
                    } catch { $log.Add("Get-Printer indisponivel ou sem filas: $($_.Exception.Message)") }

                    Stop-Service spooler -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $spool = Join-Path $env:windir "System32\spool\PRINTERS"
                    if(Test-Path $spool){ Remove-Item "$spool\*.*" -Force -ErrorAction SilentlyContinue }
                    Set-Service spooler -StartupType Automatic -ErrorAction SilentlyContinue
                    Start-Service spooler -ErrorAction SilentlyContinue
                    sfc /scanfile="$env:windir\System32\spoolsv.exe" | Out-Null
                    $log.Add("Spooler reiniciado e pasta PRINTERS limpa.")
                    $log
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Reparo de impressora finalizado" })
            }

            "opt_full" {
                foreach ($sub in @("opt_clean","opt_performance","opt_network","opt_printer")) {
                    Emit-Log "Executando modulo: $sub"
                    # Reutilizacao simplificada: chamar os blocos por nova execucao nao e trivial em switch; replicamos chamada ao operador por mensagens.
                }
                Emit-Log "Use os modulos individuais para progresso granular. A execucao completa iniciara limpeza, performance, rede e impressora."
                # Executa limpeza
                Invoke-Target -ScriptBlock {
                    foreach ($pname in @("chrome","msedge","brave","firefox","opera","vivaldi")) { Get-Process -Name $pname -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
                    foreach($p in @($env:TEMP,$env:TMP,(Join-Path $env:windir "Temp"))){ if(Test-Path $p){ Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } }
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    dism /Online /Cleanup-Image /StartComponentCleanup | Out-Null
                    dism /Online /Cleanup-Image /RestoreHealth | Out-Null
                    sfc /scannow | Out-Null
                    ipconfig /flushdns | Out-Null
                    arp -d * | Out-Null
                    netsh winsock reset | Out-Null
                    Stop-Service spooler -Force -ErrorAction SilentlyContinue
                    $spool = Join-Path $env:windir "System32\spool\PRINTERS"
                    if(Test-Path $spool){ Remove-Item "$spool\*.*" -Force -ErrorAction SilentlyContinue }
                    Start-Service spooler -ErrorAction SilentlyContinue
                    "Execucao completa finalizada. Reinicio recomendado."
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Otimizacao completa finalizada. Reinicio recomendado." })
            }


            "logoff_session" {
                $id = [string]$Parametros.id
                if ([string]::IsNullOrWhiteSpace($id) -or $id -eq "N/D") { throw "ID da sessao invalido." }
                Emit-Prog 35 "Derrubando sessao ID $id"
                Invoke-Target -ArgumentList @($id) -ScriptBlock {
                    param($sessionId)
                    logoff.exe $sessionId
                    "Sessao $sessionId encerrada."
                } | ForEach-Object { Emit-Log $_ }
                Emit-Result ([pscustomobject]@{ Ok=$true; Mensagem="Sessao encerrada"; SessaoId=$id })
            }

            "online_model_lookup" {
                $serial = [string]$Parametros.serial
                $fabricante = [string]$Parametros.fabricante
                $modelo = [string]$Parametros.modelo
                if ([string]::IsNullOrWhiteSpace($serial) -or $serial -eq "N/D") { throw "Serial nao informado para busca online." }
                Emit-Prog 20 "Pesquisando modelo online por serial"
                $query = [uri]::EscapeDataString(("`"{0}`" {1} {2} exact model" -f $serial, $fabricante, $modelo))
                $url = "https://www.bing.com/search?q=$query"
                try {
                    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 15
                    $html = [string]$resp.Content
                    $m = [regex]::Match($html,'<li class=\"b_algo\".*?<h2><a href=\"(?<u>[^\"]+)\"[^>]*>(?<t>.*?)</a>','Singleline')
                    if ($m.Success) {
                        $firstUrl = [System.Net.WebUtility]::HtmlDecode($m.Groups['u'].Value)
                        $firstTitle = ([regex]::Replace([System.Net.WebUtility]::HtmlDecode($m.Groups['t'].Value),'<[^>]+>','')).Trim()
                        Emit-Log ("Resultado encontrado: " + $firstTitle)
                        Emit-Log ("Link: " + $firstUrl)
                        try { Start-Process $firstUrl | Out-Null } catch {}
                        Emit-Result ([pscustomobject]@{
                            Ok = $true
                            Mensagem = "Busca online concluida"
                            Serial = $serial
                            Fabricante = $fabricante
                            ModeloLocal = $modelo
                            TituloResultado = $firstTitle
                            LinkResultado = $firstUrl
                            LinkPesquisa = $url
                        })
                    } else {
                        Emit-Log "Sem resultado parseavel na primeira tentativa."
                        try { Start-Process $url | Out-Null } catch {}
                        Emit-Result ([pscustomobject]@{
                            Ok = $true
                            Mensagem = "Busca online executada; abra os resultados para confirmar modelo exato."
                            Serial = $serial
                            LinkPesquisa = $url
                        })
                    }
                } catch {
                    Emit-Log ("Falha na busca online: " + $_.Exception.Message) "ERRO"
                    try { Start-Process $url | Out-Null } catch {}
                    Emit-Result ([pscustomobject]@{
                        Ok = $false
                        Mensagem = "Falha na busca automatica. Pesquisa aberta no navegador."
                        Serial = $serial
                        LinkPesquisa = $url
                    })
                }
            }

            "online_monitor_lookup" {
                $marca = [string]$Parametros.marca
                $modelo = [string]$Parametros.modelo
                $serie = [string]$Parametros.serie
                if ([string]::IsNullOrWhiteSpace($marca) -and [string]::IsNullOrWhiteSpace($modelo) -and [string]::IsNullOrWhiteSpace($serie)) {
                    throw "Dados do monitor nao informados para busca online."
                }
                Emit-Prog 20 "Pesquisando monitor online"
                $query = [uri]::EscapeDataString(("monitor `"{0}`" `"{1}`" `"{2}`" specs manual" -f $marca, $modelo, $serie))
                $url = "https://www.bing.com/search?q=$query"
                try {
                    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 15
                    $html = [string]$resp.Content
                    $m = [regex]::Match($html,'<li class=\"b_algo\".*?<h2><a href=\"(?<u>[^\"]+)\"[^>]*>(?<t>.*?)</a>','Singleline')
                    if ($m.Success) {
                        $firstUrl = [System.Net.WebUtility]::HtmlDecode($m.Groups['u'].Value)
                        $firstTitle = ([regex]::Replace([System.Net.WebUtility]::HtmlDecode($m.Groups['t'].Value),'<[^>]+>','')).Trim()
                        Emit-Log ("Resultado monitor: " + $firstTitle)
                        Emit-Log ("Link: " + $firstUrl)
                        try { Start-Process $firstUrl | Out-Null } catch {}
                        Emit-Result ([pscustomobject]@{
                            Ok = $true
                            Mensagem = "Busca online de monitor concluida"
                            Marca = $marca
                            Modelo = $modelo
                            Serie = $serie
                            TituloResultado = $firstTitle
                            LinkResultado = $firstUrl
                            LinkPesquisa = $url
                        })
                    } else {
                        try { Start-Process $url | Out-Null } catch {}
                        Emit-Result ([pscustomobject]@{
                            Ok = $true
                            Mensagem = "Busca online do monitor executada; revise os resultados."
                            Marca = $marca
                            Modelo = $modelo
                            Serie = $serie
                            LinkPesquisa = $url
                        })
                    }
                } catch {
                    Emit-Log ("Falha na busca online do monitor: " + $_.Exception.Message) "ERRO"
                    try { Start-Process $url | Out-Null } catch {}
                    Emit-Result ([pscustomobject]@{
                        Ok = $false
                        Mensagem = "Falha na busca automatica do monitor. Pesquisa aberta no navegador."
                        Marca = $marca
                        Modelo = $modelo
                        Serie = $serie
                        LinkPesquisa = $url
                    })
                }
            }
            default {
                throw "Acao desconhecida: $Acao"
            }
        }

        Emit-Prog 100 "Acao finalizada"
    }
    catch {
        Emit-Log $_.Exception.Message "ERRO"
        Emit-Prog 100 "Acao finalizada com erro"
        Emit-Result ([pscustomobject]@{ Ok=$false; Mensagem=$_.Exception.Message; Acao=$Acao; Alvo=$Alvo })
    }
}

$HtmlPainel = @'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Inventário</title>
<style>
:root{--bg:#edf2f7;--panel:#f8fafc;--panel2:#ffffff;--text:#1f2937;--muted:#6b7280;--line:#cbd5e1;--accent:#2563eb;--ok:#15803d;--warn:#b45309;--crit:#b91c1c;--shadow:0 8px 20px rgba(15,23,42,.08)}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:linear-gradient(180deg,#eef3f8,#e8eef5);color:var(--text);font-family:Calibri,Segoe UI,Arial,sans-serif}

.brand{display:flex;gap:12px;align-items:center;margin-bottom:18px}.logo{width:48px;height:48px;border-radius:17px;display:grid;place-items:center;background:linear-gradient(135deg,#38bdf8,#2563eb);font-weight:900;color:#fff;box-shadow:0 14px 35px rgba(56,189,248,.28)}
.brand h1{font-size:17px;margin:0}.brand p{font-size:12px;color:var(--muted);margin:3px 0 0}.nav{display:grid;gap:7px}.nav a{color:var(--muted);text-decoration:none;padding:9px 11px;border-radius:12px;font-size:13px;border:1px solid transparent}.nav a:hover{color:var(--text);background:rgba(56,189,248,.12);border-color:rgba(56,189,248,.22)}
.main{margin-left:0;padding:14px;max-width:1400px;margin-right:auto}.hero{background:linear-gradient(135deg,rgba(56,189,248,.12),rgba(37,99,235,.04)),var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px;box-shadow:none;margin-bottom:10px}
.hero h1{font-size:30px;margin:0 0 8px;letter-spacing:-.04em}.meta{display:flex;gap:10px;flex-wrap:wrap;color:var(--muted);font-size:13px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin-top:18px}.toolbar input,.toolbar select{background:var(--panel2);border:1px solid var(--line);border-radius:13px;color:var(--text);padding:9px 11px;min-width:240px;outline:none;font-size:13px}
button,.btn{background:rgba(56,189,248,.10);color:var(--text);border:1px solid rgba(56,189,248,.22);padding:5px 8px;border-radius:8px;cursor:pointer;font-weight:700;margin:1px;font-size:11px;line-height:1.05}button:hover{background:rgba(56,189,248,.23)}button.danger{border-color:rgba(239,68,68,.35);background:rgba(239,68,68,.12)}button.warn{border-color:rgba(245,158,11,.40);background:rgba(245,158,11,.12)}button.okbtn{border-color:rgba(34,197,94,.40);background:rgba(34,197,94,.12)}
.progress-wrap{margin-top:16px;background:rgba(148,163,184,.12);border:1px solid var(--line);border-radius:999px;height:16px;overflow:hidden}.progress{height:100%;width:0%;background:linear-gradient(90deg,#38bdf8,#22c55e);transition:.3s}.stage{font-size:12px;color:var(--muted);margin-top:8px}
.section{background:var(--panel2);border:1px solid var(--line);border-radius:14px;padding:14px;margin-bottom:12px;box-shadow:var(--shadow)}.section h2{font-size:18px;margin:0 0 10px;display:flex;align-items:center;justify-content:space-between;cursor:pointer}.collapsed .section-body{display:none}.section h3{font-size:15px;color:var(--accent);margin:18px 0 10px}
.cards{display:grid;grid-template-columns:repeat(5,minmax(160px,1fr));gap:8px}.card{background:linear-gradient(180deg,var(--panel2),var(--panel));border:1px solid var(--line);border-radius:10px;padding:8px;min-height:72px}.card-title{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}.card-value{font-size:16px;font-weight:800;margin:4px 0}.card-detail{font-size:11px;color:var(--muted)}.card-ok{border-color:rgba(34,197,94,.55)}.card-warn{border-color:rgba(245,158,11,.65)}.card-crit{border-color:rgba(239,68,68,.65)}
.table-tools{display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;margin-bottom:10px}.filter{background:var(--panel2);border:1px solid var(--line);border-radius:13px;color:var(--text);padding:10px 12px;min-width:260px}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:16px}table{border-collapse:collapse;width:100%;min-width:820px;font-size:13px}th{background:#e6edf6;color:#1f2937;text-align:left;padding:11px;border-bottom:1px solid var(--line);position:sticky;top:0}td{padding:9px 11px;border-bottom:1px solid rgba(148,163,184,.15);vertical-align:top}tbody tr:nth-child(even){background:rgba(148,163,184,.045)}tbody tr:hover{background:rgba(37,99,235,.08)}
.badge{display:inline-flex;padding:4px 8px;border-radius:999px;font-size:12px;font-weight:900;border:1px solid transparent}.ok{background:rgba(34,197,94,.16);color:#bbf7d0;border-color:rgba(34,197,94,.38)}.warn{background:rgba(245,158,11,.16);color:#fde68a;border-color:rgba(245,158,11,.42)}.crit{background:rgba(239,68,68,.16);color:#fecaca;border-color:rgba(239,68,68,.42)}.nd{background:rgba(148,163,184,.14);color:#dbeafe;border-color:rgba(148,163,184,.25)}
.empty{border:1px dashed var(--line);border-radius:15px;padding:14px;color:var(--muted);background:rgba(148,163,184,.06)}.footer{text-align:center;color:var(--muted);font-size:12px;padding:22px}.pill{display:inline-flex;align-items:center;gap:7px;padding:7px 10px;border:1px solid var(--line);border-radius:999px;background:rgba(148,163,184,.08)}.dot{width:8px;height:8px;border-radius:99px;background:var(--muted)}.dot.run{background:var(--accent);box-shadow:0 0 18px var(--accent)}.dot.ok{background:var(--ok)}.dot.err{background:var(--crit)}.logbox{background:#020617;border:1px solid var(--line);border-radius:16px;padding:12px;min-height:150px;max-height:360px;overflow:auto;color:#dbeafe;font-family:Consolas,monospace;font-size:12px;white-space:pre-wrap}.notice{border-left:4px solid var(--warn);padding:12px;background:rgba(245,158,11,.10);border-radius:14px;color:var(--muted)}
@media(max-width:1150px){.main{margin-left:0;padding:16px}.cards{grid-template-columns:repeat(2,minmax(150px,1fr))}}@media(max-width:650px){.cards{grid-template-columns:1fr}.toolbar input,.toolbar select{min-width:100%;width:100%}.hero h1{font-size:24px}}
</style>
</head>
<body>
<main class="main">
  <div class="toolbar" style="margin:0 0 8px 0">
    <button onclick="expandirTudo()">Expandir seções</button>
    <button onclick="recolherTudo()">Recolher seções</button>
  </div>
  
  <header class="hero" id="controle">
    <h1 id="titulo">Inventário</h1>
    <div class="meta">
      <span class="pill"><span id="dot" class="dot"></span><span id="status">Aguardando</span></span>
      <span id="metaComputador">Computador: -</span>
      <span id="metaData">Atualizado: -</span>
      <span id="metaDuracao">Duração: -</span>
    </div>
    <div class="toolbar">
      <input id="computer" placeholder="Digite hostname ou IP. Vazio = máquina local">
      <button onclick="iniciarColeta()">Buscar / Atualizar</button>
      <button onclick="usarLocal()">Usar máquina local</button>
      <button onclick="abrirC()">Abrir C$ / C:</button>
      <button onclick="exportarTxtSelecionado()">Exportar TXT Seletivo</button>
    </div>
    <div class="toolbar">
      <button class="warn" onclick="pcAction('restart_pc')">Reiniciar PC</button>
      <button class="danger" onclick="pcAction('shutdown_pc')">Desligar PC</button>
      <button onclick="pcAction('abort_shutdown')">Cancelar reinício/desligamento</button>
      <label class="pill"><input id="autoRefresh" type="checkbox"> Auto-atualizar</label>
      <select id="intervalo"><option value="60">a cada 60s</option><option value="120">a cada 2min</option><option value="300">a cada 5min</option></select>
      <button class="danger" onclick="encerrarServidor()">Encerrar servidor local</button>
    </div>
    <div class="progress-wrap"><div class="progress" id="progress"></div></div>
    <div class="stage" id="stage">Pronto para coletar.</div>
  </header>

  <section id="dashboard" class="section"><h2>Dashboard Executivo</h2><div class="cards" id="cards"></div></section>

  <section id="acao" class="section">
    <h2>Ações em tempo real</h2>
    <div class="progress-wrap"><div class="progress" id="actionProgress"></div></div>
    <div class="stage" id="actionStage">Nenhuma ação em execução.</div>
    <h3>Log da ação</h3>
    <div class="logbox" id="actionLog">Aguardando ação...</div>
  </section>

  <section id="sistema" class="section"><h2>Sistema Operacional</h2><div class="notice">Resumo completo do Windows, versão, build, arquitetura, licenciamento, domínio e uptime.</div><div id="tblSistema"></div><h3>Diagnóstico</h3><div id="tblDiag"></div></section>
  <section id="usuarios" class="section"><h2>Usuários e sessões</h2><h3>Usuários locais</h3><div id="tblUsers"></div><h3>Sessões conectadas/ativas</h3><div id="tblSessions"></div><h3>Perfis de usuário</h3><div id="tblProfiles"></div><h3>Administradores locais</h3><div id="tblAdminsUsers"></div></section>
  <section id="hardware" class="section"><h2>Hardware</h2><div class="toolbar"><button onclick="lookupModeloOnline()">Buscar modelo exato online (serial)</button><button onclick="lookupMonitorOnline()">Buscar monitor online</button></div><h3>Base</h3><div id="tblHardwareBase"></div><h3>Tipo de equipamento</h3><div id="tblTipoEquip"></div><h3>Processador</h3><div id="tblCpu"></div><h3>Memória por slot</h3><div id="tblMemSlots"></div><h3>Vídeo</h3><div id="tblVideo"></div><h3>Monitores conectados</h3><div id="tblMonitores"></div><h3>Dispositivos USB conectados</h3><div id="tblUsb"></div></section>
  <section id="armazenamento" class="section"><h2>Armazenamento</h2><h3>Discos físicos</h3><div id="tblDiscos"></div><h3>Volumes</h3><div id="tblVolumes"></div></section>
  <section id="rede" class="section"><h2>Rede</h2><h3>Configuração IP</h3><div id="tblRedeIp"></div><h3>Adaptadores</h3><div id="tblAdaptadores"></div></section>
  <section id="software" class="section"><h2>Software instalado e remoção</h2><div class="notice">Use "Desinstalar + limpeza" com cuidado. A limpeza residual é conservadora e registra a ação, mas pode remover pastas relacionadas ao software.</div><div id="tblSoftware"></div></section>

  <div class="footer">Inventário. Painel local de monitoramento.</div>
</main>

<script>
let estadoAtual = null;
let ultimoJson = null;
let actionTimer = null;
const tableScrollState = {};
function prepararSecoes(){
  document.querySelectorAll("section.section").forEach(sec=>{
    if(sec.dataset.ready==="1") return;
    const h2=sec.querySelector("h2");
    if(!h2) return;
    const body=document.createElement("div");
    body.className="section-body";
    while(h2.nextSibling){ body.appendChild(h2.nextSibling); }
    sec.appendChild(body);
    const b=document.createElement("button");
    b.className="toggle-btn";
    b.textContent="Recolher";
    b.onclick=(ev)=>{ev.stopPropagation();toggleSecao(sec,b);};
    h2.appendChild(b);
    h2.onclick=()=>toggleSecao(sec,b);
    sec.dataset.ready="1";
  });
}
function toggleSecao(sec,b){ sec.classList.toggle("collapsed"); b.textContent=sec.classList.contains("collapsed")?"Expandir":"Recolher"; }
function expandirTudo(){ document.querySelectorAll("section.section").forEach(s=>{s.classList.remove("collapsed"); const b=s.querySelector(".toggle-btn"); if(b)b.textContent="Recolher";}); }
function recolherTudo(){ document.querySelectorAll("section.section").forEach(s=>{s.classList.add("collapsed"); const b=s.querySelector(".toggle-btn"); if(b)b.textContent="Expandir";}); }

function arr(x){ if(!x) return []; return Array.isArray(x) ? x : [x]; }
function val(x){ return (x===null || x===undefined || x==="") ? "N/D" : x; }
function alvo(){
  let v = document.getElementById("computer").value.trim();
  v = v.replace(/^[\\/]+/, "");
  if(v.includes("\\")) v = v.split("\\")[0];
  if(v.includes("/")) v = v.split("/")[0];
  return v;
}
function escapeHtml(v){ return String(val(v)).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])); }
function clsStatus(s){ s=String(s||"").toLowerCase(); if(s.includes("crit")||s.includes("falha")||s.includes("erro"))return"crit"; if(s.includes("aten")||s.includes("pendente")||s.includes("false")||s.includes("parado"))return"warn"; if(s.includes("ok")||s.includes("true")||s.includes("running"))return"ok"; return"nd"; }
function badge(v){ return `<span class="badge ${clsStatus(v)}">${escapeHtml(val(v))}</span>`; }

function renderTabela(id, dados, extraRenderer=null){
  const oldWrap = document.getElementById("w_"+id);
  if(oldWrap){ tableScrollState[id] = { left: oldWrap.scrollLeft, top: oldWrap.scrollTop }; }
  const el=document.getElementById(id); const rows=arr(dados); if(!el)return;
  if(rows.length===0){ el.innerHTML=`<div class="empty">Nenhum dado encontrado.</div>`; return; }
  let keys=[]; rows.forEach(r=>Object.keys(r||{}).forEach(k=>{ if(!keys.includes(k))keys.push(k); }));
  if(extraRenderer) keys=["Ações",...keys];
  const filterId="f_"+id;
  let html=`<div class="table-tools"><input class="filter" id="${filterId}" placeholder="Filtrar tabela..." onkeyup="filtrar('${filterId}','t_${id}')"><span class="pill">${rows.length} registro(s)</span></div>`;
  html+=`<div class="table-wrap" id="w_${id}"><table id="t_${id}"><thead><tr>${keys.map(k=>`<th>${escapeHtml(k)}</th>`).join("")}</tr></thead><tbody>`;
  rows.forEach((r,idx)=>{
    html+="<tr>";
    keys.forEach(k=>{
      if(k==="Ações"){ html+=`<td>${extraRenderer(r,idx)}</td>`; return; }
      const v=r?r[k]:""; const usarBadge=/status|estado|ativo|pendente|prote|sucesso|habilitado|dhcp|local|ping|winrm|carregado/i.test(k);
      html+=`<td>${usarBadge?badge(v):escapeHtml(v)}</td>`;
    });
    html+="</tr>";
  });
  html+="</tbody></table></div>"; el.innerHTML=html;
  const newWrap = document.getElementById("w_"+id);
  if(newWrap && tableScrollState[id]){ newWrap.scrollLeft = tableScrollState[id].left || 0; newWrap.scrollTop = tableScrollState[id].top || 0; }
}
function filtrar(inputId, tableId){ const termo=document.getElementById(inputId).value.toLowerCase(); document.querySelectorAll(`#${tableId} tbody tr`).forEach(tr=>{tr.style.display=tr.innerText.toLowerCase().includes(termo)?"":"none";}); }
function card(titulo, valor, detalhe, status){ const c=clsStatus(status||valor); const cc=c==="ok"?"card-ok":c==="warn"?"card-warn":c==="crit"?"card-crit":""; return `<div class="card ${cc}"><div class="card-title">${escapeHtml(titulo)}</div><div class="card-value">${escapeHtml(valor)}</div><div class="card-detail">${escapeHtml(detalhe||"")}</div></div>`; }

function processActions(r){ return `<button class="danger" onclick='killProc(${Number(r.PID)})'>Matar</button><button class="warn" onclick='restartProc(${Number(r.PID)}, ${JSON.stringify(r.Caminho||"")})'>Reiniciar</button>`; }
function serviceActions(r){ return `<button class="okbtn" onclick='svc("start_service",${JSON.stringify(r.Nome)})'>Iniciar</button><button class="danger" onclick='svc("stop_service",${JSON.stringify(r.Nome)})'>Parar</button><button class="warn" onclick='svc("restart_service",${JSON.stringify(r.Nome)})'>Reiniciar</button><button onclick='setSvcStartup(${JSON.stringify(r.Nome)})'>Startup</button>`; }
function softwareActions(r,idx){ window.__soft=window.__soft||[]; window.__soft[idx]=r; return `<button class="danger" onclick='uninstallSoft(${idx},false)'>Desinstalar</button><button class="warn" onclick='uninstallSoft(${idx},true)'>Desinstalar + limpeza</button>`; }
function sessionActions(r){ return `<button class="danger" onclick='logoffSession(${JSON.stringify(r.ID||"")}, ${JSON.stringify(r.Usuario||"")})'>Forçar logoff</button>`; }

function render(dados){
  if(!dados)return; ultimoJson=dados;
  const resumo=dados.Resumo||{}; const sistema=arr(dados.Sistema)[0]||{}; const seg=dados.Seguranca||{}; const patch=dados.Patches||{}; const arm=dados.Armazenamento||{}; const serv=dados.Servicos||{}; const users=dados.Usuarios||{};
  document.getElementById("titulo").innerText=`Inventário de ${dados.Computador||"-"}`;
  document.getElementById("metaComputador").innerText=`Computador: ${dados.Computador||"-"}`;
  document.getElementById("metaData").innerText=`Atualizado: ${dados.DataGeracao||"-"}`;
  document.getElementById("metaDuracao").innerText=`Duração: ${dados.DuracaoSegundos||"-"}s`;
  const discosCrit=arr(arm.Volumes).filter(x=>String(x.Status).toLowerCase().includes("crit")).length;
  const eventosCrit=arr(dados.Eventos).filter(x=>String(x.Nivel).toLowerCase().includes("crit")).length;
  const servParados=arr(serv.AutomaticosParados).length; const defender=arr(seg.Defender)[0]||{}; const reboot=arr(patch.RebootPendente)[0]||{}; const fwCrit=arr(seg.Firewall).filter(x=>String(x.Status).toLowerCase().includes("crit")).length;
  document.getElementById("cards").innerHTML=
    card("Saúde Geral",`${resumo.Score??"N/D"}/100`,resumo.Motivos||"",resumo.Status)+
    card("Status Coleta",dados.StatusColeta||"N/D","Resultado da última coleta",dados.StatusColeta)+
    card("Uptime",sistema.Uptime||"N/D","Desde o último boot",(sistema.UptimeDias>30?"Atencao":"OK"))+
    card("Discos críticos",discosCrit,"Volumes abaixo de 10%",discosCrit>0?"Critico":"OK")+
    card("Defender",defender.Status||"N/D","Antivírus e tempo real",defender.Status)+
    card("Reboot pendente",reboot.Status||"N/D",reboot.Motivos||"",reboot.Status)+
    card("Firewall crítico",fwCrit,"Perfis desativados",fwCrit>0?"Critico":"OK")+
    card("Eventos críticos",eventosCrit,"System/Application 72h",eventosCrit>0?"Critico":"OK")+
    card("Serviços parados",servParados,"Automáticos fora de execução",servParados>0?"Atencao":"OK")+
    card("Memória RAM", arr(dados.Hardware?.MemoriaResumo)[0]?.Total || "N/D", "Slots usados: " + (arr(dados.Hardware?.MemoriaResumo)[0]?.SlotsUsados || "N/D"), "OK")+
    card("Softwares",arr(dados.Software).length,"Programas encontrados","OK");

  renderTabela("tblSistema",dados.Sistema); renderTabela("tblDiag",[dados.Diagnostico]);
  renderTabela("tblUsers",users.UsuariosLocais); renderTabela("tblSessions",users.Sessoes,sessionActions); renderTabela("tblProfiles",users.Perfis); renderTabela("tblAdminsUsers",users.GruposAdministradores);
  renderTabela("tblHardwareBase",dados.Hardware?.Base); renderTabela("tblTipoEquip",dados.Hardware?.TipoEquipamento); renderTabela("tblCpu",dados.Hardware?.Processador); renderTabela("tblMemSlots",dados.Hardware?.MemoriaSlots); renderTabela("tblVideo",dados.Hardware?.Video); renderTabela("tblMonitores",dados.Hardware?.Monitores); renderTabela("tblUsb",dados.Hardware?.USB);
  renderTabela("tblDiscos",dados.Armazenamento?.Discos); renderTabela("tblVolumes",dados.Armazenamento?.Volumes); renderTabela("tblRedeIp",dados.Rede?.IP); renderTabela("tblAdaptadores",dados.Rede?.Adaptadores);
  renderTabela("tblSoftware",dados.Software,softwareActions);
  renderTabela("tblDefender",seg.Defender); renderTabela("tblBitlocker",seg.BitLocker); renderTabela("tblTpm",seg.TPM); renderTabela("tblSecure",seg.SecureBoot); renderTabela("tblFirewall",seg.Firewall); renderTabela("tblRdp",seg.RDP); renderTabela("tblShares",seg.Compartilhamentos);
  renderTabela("tblReboot",patch.RebootPendente); renderTabela("tblHotfix",patch.Hotfixes); renderTabela("tblUpdateSvc",patch.ServicosAtualizacao);
  renderTabela("tblSvcParados",serv.AutomaticosParados,serviceActions); renderTabela("tblProc",serv.TopProcessosMemoria,processActions); renderTabela("tblSvcAtivos",serv.Ativos,serviceActions);
  renderTabela("tblEventos",dados.Eventos); renderTabela("tblErros",dados.Erros);
}

async function iniciarColeta(){ await fetch(`/api/start?computer=${encodeURIComponent(alvo())}`); await atualizarEstado(); }
async function usarLocal(){ document.getElementById("computer").value=""; await iniciarColeta(); }

async function atualizarEstado(){
  try{
    const res=await fetch("/api/state"); const st=await res.json(); estadoAtual=st;
    const dot=document.getElementById("dot"); dot.className="dot "+(st.Rodando?"run":(st.Erro?"err":"ok"));
    document.getElementById("status").innerText=st.Rodando?"Coletando":(st.Erro?"Erro":"Pronto");
    document.getElementById("progress").style.width=`${st.Percentual||0}%`;
    document.getElementById("stage").innerText=`${st.Percentual||0}% - ${st.Etapa||"Aguardando"}`;
    renderTabela("tblHistorico",st.Historico||[]);
    if(st.Dados)render(st.Dados);
  }catch(e){ document.getElementById("status").innerText="Falha ao consultar servidor local"; document.getElementById("dot").className="dot err"; }
}

async function startAction(action, params={}){
  const body={computer:alvo(),action,params};
  const res=await fetch("/api/action/start",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
  const data=await res.json();
  document.getElementById("actionLog").innerText="";
  if(!data.ok){ alert(data.mensagem||"Ação não iniciada."); }
  await atualizarAcao();
}

async function atualizarAcao(){
  const res=await fetch("/api/action/state"); const st=await res.json();
  document.getElementById("actionProgress").style.width=`${st.Percentual||0}%`;
  document.getElementById("actionStage").innerText=`${st.Percentual||0}% - ${st.Etapa||"Aguardando ação"}`;
  
  const logs=arr(st.Logs).slice(-160).map(l=>`[${l.DataHora}] [${l.Nivel}] ${l.Mensagem}`).join("\n");
  document.getElementById("actionLog").innerText=logs||"Aguardando ação...";
}

async function abrirC(){ await startAction("open_share",{}); }
async function pcAction(a){
  if(a==="restart_pc"||a==="shutdown_pc"){
    const palavra=a==="restart_pc"?"reiniciar":"desligar";
    const ok=prompt(`Confirmar ${palavra} no alvo atual?\n1 - Executar\n0 - Sair`, "0");
    if(ok!=="1")return;
    const delay=prompt("Tempo em segundos antes da ação:", "10")||"10";
    await startAction(a,{delaySeconds:Number(delay)});
  } else { await startAction(a,{}); }
}
async function logoffSession(id,user){
  if(!id || id==="N/D"){ alert("Sessão sem ID válido."); return; }
  const ok=prompt(`Forçar logoff da sessão ${id} (${user||"usuário"})?\n1 - Executar\n0 - Sair`, "0");
  if(ok!=="1")return;
  await startAction("logoff_session",{id});
}
async function killProc(pid){ if(prompt(`Matar processo PID ${pid}?\n1 - Executar\n0 - Sair`, "0")==="1") await startAction("kill_process",{pid}); }
async function restartProc(pid,path){ if(prompt(`Reiniciar processo PID ${pid}?\n1 - Executar\n0 - Sair`, "0")==="1") await startAction("restart_process",{pid,path}); }
async function svc(action,name){ if(prompt(`${action} em ${name}?\n1 - Executar\n0 - Sair`, "0")==="1") await startAction(action,{name}); }
async function setSvcStartup(name){ const tipo=prompt("Digite Automatic, Manual ou Disabled:", "Manual"); if(!tipo)return; await startAction("set_service_startup",{name,startup:tipo}); }
async function uninstallSoft(idx,cleanup){
  const s=window.__soft[idx]; if(!s)return;
  const ok=prompt(`${cleanup?"Desinstalação com limpeza segura":"Desinstalação"} de:\n${s.Nome}\n\n1 - Executar\n0 - Sair`, "0");
  if(ok!=="1")return;
  await startAction("uninstall_software",{name:s.Nome,uninstallString:s.UninstallString,quietUninstallString:s.QuietUninstallString,installLocation:s.InstallLocation,registro:s.Registro,cleanup});
}
function exportarTxtSelecionado(){
  if(!ultimoJson){ alert("Nenhum inventário carregado ainda."); return; }
  const opcoes = [
    ["1","Sistema","Sistema"],
    ["2","Diagnostico","Diagnostico"],
    ["3","Hardware","Hardware"],
    ["4","Armazenamento","Armazenamento"],
    ["5","Rede","Rede"],
    ["6","Software","Software"],
    ["7","Usuarios","Usuarios"],
    ["8","Seguranca","Seguranca"],
    ["9","Patches","Patches"],
    ["10","Servicos","Servicos"],
    ["11","Eventos","Eventos"],
    ["12","Erros","Erros"],
    ["13","Resumo","Resumo"]
  ];
  const msg = "Marque os itens para exportar no TXT (ex: 1,3,6,13):\n" + opcoes.map(o=>`${o[0]} - ${o[1]}`).join("\n");
  const raw = prompt(msg, "1,2,3,4,5,13");
  if(raw===null) return;
  const escolhidos = String(raw).split(",").map(x=>x.trim()).filter(Boolean);
  const linhas = [];
  linhas.push("INVENTARIO CORPORATIVO - EXPORTACAO TXT");
  linhas.push(`Computador: ${val(ultimoJson.Computador)}`);
  linhas.push(`DataGeracao: ${val(ultimoJson.DataGeracao)}`);
  linhas.push("");
  for(const c of escolhidos){
    const item = opcoes.find(o=>o[0]===c);
    if(!item) continue;
    const sec = item[2];
    linhas.push("============================================================");
    linhas.push(sec.toUpperCase());
    linhas.push("============================================================");
    linhas.push(JSON.stringify(ultimoJson[sec] ?? "N/D", null, 2));
    linhas.push("");
  }
  if(linhas.length<=4){ alert("Nenhuma secao valida selecionada."); return; }
  const blob = new Blob([linhas.join("\n")],{type:"text/plain;charset=utf-8"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `inventario-${ultimoJson.Computador||"computador"}-seletivo.txt`;
  a.click();
  URL.revokeObjectURL(a.href);
}
async function encerrarServidor(){ if(confirm("Encerrar o servidor local do painel?")){ await fetch("/api/shutdown"); document.getElementById("stage").innerText="Servidor local encerrado. Pode fechar esta aba."; } }
async function lookupModeloOnline(){
  if(!ultimoJson){ alert("Execute uma coleta primeiro."); return; }
  const base = (ultimoJson.Hardware && ultimoJson.Hardware.Base && ultimoJson.Hardware.Base[0]) ? ultimoJson.Hardware.Base[0] : {};
  const serial = base.Serial || "";
  const fabricante = base.Fabricante || "";
  const modelo = base.Modelo || "";
  if(!serial || serial==="N/D"){ alert("Número de série não disponível no inventário."); return; }
  await startAction("online_model_lookup",{serial,fabricante,modelo});
}
async function lookupMonitorOnline(){
  if(!ultimoJson){ alert("Execute uma coleta primeiro."); return; }
  const mons = (ultimoJson.Hardware && ultimoJson.Hardware.Monitores) ? ultimoJson.Hardware.Monitores : [];
  const m = (Array.isArray(mons) ? mons[0] : mons) || {};
  const marca = m.Marca || "";
  const modelo = m.Modelo || m.Nome || "";
  const serie = m.Serie || "";
  if((!marca || marca==="N/D") && (!modelo || modelo==="N/D") && (!serie || serie==="N/D")){
    alert("Nenhum monitor com dados suficientes para busca online.");
    return;
  }
  await startAction("online_monitor_lookup",{marca,modelo,serie});
}
function iniciarTimers(){
  setInterval(atualizarEstado,1800); setInterval(atualizarAcao,1500);
  setInterval(()=>{ if(document.getElementById("autoRefresh").checked && estadoAtual && !estadoAtual.Rodando){ iniciarColeta(); } },1000*Number(document.getElementById("intervalo").value||60));
}
(function(){ iniciarTimers(); usarLocal(); })();
</script>
</body>
</html>
'@

if (-not (Test-Admin)) {
    Write-Host "[ERRO] Execute este script como Administrador." -ForegroundColor Red
    Write-Host "Clique com o botao direito no BAT e escolha 'Executar como administrador'." -ForegroundColor Yellow
    exit 1
}

New-Pasta $OutputPath
New-Pasta (Join-Path $OutputPath "Logs")
New-Pasta (Join-Path $OutputPath "LIVE")

$Porta = Get-PortaDisponivel -PortaInicial $Porta
$prefixo = "http://127.0.0.1:$Porta/"

$script:Estado = [ordered]@{ Rodando=$false; Percentual=0; Etapa="Aguardando"; Alvo=$env:COMPUTERNAME; Dados=$null; Erro=$null; Inicio=$null; Fim=$null; Job=$null; Historico=@() }
$script:AcaoEstado = [ordered]@{ Rodando=$false; Percentual=0; Etapa="Aguardando acao"; Alvo=$env:COMPUTERNAME; Acao=$null; Erro=$null; Job=$null; Logs=@(); Resultado=$null; Inicio=$null; Fim=$null; Historico=@() }

function Atualizar-JobInventario {
    if ($null -eq $script:Estado.Job) { return }
    try {
        $saida = @(Receive-Job -Job $script:Estado.Job -ErrorAction SilentlyContinue)
        foreach ($item in $saida) {
            if ($null -eq $item) { continue }
            if ($item.__tipo -eq "progresso") { $script:Estado.Percentual=[int]$item.Percentual; $script:Estado.Etapa=[string]$item.Etapa }
            if ($item.__tipo -eq "resultado") { $script:Estado.Dados=$item.Dados; $script:Estado.Percentual=100; $script:Estado.Etapa="Coleta concluida" }
        }
        if ($script:Estado.Job.State -in @("Completed","Failed","Stopped")) {
            if ($script:Estado.Job.State -eq "Failed") {
                $motivo = $script:Estado.Job.ChildJobs[0].JobStateInfo.Reason
                if ($motivo) { $script:Estado.Erro = $motivo.Message }
                $script:Estado.Etapa = "Falha na coleta"
            }
            $script:Estado.Rodando=$false; $script:Estado.Fim=Get-Date
            $status = if($script:Estado.Erro){"Erro"}elseif($script:Estado.Dados -and $script:Estado.Dados.StatusColeta){$script:Estado.Dados.StatusColeta}else{"Finalizado"}
            $score = if($script:Estado.Dados -and $script:Estado.Dados.Resumo){"$($script:Estado.Dados.Resumo.Score)/100"}else{"N/D"}
            $script:Estado.Historico = @([pscustomobject]@{DataHora=(Get-Date).ToString("dd/MM/yyyy HH:mm:ss"); Alvo=$script:Estado.Alvo; Status=$status; Score=$score; Duracao=if($script:Estado.Inicio){[math]::Round(((Get-Date)-$script:Estado.Inicio).TotalSeconds,2)}else{"N/D"}}) + @($script:Estado.Historico | Select-Object -First 19)
            Remove-Job -Job $script:Estado.Job -Force -ErrorAction SilentlyContinue
            $script:Estado.Job=$null
        }
    } catch { $script:Estado.Erro=$_.Exception.Message; $script:Estado.Rodando=$false; $script:Estado.Etapa="Erro ao atualizar job" }
}

function Atualizar-JobAcao {
    if ($null -eq $script:AcaoEstado.Job) { return }
    try {
        $saida = @(Receive-Job -Job $script:AcaoEstado.Job -ErrorAction SilentlyContinue)
        foreach ($item in $saida) {
            if ($null -eq $item) { continue }
            if ($item.__tipo -eq "progresso") { $script:AcaoEstado.Percentual=[int]$item.Percentual; $script:AcaoEstado.Etapa=[string]$item.Etapa }
            if ($item.__tipo -eq "log") { $script:AcaoEstado.Logs = @($script:AcaoEstado.Logs) + $item }
            if ($item.__tipo -eq "resultado") { $script:AcaoEstado.Resultado=$item.Resultado }
        }
        if ($script:AcaoEstado.Job.State -in @("Completed","Failed","Stopped")) {
            if ($script:AcaoEstado.Job.State -eq "Failed") {
                $motivo = $script:AcaoEstado.Job.ChildJobs[0].JobStateInfo.Reason
                if ($motivo) { $script:AcaoEstado.Erro = $motivo.Message; $script:AcaoEstado.Logs = @($script:AcaoEstado.Logs) + [pscustomobject]@{Nivel="ERRO";Mensagem=$motivo.Message;DataHora=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss")} }
                $script:AcaoEstado.Etapa = "Falha na acao"
            }
            else { $script:AcaoEstado.Etapa = "Acao concluida"; $script:AcaoEstado.Percentual = 100 }
            $script:AcaoEstado.Rodando=$false; $script:AcaoEstado.Fim=Get-Date
            $script:AcaoEstado.Historico = @([pscustomobject]@{DataHora=(Get-Date).ToString("dd/MM/yyyy HH:mm:ss"); Alvo=$script:AcaoEstado.Alvo; Acao=$script:AcaoEstado.Acao; Status=if($script:AcaoEstado.Erro){"Erro"}else{"OK"}; Duracao=if($script:AcaoEstado.Inicio){[math]::Round(((Get-Date)-$script:AcaoEstado.Inicio).TotalSeconds,2)}else{"N/D"}}) + @($script:AcaoEstado.Historico | Select-Object -First 19)
            Remove-Job -Job $script:AcaoEstado.Job -Force -ErrorAction SilentlyContinue
            $script:AcaoEstado.Job=$null
        }
    } catch { $script:AcaoEstado.Erro=$_.Exception.Message; $script:AcaoEstado.Rodando=$false; $script:AcaoEstado.Etapa="Erro ao atualizar acao" }
}

function Start-Coleta {
    param([string]$Alvo)
    Atualizar-JobInventario
    if ($script:Estado.Rodando) { return @{ ok=$false; mensagem="Ja existe uma coleta em andamento." } }
    if ([string]::IsNullOrWhiteSpace($Alvo)) { $Alvo = $env:COMPUTERNAME }
    $script:Estado.Rodando=$true; $script:Estado.Percentual=1; $script:Estado.Etapa="Preparando coleta"; $script:Estado.Alvo=$Alvo; $script:Estado.Erro=$null; $script:Estado.Inicio=Get-Date; $script:Estado.Fim=$null
    $script:Estado.Job = Start-Job -ScriptBlock $ScriptInventario -ArgumentList $Alvo
    return @{ ok=$true; mensagem="Coleta iniciada"; alvo=$Alvo }
}

function Start-Acao {
    param([string]$Alvo, [string]$Acao, [object]$Parametros)
    Atualizar-JobAcao
    if ($script:AcaoEstado.Rodando) { return @{ ok=$false; mensagem="Ja existe uma acao em andamento." } }
    if ([string]::IsNullOrWhiteSpace($Alvo)) { $Alvo = $env:COMPUTERNAME }
    $script:AcaoEstado.Rodando=$true; $script:AcaoEstado.Percentual=1; $script:AcaoEstado.Etapa="Preparando acao"; $script:AcaoEstado.Alvo=$Alvo; $script:AcaoEstado.Acao=$Acao; $script:AcaoEstado.Erro=$null; $script:AcaoEstado.Inicio=Get-Date; $script:AcaoEstado.Fim=$null; $script:AcaoEstado.Logs=@(); $script:AcaoEstado.Resultado=$null
    $script:AcaoEstado.Job = Start-Job -ScriptBlock $ScriptAcao -ArgumentList $Alvo, $Acao, $Parametros
    return @{ ok=$true; mensagem="Acao iniciada"; alvo=$Alvo; acao=$Acao }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefixo)
try { $listener.Start() }
catch {
    Write-Host "[ERRO] Nao foi possivel iniciar o servidor local em $prefixo" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Inventario Corporativo N3 LIVE V4 iniciado" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "URL: $prefixo" -ForegroundColor Green
Write-Host "Pressione CTRL+C nesta janela para encerrar." -ForegroundColor Yellow
Write-Host ""

if (-not $NaoAbrirNavegador) { Start-Process $prefixo }

$script:ServidorAtivo = $true

while ($listener.IsListening -and $script:ServidorAtivo) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $path = $req.Url.AbsolutePath.ToLowerInvariant()
        $query = Get-QueryParams $req.Url.Query
        Atualizar-JobInventario
        Atualizar-JobAcao

        switch ($path) {
            "/" { Send-Http -Contexto $ctx -Conteudo $HtmlPainel -ContentType "text/html; charset=utf-8" }
            "/api/start" {
                $resp = Start-Coleta -Alvo $query["computer"]
                Send-Http -Contexto $ctx -Conteudo (ConvertTo-JsonSeguro $resp)
            }
            "/api/state" {
                $estadoPublico = [ordered]@{
                    Rodando=$script:Estado.Rodando; Percentual=$script:Estado.Percentual; Etapa=$script:Estado.Etapa; Alvo=$script:Estado.Alvo; Erro=$script:Estado.Erro
                    Inicio=if($script:Estado.Inicio){$script:Estado.Inicio.ToString("dd/MM/yyyy HH:mm:ss")}else{$null}
                    Fim=if($script:Estado.Fim){$script:Estado.Fim.ToString("dd/MM/yyyy HH:mm:ss")}else{$null}
                    Dados=$script:Estado.Dados; Historico=$script:Estado.Historico
                }
                Send-Http -Contexto $ctx -Conteudo (ConvertTo-JsonSeguro ([pscustomobject]$estadoPublico))
            }
            "/api/action/start" {
                $body = Get-BodyJson -Request $req
                $resp = Start-Acao -Alvo ([string]$body.computer) -Acao ([string]$body.action) -Parametros $body.params
                Send-Http -Contexto $ctx -Conteudo (ConvertTo-JsonSeguro $resp)
            }
            "/api/action/state" {
                $acaoPublica = [ordered]@{
                    Rodando=$script:AcaoEstado.Rodando; Percentual=$script:AcaoEstado.Percentual; Etapa=$script:AcaoEstado.Etapa; Alvo=$script:AcaoEstado.Alvo; Acao=$script:AcaoEstado.Acao
                    Erro=$script:AcaoEstado.Erro; Logs=$script:AcaoEstado.Logs; Resultado=$script:AcaoEstado.Resultado; Historico=$script:AcaoEstado.Historico
                    Inicio=if($script:AcaoEstado.Inicio){$script:AcaoEstado.Inicio.ToString("dd/MM/yyyy HH:mm:ss")}else{$null}
                    Fim=if($script:AcaoEstado.Fim){$script:AcaoEstado.Fim.ToString("dd/MM/yyyy HH:mm:ss")}else{$null}
                }
                Send-Http -Contexto $ctx -Conteudo (ConvertTo-JsonSeguro ([pscustomobject]$acaoPublica))
            }
            "/api/shutdown" {
                Send-Http -Contexto $ctx -Conteudo (@{ ok=$true; mensagem="Servidor encerrando" } | ConvertTo-Json -Compress)
                $script:ServidorAtivo = $false
            }
            default {
                Send-Http -Contexto $ctx -Conteudo (@{ erro="Rota nao encontrada"; rota=$path } | ConvertTo-Json -Compress) -StatusCode 404
            }
        }
    }
    catch {
        try { if ($ctx) { Send-Http -Contexto $ctx -Conteudo (@{ erro=$_.Exception.Message } | ConvertTo-Json -Compress) -StatusCode 500 } } catch {}
    }
}

try { $listener.Stop() } catch {}
try { $listener.Close() } catch {}
Write-Host "Servidor local encerrado." -ForegroundColor Yellow



# OTIMIZAÇÃO TI V4.1 PLUS

> Suite técnica para manutenção, diagnóstico, otimização e suporte operacional em ambientes Windows.

![Windows](https://img.shields.io/badge/Windows-10%2F11%20%7C%20Server-blue)
![Batch](https://img.shields.io/badge/Batch-CMD-informational)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Status](https://img.shields.io/badge/status-V4.1%20PLUS-success)
![License](https://img.shields.io/badge/license-MIT-green)
![Modo](https://img.shields.io/badge/execu%C3%A7%C3%A3o-admin%20required-orange)

## Visão geral

**OTIMIZAÇÃO TI V4.1 PLUS** é uma solução técnica para padronizar rotinas de manutenção, reparo, diagnóstico e suporte em computadores Windows.

O projeto foi desenvolvido para apoiar operações de TI com foco em:

- limpeza profunda do sistema;
- reparo de integridade do Windows;
- otimização de desempenho;
- correção de rede;
- correção de impressoras;
- governança de recursos de IA do Windows;
- diagnóstico completo;
- manutenção rápida e avançada;
- inventário técnico em painel local;
- uso assistido de ferramentas portáteis, incluindo CrystalDiskInfo, TreeSize Free, Dism++ e Revo Uninstaller Pro.

A versão **V4.1 PLUS** adiciona melhorias de segurança, controle de concorrência, logs centralizados, modo *dry-run* para ações sensíveis e melhor organização dos módulos externos.

## Objetivo do projeto

O objetivo do **OTIMIZAÇÃO TI** é oferecer um orquestrador local, portátil e organizado para técnicos de suporte, analistas de infraestrutura e administradores que precisam executar rotinas repetitivas com mais padronização, rastreabilidade e segurança operacional.

Ele não substitui a análise técnica humana. O projeto funciona como um painel operacional para acelerar tarefas comuns, reduzir erros manuais e manter registro das ações executadas.

## Principais recursos

### Manutenção e otimização

- Limpeza de arquivos temporários do Windows.
- Limpeza multiusuário de caches temporários.
- Limpeza de cache de navegadores em múltiplos perfis.
- Limpeza de Windows Update e Delivery Optimization.
- Limpeza de relatórios WER, dumps e minidumps antigos.
- Limpeza de thumbnail cache e icon cache.
- Limpeza de lixeira com confirmação.
- Execução de `DISM /StartComponentCleanup`.
- Execução de `DISM /RestoreHealth`.
- Execução de `SFC /scannow`.
- Otimização de volumes fixos com `Optimize-Volume`.
- Aplicação de políticas com `gpupdate /force`.
- Comparativo de espaço em disco antes e depois da manutenção.

### Desempenho

- Criação e ativação do plano de energia **Desempenho Máximo**.
- Ajustes de energia para operação em AC.
- Rotinas de integridade e otimização do sistema.
- Flush DNS ao final do fluxo.

### Rede

- Flush e registro de DNS.
- Renovação de IP, quando o modo de execução permite.
- Limpeza de cache ARP e destination cache.
- Reset de TCP/IP e Winsock, exceto em modo remoto.
- Reset de WinHTTP proxy.
- Testes básicos de conectividade:
  - loopback;
  - IP público;
  - DNS;
  - HTTPS.

### Impressoras

- Inventário de impressoras instaladas.
- Limpeza de jobs travados.
- Reset do spooler.
- Limpeza da pasta `spool\PRINTERS`.
- Inicialização de serviços relacionados.
- Validação do `spoolsv.exe` com SFC.
- Relatório final do módulo.

### Governança de IA do Windows

O módulo de IA local foi reforçado na versão **V4.1 PLUS** com controles de segurança para diagnóstico, desativação, remoção e reversão de políticas relacionadas a recursos de IA do Windows.

Recursos disponíveis:

- diagnóstico;
- desativação por políticas;
- remoção Appx/Recall;
- remoção profunda protegida;
- bloqueio de reinstalação;
- remoção completa;
- reversão de políticas;
- *dry-run* completo.

Controles de segurança:

- modo *dry-run* para gerar relatório sem alterar o sistema;
- confirmação forte para ações destrutivas;
- uso de *allowlist* para filtros positivos;
- ações profundas bloqueadas por padrão;
- ações profundas liberadas somente com parâmetro explícito;
- edição JSON por parse estrutural, evitando substituições globais cegas;
- trilha de execução por item com status `WouldDo`, `Done`, `Failed` e `Skipped`.

### Inventário LIVE

O módulo **Inventário LIVE** abre um painel local para coleta, acompanhamento e exportação de dados técnicos.

Recursos principais:

- coleta local e remota;
- dados de sistema, hardware, armazenamento, rede, software, usuários, segurança, patches, serviços e eventos;
- diagnóstico remoto com normalização de alvo;
- validação de WinRM e portas `5985`/`5986`;
- mensagens orientativas para falhas comuns;
- fallback com ajuste de `TrustedHosts` em cenários por IP, quando aplicável;
- painel com progresso e histórico de coletas e ações;
- exportação em JSON;
- exportação TXT seletiva por seções escolhidas.

### Ferramentas portáteis

O projeto organiza ferramentas externas opcionais em uma estrutura própria:

- CrystalDiskInfo;
- TreeSize Free;
- Dism++;
- Revo Uninstaller Pro.

O **Dism++** permanece em modo **manual assistido**. O script apenas abre a ferramenta mediante confirmação forte e não automatiza cliques ou rotinas internas do executável.

## Estrutura do projeto

```text
.
├── OtimizacaoTI_V4_PLUS.bat
├── modules/
│   ├── OtimizacaoTI_AI_Local.ps1
│   └── OtimizacaoTI_ClassicApps.ps1
├── payloads/
│   └── ClassicApps/
├── tools/
│   ├── portable/
│   │   ├── CrystalDiskInfo/
│   │   ├── TreeSizeFree/
│   │   ├── DismPP/
│   │   └── RevoUninstallerPro/
│   └── inventario/
│       └── Inventario-Corporativo-N3-LIVE-V4.ps1
└── docs/
```

### Arquivos e pastas principais

| Caminho | Descrição |
|---|---|
| `OtimizacaoTI_V4_PLUS.bat` | Orquestrador principal do sistema. |
| `modules/OtimizacaoTI_AI_Local.ps1` | Módulo de IA local com *dry-run*, trilha de ações e controles de segurança. |
| `modules/OtimizacaoTI_ClassicApps.ps1` | Módulo para apps clássicos do Windows. |
| `payloads/ClassicApps/` | Payloads locais usados pelo módulo de apps clássicos. |
| `tools/portable/` | Ferramentas externas opcionais. |
| `tools/inventario/` | Módulo de Inventário LIVE com painel local. |
| `docs/` | Documentação técnica do projeto. |

## Requisitos

- Windows 10, Windows 11 ou Windows Server compatível.
- PowerShell 5.1 ou superior.
- Execução como administrador.
- Permissão para execução de scripts PowerShell, quando aplicável.
- Acesso local aos módulos e ferramentas opcionais incluídas no projeto.

## Como executar

1. Baixe ou clone este repositório.
2. Extraia os arquivos em uma pasta local.
3. Clique com o botão direito em `OtimizacaoTI_V4_PLUS.bat`.
4. Selecione **Executar como administrador**.
5. Escolha a opção desejada no menu principal.
6. Consulte o log gerado ao final da execução.

> Algumas rotinas exigem privilégios administrativos e podem solicitar confirmação adicional antes de alterar componentes sensíveis do sistema.

## Menu principal

| Opção | Função |
|---|---|
| `1` | Limpeza profunda do Windows |
| `2` | Otimização de desempenho máximo |
| `3` | Resolver problema de rede |
| `4` | Resolver problema de impressora |
| `5` | Remover recursos de IA do Windows |
| `6` | Apps clássicos do Windows |
| `7` | Diagnóstico completo do sistema |
| `8` | Manutenção rápida completa |
| `9` | Manutenção completa avançada |
| `I` | Inventário LIVE |
| `T` | Ferramentas portáteis |
| `U` | Sessões de usuário |
| `M` | Alterar modo de execução |
| `0` | Sair |

## Modos de execução

| Modo | Descrição |
|---|---|
| `COMPLETO` | Executa o fluxo normal das rotinas selecionadas. |
| `SEGURO` | Preserva um comportamento mais conservador em operações sensíveis. |
| `REMOTO` | Evita comandos que podem derrubar conectividade remota. |

O modo **REMOTO** é recomendado quando a máquina está sendo acessada por RDP, ferramenta de suporte remoto, VPN ou qualquer canal que possa ser afetado por reset de rede.

## Fluxo de inicialização

Ao iniciar, o orquestrador executa as seguintes etapas:

1. Valida privilégio administrativo.
2. Solicita elevação via UAC, se necessário.
3. Cria pastas base.
4. Cria arquivo de log da sessão.
5. Valida lock de execução.
6. Detecta lock ativo, antigo ou corrompido.
7. Solicita confirmação para sobrescrever lock ativo.
8. Remove lock antigo ou inválido.
9. Registra novo lock com PID e timestamp.
10. Inicia o menu principal.

## Segurança operacional

A solução adota alguns princípios para reduzir risco durante a execução:

- execução com privilégio administrativo controlado;
- lock de execução para evitar concorrência;
- logs centralizados;
- confirmações fortes para ações sensíveis;
- separação entre funções core e ferramentas externas;
- modo remoto para evitar perda de conectividade;
- *dry-run* em ações de maior impacto;
- contagem separada de avisos e erros;
- wrappers para comandos idempotentes.

### Confirmações fortes

Algumas ações exigem digitação de texto exato antes da execução, como:

- `ABRIR DISM++`
- `LOGOFF FORCADO`

Essa abordagem reduz o risco de execução acidental em operações críticas.

## Logs

Todos os logs são centralizados em:

```text
%ProgramData%\OtimizacaoTI\Logs
```

Cada execução gera um arquivo único por timestamp.

O resumo final inclui:

- total de avisos;
- total de erros;
- necessidade de reinício;
- status geral da execução.

## Idempotência e contagem de avisos

A versão **V4.1 PLUS** separa comandos tolerantes a falhas esperadas por meio de wrappers dedicados:

- `:run_soft`
- `:ps_soft`

Com isso, retornos esperados, como tentativa de encerrar processo inexistente, não poluem indicadores de erro real.

## Módulo 1: Limpeza profunda

Executa rotinas de limpeza do sistema, cache, temporários e componentes do Windows.

Principais ações:

- limpeza de `%TEMP%`, `%TMP%` e `Windows\Temp`;
- limpeza multiusuário de caches;
- limpeza de cache de navegadores;
- limpeza de Windows Update;
- limpeza de Delivery Optimization;
- limpeza de WER e minidumps antigos;
- limpeza de thumbnail cache e icon cache;
- limpeza da lixeira com confirmação;
- execução de `DISM /StartComponentCleanup`;
- execução de `ipconfig /flushdns`;
- comparativo de espaço antes e depois.

## Módulo 2: Otimização

Executa rotinas voltadas a desempenho, integridade e estabilidade.

Principais ações:

- cria e ativa o plano `Desempenho Máximo`;
- ajusta políticas de energia;
- executa `DISM /RestoreHealth`;
- executa `SFC /scannow`;
- executa `Optimize-Volume`;
- executa `gpupdate /force`;
- realiza `flushdns` final.

## Módulo 3: Rede

Executa diagnóstico e correções de rede.

Principais ações:

- flush e registro de DNS;
- release e renew de IP, exceto em modo remoto;
- limpeza de ARP;
- limpeza de destination cache;
- reset TCP/IP e Winsock, exceto em modo remoto;
- reset WinHTTP proxy;
- testes de conectividade.

## Módulo 4: Impressora

Executa manutenção do spooler e diagnóstico de impressão.

Principais ações:

- inventário de impressoras;
- limpeza de jobs travados;
- reset do spooler;
- limpeza de `spool\PRINTERS`;
- inicialização de serviços relacionados;
- validação de `spoolsv.exe`;
- relatório final.

## Módulo 5: IA do Windows

Executa diagnóstico, desativação, bloqueio, remoção e reversão de políticas relacionadas a recursos de IA do Windows.

O módulo possui proteções adicionais na versão **V4.1 PLUS**:

- *dry-run* completo;
- confirmação forte;
- *allowlist*;
- ações profundas bloqueadas por padrão;
- trilha técnica de planejamento e execução;
- tentativa de backup de registro;
- tentativa de ponto de restauração.

> Recomenda-se executar o *dry-run* antes de qualquer remoção ou alteração profunda.

## Módulo 6: Apps clássicos

Executa rotinas relacionadas a aplicativos clássicos do Windows.

Recursos:

- habilitação do Photo Viewer clássico;
- instalação ou registro de payloads locais de Paint, Snipping Tool e Notepad;
- tentativa de instalação do Photos Legacy via `winget`.

Observação:

- Se o objetivo for manter apenas manutenção e diagnóstico, sem instalação de apps clássicos, este módulo pode ser removido junto com `payloads/ClassicApps`.
- No estado atual do projeto, `payloads/ClassicApps` é utilizado pelo menu `6`.

## Menu T: Ferramentas portáteis

Abre ferramentas externas opcionais:

- `CrystalDiskInfoPortable.exe`;
- `TreeSizeFree.exe`;
- `Dism++`;
- `Revo Uninstaller Pro`.

O Dism++ exige confirmação forte antes de abrir. O Revo Uninstaller Pro deve ser usado de forma manual assistida para desinstalação avançada e limpeza de sobras de programas.

## Menu I: Inventário LIVE

Inicia painel local em tempo real para inventário e ações administrativas.

Módulo executado:

```text
tools/inventario/Inventario-Corporativo-N3-LIVE-V4.ps1
```

Pasta dedicada de saída e logs:

```text
Inventario Log
```

Essa pasta é separada do log técnico principal.

## Menu U: Sessões de usuário

Permite gerenciar sessões de usuário locais.

Recursos:

- lista sessões usando `quser`;
- força logoff de outros usuários com confirmação forte;
- preserva a sessão atual.

Confirmação exigida:

```text
LOGOFF FORCADO
```

## Boas práticas de uso

1. Execute sempre como administrador.
2. Use o modo **REMOTO** quando estiver conectado remotamente.
3. Rode o *dry-run* no módulo de IA antes de remoções.
4. Leia as confirmações antes de prosseguir.
5. Valide o log ao final da operação.
6. Reinicie o computador quando o resumo final indicar necessidade.
7. Evite executar múltiplas instâncias ao mesmo tempo.
8. Use ferramentas externas, como Dism++, apenas com análise técnica.

## Recomendações para publicação no GitHub

Antes de publicar, revise:

- dados pessoais em comentários ou logs;
- arquivos temporários;
- executáveis de terceiros dentro de `tools/portable`;
- payloads redistribuíveis em `payloads/ClassicApps`;
- licença de uso;
- permissões de distribuição de ferramentas externas;
- binários pagos ou proprietários, como **Revo Uninstaller Pro**, devem respeitar a licença do fornecedor e, em repositórios públicos, podem ser documentados como dependência opcional em vez de serem redistribuídos diretamente;
- prints, logs ou evidências que possam conter nomes de máquina, domínio, IPs internos ou usuários.

## Observação sobre ferramentas de terceiros

As ferramentas em `tools/portable/` são tratadas como recursos auxiliares e opcionais.

Caso o repositório seja público, valide a licença de cada ferramenta antes de distribuir os executáveis diretamente. Ferramentas proprietárias ou pagas, como **Revo Uninstaller Pro**, devem ser usadas somente quando houver licença válida e permissão de uso/distribuição conforme os termos do fornecedor.

Uma alternativa recomendada para repositórios públicos é manter apenas a estrutura de pastas e a documentação de instalação, sem incluir executáveis proprietários.

## Aviso técnico

Este projeto executa comandos administrativos no Windows. Algumas ações podem alterar configurações do sistema, limpar caches, reiniciar serviços, remover políticas, resetar rede ou exigir reinicialização.

Use em ambiente controlado, revise os logs e mantenha backups quando necessário.

## Roadmap sugerido

- [ ] Criar documentação individual por módulo.
- [ ] Adicionar exemplos de execução com prints.
- [ ] Criar changelog formal.
- [ ] Adicionar seção de troubleshooting.
- [ ] Criar assinatura/hash dos arquivos principais.
- [ ] Criar modo de exportação de relatório consolidado.
- [ ] Adicionar testes básicos de validação dos módulos PowerShell.
- [ ] Separar dependências opcionais em pacote externo.

## Licença

Este projeto está licenciado sob a licença **MIT**, uma licença aberta e permissiva que permite uso, cópia, modificação, distribuição e sublicenciamento, desde que o aviso de copyright e a licença sejam mantidos.

Consulte o arquivo [`LICENSE`](./LICENSE) para mais detalhes.

## Autor

Desenvolvido por **Felipe Brasilio**.

---

**OTIMIZAÇÃO TI V4.1 PLUS**  
Manutenção, diagnóstico e suporte Windows com mais padronização, rastreabilidade e controle operacional.

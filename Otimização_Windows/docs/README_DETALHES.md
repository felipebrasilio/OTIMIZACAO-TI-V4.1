# OTIMIZACAO TI V4.1 PLUS - DOCUMENTACAO TECNICA

## Autor e objetivo
Eu desenvolvi a solucao **OTIMIZACAO TI** para padronizar manutencao tecnica de Windows com foco em:
- limpeza profunda,
- reparo de integridade,
- performance,
- rede,
- impressao,
- governanca de recursos de IA do Windows,
- suporte operacional com ferramentas portateis.

A versao atual e a **V4.1 PLUS**, com hardening de seguranca, dry-run no modulo de IA e organizacao de ferramentas externas.

## Estrutura do projeto
- `OtimizacaoTI_V4_PLUS.bat`: orquestrador principal.
- `modules/OtimizacaoTI_AI_Local.ps1`: modulo de IA local com dry-run e trilha de acoes.
- `modules/OtimizacaoTI_ClassicApps.ps1`: modulo de apps classicos.
- `payloads/ClassicApps/`: payloads locais para apps classicos (necessario somente para opcoes de instalacao classica do Modulo 6).
- `tools/portable/`: ferramentas externas opcionais.
  - `CrystalDiskInfo/`
  - `TreeSizeFree/`
  - `DismPP/`
- `tools/inventario/`: modulo de Inventario LIVE (painel web local).
- `docs/`: documentacao tecnica.

## Principios operacionais
1. Execucao com privilegio administrativo.
2. Lock de execucao para evitar concorrencia.
3. Log centralizado em `%ProgramData%\\OtimizacaoTI\\Logs`.
4. Confirmacao forte para acoes sensiveis.
5. Separacao entre operacoes core e ferramentas externas.

## Fluxo de inicializacao
1. O script valida privilegio admin.
2. Se necessario, eleva via UAC.
3. Cria pastas base e log.
4. Valida lock ativo/stale:
  - lock ativo: solicita confirmacao para override,
  - lock antigo/corrompido: remove automaticamente.
5. Registra lock com PID e timestamp.
6. Inicia log da sessao.

## Menu principal
- `[1]` Limpeza profunda do Windows
- `[2]` Otimizacao de desempenho maximo
- `[3]` Resolver problema de rede
- `[4]` Resolver problema de impressora
- `[5]` Remover recursos de IA do Windows
- `[6]` Apps classicos do Windows
- `[7]` Diagnostico completo do sistema
- `[8]` Manutencao rapida completa
- `[9]` Manutencao completa avancada
- `[I]` Inventario LIVE
- `[T]` Ferramentas portateis
- `[U]` Sessoes de usuario
- `[M]` Alterar modo de execucao
- `[0]` Sair

## Modos de execucao
- `COMPLETO`: executa todo o fluxo normal.
- `SEGURO`: preserva fluxo conservador para operacoes sensiveis (em especial IA profunda).
- `REMOTO`: evita comandos que derrubam conectividade remota.

## Modulo 1 - Limpeza profunda
Funcoes principais:
- limpeza de `%TEMP%`, `%TMP%`, `Windows\\Temp`;
- limpeza multiusuario de caches temporarios e crash dumps;
- limpeza de cache de navegadores multi-perfil;
- limpeza de caches de Windows Update e Delivery Optimization;
- limpeza de WER/minidumps antigos;
- limpeza de thumbnail/icon cache;
- limpeza de lixeira (confirmacao);
- `DISM /StartComponentCleanup`;
- `ipconfig /flushdns`;
- comparativo de espaco em disco antes/depois.

## Modulo 2 - Otimizacao
Funcoes principais:
- cria/ativa plano `Desempenho Maximo`;
- ajusta politicas de energia em AC;
- `DISM /RestoreHealth`;
- `SFC /scannow`;
- `Optimize-Volume` em unidades fixas;
- `gpupdate /force`;
- `flushdns` final.

## Modulo 3 - Rede
Funcoes principais:
- DNS flush/register;
- release/renew de IP (exceto modo remoto);
- limpeza ARP e destination cache;
- reset TCP/IP e Winsock (exceto modo remoto);
- reset WinHTTP proxy;
- testes de conectividade (loopback, IP publico, DNS e HTTPS).

## Modulo 4 - Impressora
Funcoes principais:
- inventario de impressoras;
- limpeza de jobs travados;
- reset do spooler e pasta `spool\\PRINTERS`;
- inicializacao de servicos relacionados;
- validacao `spoolsv.exe` com SFC;
- relatorio final.

## Modulo 5 - IA do Windows (hardening V4.1)
Submenu:
- diagnostico,
- desativacao por politicas,
- remocao Appx/Recall,
- remocao profunda (guardada),
- bloqueio de reinstalacao,
- remocao completa,
- reversao de politicas,
- dry-run completo.

### Controles de seguranca
- **dry-run**: gera relatorio sem alterar o sistema.
- **confirmacao forte**: texto exato para operacoes destrutivas.
- **allowlist**: filtros positivos para Appx/features/tasks/CBS.
- **acoes profundas bloqueadas por padrao**: requer `-UnsafeDeepActions`.
- **edicao JSON por parse estrutural**: sem replace global cego.

### Saida tecnica
- trilha de planejamento e execucao por item (WouldDo, Done, Failed, Skipped);
- backups de registro e tentativa de ponto de restauracao.

## Modulo 6 - Apps classicos
- habilita Photo Viewer classico;
- instala/registre payloads locais de Paint/Snipping/Notepad;
- tentativa de Photos Legacy via winget.

Observacao de dependencia:
- se o objetivo for manter apenas manutencao/diagnostico e nao usar instalacao de apps classicos, este modulo pode ser removido junto com `payloads/ClassicApps`.
- no estado atual do projeto, `payloads/ClassicApps` e utilizado pelo menu `[6]`.

## Menu T - Ferramentas portateis
- abre `CrystalDiskInfoPortable.exe`;
- abre `TreeSizeFree.exe`;
- abre `Dism++` com confirmacao forte (`ABRIR DISM++`).

Observacao tecnica:
- Dism++ permanece **manual assistido**. O script nao automatiza cliques nem rotinas internas do executavel.
- Isso reduz risco operacional e melhora previsibilidade.

## Menu I - Inventario LIVE
- inicia painel local em tempo real para inventario e acoes administrativas;
- executa modulo: `tools/inventario/Inventario-Corporativo-N3-LIVE-V4.ps1`;
- usa pasta dedicada de saida/logs: `Inventario Log` (separada de `Log Tecnico`).

### Recursos principais do Inventario LIVE
- coleta local/remota de sistema, hardware, armazenamento, rede, software, usuarios, seguranca, patches, servicos e eventos;
- diagnostico remoto com normalizacao de alvo (hostname/IP/share);
- validacao de conectividade WinRM + portas 5985/5986 + mensagens orientativas;
- fallback com ajuste automatico de TrustedHosts para cenarios por IP quando aplicavel;
- painel com progresso e historico de coleta/acoes.

### Exportacao de resultado
- `Exportar JSON`: gera arquivo completo;
- `Exportar TXT Seletivo`: salva arquivo `.txt` simples contendo apenas as secoes escolhidas (marcacao por lista de opcoes).

## Menu U - Sessoes de usuario
- lista sessoes via `quser`;
- forca logoff de outros usuarios com confirmacao forte (`LOGOFF FORCADO`);
- preserva sessao atual.

## Contagem de avisos e idempotencia
A V4.1 separa comandos idempotentes com wrappers dedicados:
- `:run_soft`
- `:ps_soft`

Com isso, retornos esperados (ex.: `taskkill` sem processo ativo) nao poluem indicadores de erro real.

## Logs
- caminho: `%ProgramData%\\OtimizacaoTI\\Logs`.
- cada execucao gera arquivo unico por timestamp.
- resumo final inclui:
  - total de avisos,
  - total de erros,
  - necessidade de reinicio.

## Organizacao para manutencao manual
- alteracoes do core: `OtimizacaoTI_V4_PLUS.bat` e `modules/*.ps1`.
- ferramentas externas: `tools/portable/*`.
- sem dependencia de scripts legados externos.

## Boas praticas de uso
1. Executar sempre como administrador.
2. Rodar dry-run no modulo de IA antes de remocoes.
3. Usar Dism++ de forma manual e consciente.
4. Validar logs ao final de cada operacao.

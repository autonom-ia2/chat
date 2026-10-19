# #1709 — Motores WAHA de produção: leitura de arquitetura e logs (17/10/2026)

Leitura só de leitura, aprovada pelo Rodrigo ("pode entrar nos wahas como precisar"). Nada foi alterado: sem restart, update, env, sessão ou mensagem. Acesso pelos aliases SSH `hubsegs` (wa-hub) e `autonomia` (wa-autonomia). Credenciais não foram lidas; do env do serviço só foi lida a variável `WHATSAPP_DEFAULT_ENGINE`.

Pergunta: a produção sofre do problema visto no M2 (`docs/audit/2026-10-17-1709-gows-panic.md`), em que o GOWS deu `oneof type already set` e `fatal error: found bad pointer in Go heap` rodando sob emulação amd64 (qemu-user) num host aarch64?

## wa-hub (alias `hubsegs`, nó `srv777557`, manager Leader do Swarm)

| Item | Valor |
|---|---|
| `uname -m` do host | `x86_64` |
| `docker info` Architecture | `x86_64` (nó Swarm: `x86_64`) |
| Imagem do serviço `waha_waha-plus` | `devlikeapro/waha-plus@sha256:ac5d6c13…9598` |
| Plataforma no spec do serviço | nenhuma restrição (`Placement.Platforms = null`) |
| Arquitetura da imagem em uso | `linux/amd64` |
| `uname -m` dentro do container | `x86_64` |
| binfmt_misc no host | só `python3.10` (nenhum handler qemu) |
| Engine | `WHATSAPP_DEFAULT_ENGINE=GOWS` |
| Container atual | `134b71d3cb4c`, no ar desde 16/10 15:31:33 UTC, `RestartCount=0` |
| Logs cobertos | 16/10 15:29:50 → 17/10 09:14:47 UTC (211.159 linhas + 97 do container que falhou) |
| `found bad pointer` | 0 |
| `fatal error` | 0 |
| `oneof type already set` | 0 |
| `Panic happened` | 0 |
| `panic:` | 0 |
| `Stream error, reconnecting` | 0 |
| (extra) `SIGSEGV`, `goroutine `, `runtime: ` | 0 |
| Kernel (journal 7 dias): OOM/segfault | 0 |

Tarefas do serviço (histórico do Swarm guarda 5):

| Tarefa criada (UTC) | Fim (UTC) | Estado | Exit |
|---|---|---|---|
| 26/09 14:16 | (anterior) | shutdown | 137 |
| 02/10 11:32 | (anterior) | shutdown | 137 |
| 12/10 15:34 | 16/10 ~15:28 | failed | 0 (morto pelo desligamento do host) |
| 16/10 15:29 | 16/10 15:31:19 | failed | 1 — `GOWS did not start after 10000 ms` |
| 16/10 15:31 | — | **running** | — |

Na semana: 1 queda por desligamento do host e 1 falha de boot logo depois; nenhum crash do GOWS em operação.

## wa-autonomia (alias `autonomia`, nó `srv862087`, manager Leader do Swarm)

| Item | Valor |
|---|---|
| `uname -m` do host | `x86_64` |
| `docker info` Architecture | `x86_64` (nó Swarm: `x86_64`) |
| Imagem do serviço `waha_waha-plus` | `devlikeapro/waha-plus@sha256:ac5d6c13…9598` (a mesma do wa-hub) |
| Plataforma no spec do serviço | nenhuma restrição (`Placement.Platforms = null`) |
| Arquitetura da imagem em uso | `linux/amd64` |
| `uname -m` dentro do container | `x86_64` |
| binfmt_misc no host | só `python3.10` (nenhum handler qemu) |
| Engine | `WHATSAPP_DEFAULT_ENGINE=GOWS` |
| Container atual | `8e4de8cfab4c`, no ar desde 16/10 18:44:36 UTC, `RestartCount=0` |
| Logs cobertos | 14/10 22:18:54 → 16/10 18:18:06 (container anterior, 41.828 linhas) e 16/10 18:44:44 → 17/10 09:15:05 (atual, 12.015 linhas) |
| `found bad pointer` | 0 |
| `fatal error` | 0 |
| `oneof type already set` | 0 |
| `Panic happened` | 0 |
| `panic:` | 0 |
| `Stream error, reconnecting` | 0 |
| (extra) `SIGSEGV`, `goroutine `, `runtime: ` | 0 |
| Kernel (journal 7 dias): OOM/segfault | 0 |

Tarefas do serviço:

| Tarefa criada (UTC) | Fim (UTC) | Estado | Exit |
|---|---|---|---|
| 12/10 15:06 | (anterior) | failed | 137 |
| 12/10 15:10 | (anterior) | failed | 137 |
| 12/10 15:14 | (anterior) | shutdown | 143 |
| 12/10 15:33 | 16/10 ~18:18 | failed | 255 (morto pelo desligamento do host) |
| 16/10 18:44 | — | **running** | — |

Na semana: 4 trocas de tarefa em 27 min em 12/10 (exits 137/137/143, os logs dessas tarefas não existem mais, então a causa não pôde ser lida) e 1 queda por desligamento do host em 16/10.

## Outros fatos observados

- **Os dois hosts foram desligados pelo hipervisor em 16/10** (`qemu-ga: guest-shutdown called` + `System is powering down (hypervisor initiated shutdown)`): wa-hub às 14:54, wa-autonomia às 18:18 (horário local do host). Voltaram com kernel novo (`5.15.0-198`). As quedas do WAHA nesse dia vêm daí, não do GOWS. Depois do boot, o `UpdatedAt` dos dois serviços mudou (15:28:56 e 18:44:26 UTC); não investiguei o que reaplicou o spec.
- O `qemu-ga` é o agente de convidado da VM KVM da Hostinger: virtualização por hardware, com CPU x86_64 nativa. **Não é** a tradução de instruções do qemu-user (`qemu-x86_64` via binfmt) que causou o problema no M2.
- No wa-hub, a falha de 16/10 15:31 foi `GOWS did not start after 10000 ms` (o GOWS demorou para subir logo após o boot); o Swarm subiu outra tarefa 2 min depois e ela segue no ar. Não há panic nem stack nessa tarefa.
- Erros de nível 50 existem, mas são de outra natureza: no wa-hub, 4.116 `APIError 404` e ~640 erros de insert nas tabelas do app Chatwoot (`app_chatwoot_chatwoot_messages`, `app_chatwoot_whatsapp_acks`); nos dois, `Error reading from websocket` e `Failed to fetch message capping`, além de poucos `Undecryptable message`. Nenhum é corrupção de memória do Go. Ficam fora deste escopo.

## Limites da leitura

- **wa-hub:** só há logs desde 16/10 15:29 (~18 h). O container de 12/10 a 16/10 foi removido junto com seus logs, então a semana anterior não pôde ser contada.
- **wa-autonomia:** há ~2,5 dias de log (de 14/10 22:18 em diante). De 12/10 até 14/10 22:18 o log já tinha rodado (json-file, `max-size=100m`, `max-file=10`) ou foi descartado com os containers removidos.
- O histórico do Swarm guarda só 5 tarefas (`TaskHistoryRetentionLimit=5`); restarts antes delas não são visíveis.
- A busca cobriu o texto do log inteiro (stdout e stderr do container, inclusive o do GOWS, que aparece em ~100 mil linhas no wa-hub). Um panic do GOWS que não chegasse ao stderr não seria visto, mas também deixaria um exit diferente de zero com o host no ar, e isso não aparece nos períodos cobertos.

## Conclusão

1. **A produção é amd64 nativo.** Os dois hosts são x86_64, a imagem em uso é `linux/amd64`, o container responde `x86_64` e não há handler qemu no binfmt. O GOWS roda sem tradução de instruções, ao contrário do M2.
2. **Não há sinal do mesmo problema** nos períodos com log (wa-hub 18 h; wa-autonomia ~2,5 dias): zero `found bad pointer`, `fatal error`, `oneof type already set`, `Panic happened`, `panic:` e `Stream error, reconnecting`, zero OOM/segfault no kernel. As quedas da semana têm causa conhecida (desligamento do host pelo hipervisor em 16/10) ou não puderam ser lidas (wa-autonomia, 12/10 15:06–15:33, logs já removidos).
3. Isso reforça a hipótese do relatório do M2 (bug de emulação qemu-user), mas não a prova: a cobertura é curta. Para fechar com mais base, repetir a contagem daqui a alguns dias, quando os containers atuais tiverem uma semana de log.

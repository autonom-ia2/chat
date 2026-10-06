# #995 — requisito Serve confirmado e aceite local Autonomia

Checkpoint de 6 de outubro de 2026, após a coleta AWS Autonomia concluída às 09:31:57 UTC (06:31:57 em São Paulo). Esta nota sucede `995-runtime-resume-20261006.md`. É uma síntese das saídas observadas, não uma substituição dos recibos operacionais. A autorização de Rodrigo para continuidade, testes, revisões e publicação com gates verdes permanece válida.

## Resultado desta rodada

- A conexão normal M4→VPS respondeu. O resultado anterior de Serve foi reconciliado por leitura: a classe real era `TimeoutExpired`; rollback `already_absent/config_restored=true`.
- Uma consulta posterior de Serve retornou `{}`, confirmando a ausência de mounts naquele instante.
- O próprio Tailscale confirmou que **Serve não está habilitado na tailnet e aguarda consentimento administrativo**. Não se trata mais de hipótese derivada somente da duração do timeout.
- Display/gateway Autonomia foram iniciados e verificados na release instalada 3783. Hub2You e os 115 containers foram preservados.
- Os 42 testes negativos locais dos dois gateways passaram: 21 por stack. Essa prova usa loopback, não HTTPS.
- O diagnóstico A6 da Autonomia foi executado com controle próprio fresco e limpeza conclusiva, sem alterar IAM ou liberar o corte.
- Nenhum novo apply de Serve, Funnel, ACL, overlay Rails, merge/deploy Rails, corte dos Macs, B0, partida de publisher/manager ou habilitação da flag global ocorreu nesta rodada.

## Causa do bloqueio HTTPS

Pelo caminho SSH normal, a leitura do resultado `/tmp/instagram-serve_20261006T085100Z_a8cb9b602f434245a1919424e872c56c.result.json` retornou:

```json
{"status":"failed","failure_class":"TimeoutExpired","failure_code":"bounded_command_or_io_failure","rollback":{"state":"already_absent","config_restored":true}}
```

A consulta de status indicou backend `Running` e `CertDomains=null`. Esse campo, isoladamente, foi tratado como indício, não como conclusão.

Depois de conferir a API no cliente oficial, executou-se somente a consulta de requisitos:

```sh
tailscale debug localapi POST '/localapi/v0/query-feature?feature=serve'
```

PID Mac 24430; resposta do servidor:

```json
{"Text":"Serve is not enabled on your tailnet.\nTo enable, visit:","ShouldWait":true}
```

A resposta também trouxe a URL administrativa específica do nó. A URL não é uma credencial, mas foi omitida deste registro público porque não é necessária à prova. Nenhuma alteração de configuração é feita por essa consulta de requisitos.

A documentação oficial explica que Serve HTTPS exige certificados habilitados e que o fluxo interativo espera o consentimento. O requisito ausente explica a espera observada; não se atribui falha ao gateway local. Não aumentamos timeout nem desativamos validação TLS.

Referências oficiais consultadas em 06/10/2026:
- https://tailscale.com/docs/features/tailscale-serve
- https://tailscale.com/docs/how-to/set-up-https-certificates
- https://raw.githubusercontent.com/tailscale/tailscale/main/client/local/local.go (`Client.QueryFeature`)

### Ação administrativa necessária

No painel Tailscale: DNS → HTTPS Certificates → Enable HTTPS. O fluxo específico de Serve também pode ser usado, mantendo **Tailscale Funnel desmarcado**. A emissão publica o nome DNS do certificado no registro público de transparência; isso não torna o serviço acessível fora da tailnet. Não alterar ACLs, não usar Funnel e não substituir HTTPS por HTTP público.

A tentativa de abrir a página no Chrome pelo controle local não produziu uma tela de consentimento verificável. Não foi clicado botão de habilitação nem realizado login administrativo. O comando `open` foi enviado, mas não se afirma que a página permaneceu aberta.

## Autonomia — ativação inicial e verificação

Raiz local: `/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/`.

Os executores usados permaneceram nos hashes anteriormente revisados:

| Arquivo | SHA256 |
| --- | --- |
| `runtime/display-gateway-3783da330716bf92346e5b017a6a491fdb8f1377/display-gateway.py` | `ea58b75358dfb607fb70458a1de87601c94b7d3ee9f19ad51b50bd69c7251aae` |
| `display-gateway-remote.py` no mesmo diretório | `22cc71edbeaa5c689177c541f91bd2163fa8799f3a3f8c1fe473140f346a4de1` |

A pré-checagem confirmou `current` em `3783da330716bf92346e5b017a6a491fdb8f1377`, `instagram_vps_env_pair_ok`, o par Autonomia inicialmente inativo e os quatro publishers/managers VPS inativos.

| Etapa | PID Mac | UTC | Resultado |
| --- | --- | --- | --- |
| start Autonomia | 25800 | 09:28:28.561357 | PASS / exit 0 |
| verify Autonomia | 26228 | 09:28:52.968257 | PASS / exit 0 |

Display PID 1547143; gateway PID 1547196; ambos iguais nas duas observações. Gateway somente em `127.0.0.1:18442`; display sem listener TCP; VNC socket Unix modo 0660; runtime 0710; Xauthority 0600; Node privado montado somente leitura. Acesso anônimo recusado com 401 sem cookie. Nenhum marcador de navegador foi criado. O par Hub2You e os 115 containers conservaram os estados comparados pelo executor.

Os quatro serviços display/gateway estão ativos na última verificação, mas desabilitados para boot nesta fase. Publishers/managers permanecem inativos. Não confundir esta preparação com a operação do navegador Meta.

## Testes negativos locais — 42/42

Executor já revisado `negative-probe.py`, SHA256 `f1c483ef385a608b211bd3be7be3870e2b53b47b486900e01e0ed55b9cbfa0bf`.

PID Mac 26658; conclusão 09:29:22.262653 UTC. `planned=42`, `attempted=42`, `passed=42`, `failures=0`, `complete_success=true`, `transport=loopback`.

Cobertura: recursos sem sessão, query indevida, origem errada/ausente/null, Authorization alternativa, cross-site, formulários vazios/duplicados, JWT inválido e WebSocket sem cookie/origem válida. As respostas esperadas 401/403/415 foram observadas, sem emissão de cookies ou upgrade WebSocket.

Recibo remoto: `/opt/instagram-meta-staging/https-approved-1023-20261005/negative-loopback-20261006T0929.json`.

Esse recibo **não comprova TLS, proxy Serve, autenticação positiva, replay após restart, UI ou Meta**. Os testes HTTPS/autenticados continuam pendentes, sem fallback que contabilize loopback como HTTPS.

## AWS A6 Autonomia — observação e limites

Pré-checagens PIDs 26963 e 27975: concluídas às 09:29:53 e 09:31:07 UTC, com fontes revisadas exatas, role/trust/mappings esperados, CURRENT estável no contexto e produtores inativos. Nenhuma mutação IAM.

C0 Autonomia, PID 27504, exit 0: `aws/autonomia/proof-protocol-control-77a532bc7b8946e9bca5810d9925700e.json`. Progresso parcial próprio: handshake_request 335 bytes com estrutura e digest válidos. Sessão encerrada; cleanup conclusivo às 09:30:26.873841 UTC.

A6 Autonomia, PID 28457, exit 0: `aws/autonomia/proof-auth-binding-5816340ba9944c55bc72c990f692c427.json`. Uma tentativa com token próprio novo para o canal de uma sessão administrativa sintética da mesma conta. HTTP 101 seguido de close diagnóstico com 179 bytes, código 1003, razão UTF-8 de 177 bytes, leitura completa. Projeção ordenada não truncada:

`TOKEN OTHER CHANNEL ID IS NOT VALID FOR OTHER CHANNEL OTHER TOKEN OTHER`

Os dois IDs conhecidos estavam presentes, com contexto validado. O controle original próprio fornecido ao plugin abriu listener e apresentou banner SSH. Plugin parado; as duas sessões foram explicitamente encerradas; cleanup conclusivo às 09:31:57.426260 UTC e nenhum remanescente.

A interpretação limitada é a recusa comportamental do par token/canal incompatível nessa tentativa. Não se atribui causa interna à IAM, não se comprova login SSH nem se excluem todos os comportamentos internos de substituição/retry do plugin. Os recibos continuam `diagnostic_only=true`, `foreign_access_classified=false` e `cutover_eligible=false`. Nenhum compositor foi alterado para transformar diagnóstico em aprovação. A evidência Hub anterior continua histórica, não recebe timestamp novo.

## Subagentes solicitados

Três processos Claude foram iniciados em modo sem ferramentas e terminaram exit 1. O recibo lido de `https-cause` confirmou sessão OAuth expirada e falha de refresh, antes de inferência. Os outros dois não tiveram os motivos individuais lidos.

Três revisores Codex foram então iniciados, modelo explícito `gpt-6.1-sol`, esforço high, sandbox read-only, MCPs desabilitados por invocação e sessão efêmera. Objetivos: diagnóstico HTTPS, testes do gateway e interpretação de evidência AWS. PIDs 16685/16686/16687; o coordenador 16673 terminou exit 0, registrando exit 0 para os três filhos.

Resultados locais em `review/codex-20261006T0921/{https-cause,gateway-tests,aws-evidence}.json`. A chamada que leria o conteúdo consolidado foi bloqueada pela plataforma antes de execução. Não foi repetida por rota alternativa. **Não alegar parecer aprovado, ausência de achados ou zero chamadas de ferramentas somente pelos exit codes**; essas conclusões dependem da leitura dos arquivos.

## Continuidade e Project

Coordenação registrada na PR #1039; documentação na PR draft #1042. Nenhum novo merge/deploy solicitado. A fila não foi inventariada nesta etapa independente do deploy Rails; deve ser consultada antes de qualquer publicação.

O conector do Project foi consultado novamente e retornou HTTP 404 no endpoint MCP/ngrok. **Project update pendente** para #995: Projeto=Hub2You; Status=Bloqueada; Tipo=Infra; Prioridade=P1; Risco=Alto; Ambiente=Produção; Próxima ação=Habilitar somente HTTPS/Serve na tailnet; ler pareceres pendentes; validar HTTPS e autenticação de ambos gateways; depois overlay, corte+B0, produtores e aceite Meta. 42/42 negativos locais passaram; assistido OFF.

Para #1042: Projeto=Hub2You; Status=PR aberta; Tipo=Docs; Prioridade=P1; Risco=Médio; Ambiente=Produção; Próxima ação=Revisar os checkpoints e limites das evidências; manter draft fora da fila até revisão consolidada.

A próxima mutação Serve exige consentimento efetivo e uma nova leitura de requisitos/configuração. Depois usar os executores com seus backups e gates, validar HTTPS real e autenticação, conferir as versões Rails/overlay e a fila, executar corte controlado, coletar B0 após corte/antes dos produtores e validar login Meta, publicação e renovações naturais. Manter `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false` até o aceite. Não apagar Redis, cookies, outcomes, epochs, journals ou backups.

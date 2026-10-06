# #995 — retomada operacional em 6 de outubro de 2026

Este checkpoint sucede o registro de 5 de outubro preservado em `995-aws-recovery-20261005/README.md`. É uma síntese das saídas efetivamente observadas nesta rodada, não uma cópia dos recibos brutos. As autorizações anteriores de Rodrigo permanecem válidas. A migração e o aceite Meta ainda não estão concluídos.

## Estado ao interromper as operações

- Runtime corrigido `3783da330716bf92346e5b017a6a491fdb8f1377` instalado e verificado na VPS n8n.
- Display e gateway Hub2You ativos e verificados; continuam desabilitados para partida no boot nesta fase. Display/gateway Autonomia não foram iniciados nesta rodada.
- Publishers/managers VPS das duas stacks permaneceram inativos nas verificações realizadas. Não houve corte ou parada dos gestores Mac.
- A6 Hub concluiu a observação comportamental descrita abaixo, com controle próprio e limpeza confirmados. Não houve A6 Autonomia nem composição de prova de cutover.
- A tentativa de Tailscale Serve não concluiu. Seu executor confirmou rollback com a configuração original restaurada e mount já ausente. Não houve prova HTTPS bem-sucedida, autenticação do console ou login Meta.
- Nenhuma escrita no overlay Rails, novo merge/deploy Rails ou habilitação de `INSTAGRAM_TESTER_AUTOMATION_ENABLED` foi feita nesta rodada. O gate deve continuar OFF até o aceite.

## Reconexão e integridade do pacote

O conector M4 voltou a executar comandos e ler os arquivos da worktree. Identidade observada: MacBook-Air-de-Rodrigo.local, usuário rodrigosilva. A raiz operacional local é:

`/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/`

Neste documento, os caminhos locais seguintes são relativos a essa raiz.

O `runtime/upgrade/runtime-upgrade.py` original foi lido e seu SHA256 conferido: `8d619986a8f9f297da87b5c5ee3a9b3b945bb1306656901bacfa3a5ddf08a6b8`. O remoto também foi lido integralmente e preserva SHA256 `29dd56d05f16e1585d3f2066158c4543186baffc31fe74bbe44c93f4d5b84f9a`.

O comando `package` do SHA mergeado terminou com sucesso no PID Mac 91847. O validador separado, PID 92394, conferiu cada arquivo do tar contra o manifesto: caminho, tipo regular, modo, tamanho, SHA256 e identidade do objeto Git. Não foi alegado novo parecer de subagente nesta rodada.

| Propriedade | Resultado |
| --- | --- |
| Arquivos | 41 |
| Tar | 49.803 bytes |
| SHA256 do tar | `c863fd1283ad7fd9a62b1a9e2c255963fb1be6919e76dc4e77225e8bea3b1d39` |
| Digest JSON canônico de `files` | `c5df697fbfdb884f6e728118efb75b32ac1cb3ea164d6c8a8941ec2560dafc8d` |

O digest coincide com o inventário anteriormente revisado. Tar e manifesto reais estão em `runtime/upgrade/`, com os nomes `runtime-<SHA>.tar.gz` e `manifest-<SHA>.json` e modo 0600.

## Instalação real, em fases separadas

A leitura inicial da VPS confirmou hostname srv707880, link current na release 499809, oito units inativas/desabilitadas e nenhum processo listado sob os seis UIDs de serviço. Essa leitura não é uma investigação global de todos os processos do host.

| Fase | PID Mac | Conclusão observada (UTC) | Resultado |
| --- | --- | --- | --- |
| stage | 93191 | 08:42:08.831695 | exit 0; 41 fontes verificadas |
| preflight | 93358 | 08:42:21.268652 | exit 0; runtime_preflight_ok |
| install | 93518 | 08:42:44.725194 | exit 0 |
| verify-inactive | 93731 | 08:43:01.357599 | exit 0; oito units inativas/desabilitadas |

As quatro fases confirmaram preservação dos 115 containers observados, incluindo seus estados/start/restart counts; seis identidades de serviço, metadados privados e Node do host v18.19.1 também foram preservados. A release anterior 499809 permanece disponível. Nenhum serviço foi iniciado ou habilitado por essas quatro fases e nenhuma alteração Redis foi executada.

Recibos/intents locais: `runtime/upgrade/<fase>-<SHA>.json` e `.intent.json`. Recibos/intents remotos: `/opt/instagram-meta-staging/upgrade-<SHA>.<fase>.json` e `.intent.json`. Não repetir as fases sobre esses arquivos.

## AWS A6 Hub — observação concluída, sem liberação automática de corte

A promoção A6 local ocorreu uma vez, PID 94223, de 08:43:49.016617 a 08:43:49.018713 UTC. O recibo `aws/auth-a6-promotion-20261005.json` conserva o nome do executor histórico, mas seus timestamps são de 6 de outubro. Estado: `promoted_readback_exact`.

Somente o helper de projeção e a preflight mudaram; os backups A5 foram preservados. Não houve alteração IAM. Pré-checagens Hub, PIDs 94548 e 95469, concluíram às 08:44:40 e 08:46:01 UTC, respectivamente, com identidade/trust/mappings exatos e produtores inativos. O alvo CURRENT observado foi a instância vigente naquela coleta, não o alvo histórico de 5 de outubro.

C0 Hub: PID 95038, exit 0, recibo `aws/hub2you/proof-protocol-control-ea4136ecafe043ea899e4d3f874ce733.json`. Houve progresso parcial estruturalmente válido do protocolo próprio, com handshake_request de 335 bytes e digest válido. A sessão foi explicitamente encerrada; cleanup conclusivo às 08:45:24.669430 UTC, sem remanescentes.

A6 Hub: PID 96000, exit 0, recibo `aws/hub2you/proof-auth-binding-bcb247493ffe4ef3a2865027cef4d2bc.json`. Um token próprio recém-criado e ainda não usado foi enviado uma vez ao canal de outra sessão administrativa sintética da mesma conta. O diagnóstico leu integralmente o close de 175 bytes, com código 1003 e razão UTF-8 de 173 bytes. A projeção ordenada, não truncada, preservou:

`TOKEN OTHER CHANNEL ID IS NOT VALID FOR OTHER CHANNEL OTHER TOKEN OTHER`

Os dois IDs conhecidos estavam presentes e o contexto de sessão foi validado. A interpretação desta observação é a recusa comportamental do token/canal incompatível naquela tentativa. Não se atribui a decisão a uma camada IAM interna. Os classificadores automáticos continuaram `unrecognized/unknown`; os recibos mantêm `diagnostic_only=true`, `foreign_access_classified=false` e `cutover_eligible=false`.

Depois da tentativa cruzada, o plugin oficial recebeu o par original próprio, abriu seu listener e apresentou banner SSH; o plugin foi encerrado. Esse controle não comprova login SSH, publicação, exclusão observada de toda substituição interna de token ou ausência de retries internos. Ambas as sessões foram explicitamente encerradas, com limpeza conclusiva às 08:47:04.500396 UTC e sem remanescentes. Não houve tentativa A6 Autonomia, repetição A6 Hub ou alteração do compositor de cutover.

## Display/gateway Hub — partida real corrigida

Os dois executores revisados do commit documental 584ab foram copiados para novo diretório local `runtime/display-gateway-3783da330716bf92346e5b017a6a491fdb8f1377/`, conferindo os hashes antes e após gravar. Os executores históricos permanecem intactos.

- Wrapper: `ea58b75358dfb607fb70458a1de87601c94b7d3ee9f19ad51b50bd69c7251aae`.
- Remoto: `22cc71edbeaa5c689177c541f91bd2163fa8799f3a3f8c1fe473140f346a4de1`.

A verificação completa `verify-pair.py` da release instalada retornou `instagram_vps_env_pair_ok`, PID Mac 97037.

Start Hub: PID 97171, PASS às 08:49:04.172060 UTC. Verify Hub: PID 97330, PASS às 08:49:18.380777 UTC. Display PID 1475711 e gateway PID 1475752 permaneceram iguais nas duas observações.

As verificações comprovaram gateway somente em loopback 18441, VNC em socket Unix sem listener TCP, permissões esperadas dos sockets/diretórios/Xauthority, Node privado montado readonly e recusa anônima 401 sem cookie. Não havia marker de pedido de navegador. Publishers/managers e a outra stack foram preservados; os 115 containers também. Start/verify têm seus próprios recibos e intents nesse diretório novo.

Essa partida comprova a correção da falha de bootstrap observada anteriormente. Não comprova console HTTPS, navegador Meta, publicação ou renovação.

## HTTPS — tentativa falhou; rollback confirmado pelo executor

Os três scripts já staged em `/opt/instagram-meta-staging/https-approved-1023-20261005/` tiveram hashes, owner root, modo 0600 e arquivo regular conferidos. A leitura prévia mostrou configuração Serve vazia.

O executor original `serve-mount.py`, SHA256 `52b5e5b62ed15bb07059dbc599d7ec8a34c03585f7fc4fc5b08c097f778663b5`, foi chamado uma vez para Hub2You. PID Mac 98180, duração observada 34,78 segundos, exit 1. Após o backup, retornou:

- `failure_code=bounded_command_or_io_failure`;
- rollback `state=already_absent`, `config_restored=true`.

Backup remoto: `/tmp/instagram-serve_20261006T085100Z_a8cb9b602f434245a1919424e872c56c.json`.

Resultado remoto: `/tmp/instagram-serve_20261006T085100Z_a8cb9b602f434245a1919424e872c56c.result.json`.

A duração é compatível com o limite configurado, mas a classe exata da falha e sua causa não foram confirmadas. A consulta posterior que leria uma projeção do resultado e status Tailscale foi bloqueada pela plataforma antes de executar: não foi possível determinar o status de segurança da solicitação. Não foi enviada a mesma consulta por outra rota, repetido o apply ou alterados timeouts/permissões para contornar o bloqueio. A afirmação de configuração restaurada vem do retorno terminal do executor; não de uma leitura posterior independente.

Nenhum probe HTTPS negativo ou autenticado foi executado. A configuração HTTPS/consentimento Tailscale é um ponto a investigar, não uma causa comprovada neste checkpoint.

## Coordenação e retomada

O avanço foi comunicado na PR #1039. A consulta composta inicial de fila/deploys foi bloqueada antes de executar; portanto esta rodada não produziu inventário atualizado da fila. Não houve nova publicação Rails, e a instalação do runtime inativo foi separada desse fluxo.

Retomar somente por caminho normal permitido, sem enfraquecer os controles. Primeiro reconciliar o resultado Serve e seu estado atual; diagnosticar a falha antes de repetir qualquer mutação. Preservar os backups, os recibos de instalação e os diagnósticos AWS. O par display/gateway Hub está ativo nas últimas verificações; não reiniciar indiscriminadamente nem declarar todas as units inativas.

Após resolver HTTPS, continuar os gates de autenticação/isolamento por stack, overlay com versões/fila atuais, corte Mac, B0 válido, partida dos produtores, login humano Meta e publicação/renovações naturais. Nenhuma dessas etapas é substituída por provas sintéticas ou pelo deploy da aplicação.

## Project update pendente

O conector do Project Autonom.ia Dev retornou HTTP 404 no endpoint ngrok/MCP. A tentativa não confirmou atualização do board. Preencher no item da #995:

| Campo | Valor |
| --- | --- |
| Projeto | Hub2You |
| Status | Bloqueada |
| Tipo | Infra |
| Prioridade | P1 |
| Risco | Alto |
| Ambiente | Produção |
| Próxima ação | Diagnosticar Serve/HTTPS após reconciliar a tentativa revertida; inspeção bloqueada pela plataforma. Runtime 3783 instalado, Hub display/gateway ativo. Concluir isolamento das duas stacks, overlay, corte+B0 e aceite Meta. Assistido OFF. |

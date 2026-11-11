# Issue #995 — verificação posterior ao deploy, 07/10/2026
## Estado atual consolidado — 07/10/2026, 17:26 UTC

A PR #1112 está mergeada; AWS executa `383ed42f82659a2891ca59e506e9ea86e8002e1d` nas duas stacks e VPS executa `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26`. Sessões legítimas, duas renovações naturais por stack, recursos permanentes e reinício controlado das oito units foram comprovados nos checkpoints abaixo. Ativação restrita e liberação global de criação foram aprovadas e aplicadas. Envio Meta permanece bloqueado.

**Aceite funcional pendente:** a busca no painel falha; o backend recebe HTTP 400/HTML da Meta tanto no typeahead quanto na leitura GraphQL de papéis. O navegador legítimo recebe HTTP 200 com papéis completos. O campo `server_timestamps` ausente no backend foi isolado num par com mesma sessão e não resolveu o HTTP 400. Um GET público pelo transporte do backend respondeu HTTP 200; URL, Host e formato da request foram verificados. Isso exclui falha grosseira de conectividade nessa leitura, sem provar a causa da rejeição autenticada. Nenhum patch funcional foi aplicado a partir dessas hipóteses.

Os relatos abaixo são cronológicos; pendências antigas devem ser interpretadas na data de cada checkpoint. A #995 continua aberta, sem conexão/OAuth/teste ou reconexão da caixa homologados.

Verificação somente de leitura realizada entre 13:48:33 e 13:48:59 UTC
(10:48:33 a 10:48:59 BRT). Nenhum merge, deploy, restart ou instalação executado
nesta verificação.

- PR #1112 MERGED em 12:50:47 UTC, mergeCommit
  `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26`.
- Autonomia: workflow https://github.com/autonom-ia2/chat/actions/runs/37623967743
  concluído com sucesso em 13:06:04 UTC.
- Hub2You: workflow https://github.com/autonom-ia2/chat/actions/runs/37623967612
  concluído com sucesso em 13:06:30 UTC.
- Consultas AWS autenticadas verificaram contas corretas, instâncias CURRENT
  rodando, tags de produção, listener HTTPS apontando para CURRENT e targets
  saudáveis nas duas stacks.
- Uma leitura SSM limitada por stack verificou `/app/.git_sha` dos containers
  chatwoot-web e chatwoot-worker: todos correspondem ao mergeCommit acima e
  estão running. O SHA-256 de session_publisher.rb no web corresponde ao arquivo
  do commit integrado. CURRENT permaneceu igual durante as leituras.
- Rollback anterior de cada AWS registrado, em target distinto, com instância
  parada; não estava saudável naquele instante e nenhum rollback foi executado.
- SSH somente de leitura na VPS confirmou current ainda em
  `/opt/instagram-meta/releases/9a48a2de08e93f2f7dc6916d7a4c79729f88dec4`.
  Os hashes de session-manager.mjs e session-observer.mjs diferem do mergeCommit.
  A correção da captura ainda não está instalada na VPS.
- Os sete serviços anteriores continuam ativos, com os mesmos PIDs, NRestarts=0
  e início em torno de 09:17 UTC. Manager Autonomia continua inativo. Todas as
  oito units permanecem disabled para boot. Publishers ainda têm quota 200%
  transitória; display/gateway 50% e managers 150%.

Deploy AWS confirmado. Instalação VPS e aceite real de captura, duas renovações
naturais, persistência e reconexão pelo painel continuam pendentes. Nenhum teste
real novo da Meta ou do painel foi executado nesta verificação.

## Continuação autorizada e upgrade VPS

Rodrigo autorizou continuar nesta conversa após a verificação dos deploys.
Pacote do merge 2cc6b4f preparado com archive SHA-256
`3779919b95c01e17ea304bc3e6cc392b812d764f79a3b0dc2a5cc6baefe06a9d`;
41 arquivos versionados verificados. package.json/package-lock e quatro templates
iguais à release anterior; somente dependências Linux já instaladas e locked
foram copiadas para a fonte nova. Releases/perfis/chaves antigos preservados.

O stage inicial recusou permissões 0664 de git archive; foram corrigidas somente
na fonte nova root-owned. Nenhum serviço interrompido nessa tentativa.
Revisão independente Nexo liberou stop/install após quatro ajustes do executor.

Drenagem em 15:07 UTC: oito units sem processo/perfil/marker concorrente. O
recibo stop retornou erro porque exigia inactive estrito e manager Hub terminou
failed/MainPID=0; installer original permite inactive/failed. A leitura física
de drenagem foi preservada; não houve reset-failed nem exclusão de lock.
Installer original, com Node privado bindado, terminou sucesso em15:08:39UTC.
current aponta para 2cc6b4f e hashes manager/observer correspondem ao merge.
Seis units de apoio retomadas; env-pair passou; gateways devolveram401 sem cookie
e ambos sockets VNC Unix estavam presentes.

Bootstrap real via ig-autonomia e socket instalado, com quota50%, falhou e as
quotas200% prévias foram restauradas nas duas stacks. A saída interna dessa
primeira falha não foi preservada pelo wrapper; não atribuir duração específica.
Controle no cliente real em200% passou em19003ms. Medição de fases em200% passou
em17934.185ms; SSH/publisher/Rails6195.482ms. Medição isolada transitória em50%
falhou pelo deadline em25027.975ms, com preparação/chave concluída somente após
21s. Não há prova válida de contadores cgroup de throttling: a leitura posterior
com ControlGroup vazio resolveu o cgroup raiz, e esses contadores foram descartados.
Não alterar TTL, deadlines, retries, proxy, IAM ou serviços n8n.

Proposta revisada: tornar permanentes os200% já usados somente nos dois publishers,
em drop-ins porinstância, preservando Node e demais limites. Autorização específica
solicitada e ainda pendente neste checkpoint. Os overrides runtime200% continuam.

Gestores iniciados em15:12:06UTC. Autonomia publicou sessão legítima, capturada
em15:12:29.627UTC e gravada em15:12:55.715380UTC; leitura de15:13:33 confirmou
snapshot presente, pointer active, availabletrue e heartbeat healthy em15:13:14.632UTC.
Automação de produto continua globallydisabled; não confundir available com enabled.
Hub2You sem sessão e operator_required/control_availabletrue. O fluxo oficial de
reconexão foi acionado pelo SuperAdmin no navegador autorizado; pedido queued e
viewer privado aberto, aguardando disponibilidade do Chrome. Nenhum login humano
novo foi solicitado neste checkpoint, nem reenviado payload de captura.

Duas renovações naturais, persistência/restart, habilitação de boot e conexão/teste
pelo painel permanecem pendentes. O código VPS usa pausa de780000ms (13min) mais
ciclo bounded120s; os intervalos naturais não foram encurtados ou alterados.

Project: PR status Mergeada confirmado por leitura. Mutação do campo Próxima ação
falhou repetidamente com erro interno GraphQL; registrar pendência e não alegar
atualização. Demais seis campos mantêm os valores anteriores confirmados.


## Autenticação humana Hub e deploy concorrente observado

Rodrigo informou login concluído. A inspeção visual confirmou a página de funções
Meta, com Chrome remoto ainda aberto; o executor fechou a última aba desse Chrome
pela interface noVNC autorizada. O viewer confirmou acesso encerrado. Não houve
kill forçado, reset de perfil ou envio de senha/código pelo chat.

Em15:19UTC a leitura revelou backend AWS avançado para383ed42, descendente de2cc6b4f,
por deploy concorrente da PR#1119. Comparação GitHub: ahead8,93arquivos modificados,
nenhum arquivo Instagram/Gemfile/bootRails/Dockerfile alterado. A sessão Autonomia
permaneceu válida e o pedido Hub running com mesmoid. Não atribuir esse deploy
a esta execução; não reverter trabalho de outra frente. Revalidar saúde/CURRENT
antes de qualquer liberação adicional.

Leitura dos gates em15:20UTC: global enabledfalse e feature de assistido false
nas duas contas autorizadas; channel_instagramtrue. Há preparação/ativação de
produto ainda necessária após o aceite do runtime, além da publicação da sessão.


## Reconexão, renovação inicial e preparo de ativação — 15:34 UTC

A reconexão Hub terminou como `succeeded`, com o mesmo request ID emitido pela
interface oficial. Captura legítima em 15:19:40.739 UTC; publicação em
15:20:09.809888 UTC. O wrapper iniciou o processo contínuo, que capturou em
15:21:05.913 UTC e publicou em 15:21:32.539277 UTC. Essa captura de partida não
conta como renovação natural. Screenshot privada comprova `Completed` e a
automação ainda globalmente desativada.

Autonomia: baseline capturada em 15:12:29.627 UTC; primeira renovação natural
capturada em 15:26:29.263 UTC e publicada em 15:26:54.172841 UTC, com nova versão
canônica e heartbeat saudável. Ambos os gestores continuam nos PIDs iniciais
784192/784226, NRestarts=0. Nenhum replay, redução do intervalo ou restart foi
usado para obter essa renovação.

O bit assistido da conta 18 mudou por uma gravação externa em 15:26:09.770116 UTC,
com marcador de rollout true. Logs saneados no CURRENT registram um PATCH da
conta 18 e uma ação AccountsController#update no intervalo 15:25–15:27. O
executor fez apenas GET/read e não enviou esse PATCH; não atribuir ator sem
prova. Preservar o bit true. Global continua false e a conta 1 continua false.

Preparação restrita: candidatos em memória alteram somente enabled=true e
allowlist=1 (Autonomia)/18 (Hub). A revisão corrigiu o preparador para não
persistir valores descriptografados; os dois scratchfiles próprios foram
removidos e recriados apenas com Name/ARN/Version/Type e metadata. Apply/rollback
buscam versões SSM em memória; não registram payloads. Nenhum put, feature write,
novo deploy ou quota permanente foi aplicado. Aprovação específica solicitada
para o bloco final, conforme AGENTS e o gate de CPU do plano revisado.

O erro interno anterior de Project não se repetiu na tentativa limitada das
15:34 UTC. Próxima ação da issue e da PR foi atualizada e os sete campos foram
relidos: Projeto Hub2You; issue Em desenvolvimento/Infra; PR Mergeada/Bug; ambas
P1, Alto, Produção e próxima ação coerente com sessões reais/aceite pendente.
O backend atual é 383ed42f, com os dois workflows externos concluídos com sucesso.


## Duas renovações Autonomia — 15:41 UTC

Segunda renovação natural da Autonomia: captura em 15:40:32.362 UTC e publicação
em 15:41:00.786355 UTC; versão `a224d8f0-c2ef-495f-98c1-27bc4b6e0797`.
A primeira tinha versão `7ff47410-c868-4245-b672-9f940b17a3f3`; baseline
`ee5ba42f-439d-4791-a2e1-72a477f15c45`. As duas mudanças decorreram dos ciclos
normais, sem operador/restart/replay. Hub tem primeira renovação em
15:35:02.638 UTC, publicada em 15:35:29.640677 UTC; segunda ainda pendente.

Saúde CURRENT/listener/target e web+worker SHA383 foram revalidados em ambas
as AWS às 15:36 UTC; previous distinto, parado e registrado para rollback.
Os seis deltas não aprovados na worktree anterior continuam com HEAD e hashes
iguais ao manifesto. A UI de conta1 está autenticada no produto e pronta para
conexão; SuperAdmin Aut exige login, portanto a alteração restrita do bit será
pelo modelo existente sob lock, após aprovação, com reversão preparada.


## Duas renovações por stack confirmadas — 15:50 UTC

| Stack | Baseline contínua | Renovação natural 1 | Renovação natural 2 |
| --- | --- | --- | --- |
| Autonomia | 15:12:29.627 | 15:26:29.263 | 15:40:32.362 |
| Hub2You | 15:21:05.913 | 15:35:02.638 | 15:48:59.003 |

Todos os horários da tabela são capturas UTC de 07/10/2026, lidas do backend
real. A segunda Hub foi publicada em 15:49:24.338069 UTC; heartbeat saudável em
15:49:39.120 UTC. Aut permanece saudável, com heartbeat em 15:41:19.209 UTC.
Cada mudança gerou versão canônica distinta e pointer ativo, snapshot presente
e configuração disponível. A captura humana de recuperação Hub e a captura
imediata ao iniciar processo contínuo foram excluídas da contagem natural.

O verificador privado registra source real, ausência de publicação pelo leitor,
conta alvo, UTC de leitura/captura e estado saudável da última observação. O
reinício exige prova de duas naturais e leitura atual saudável. Executor de
conta1 passou parse Ruby, bloqueia repetição que sobrescreveria recibo, preserva
outros bits/atributos e condiciona rollback ao estado aplicado sob lock.

Nenhuma quota permanente, enable para boot, restart de aceite, put SecureString,
ativação conta1 ou novo deploy foi feito neste checkpoint. A aprovação conjunta
solicitada ainda não foi recebida. Runtime VPS e publicação AWS já executados
são fatos distintos desses itens pendentes. Conexão/teste dos Instagrams pelo
painel permanece pendente: não declarar o assistido operacional.

Checkpoint público: https://github.com/autonom-ia2/chat/issues/995#issuecomment-6041529497.
Próxima ação dos dois itens foi atualizada para duas naturais por stack e relida;
os sete campos estão presentes. Aprovação final permanece pendente.

## Bloco final autorizado e persistência de CPU — 16:04 UTC

Rodrigo respondeu `pode continuar` ao pedido concreto do bloco final: manter
200% nos publishers, habilitar boot e validar reinício somente das units
Instagram, ativar apenas as contas autorizadas 1/18, carregar os gates pelos
dois deploys blue-green normais e testar o painel. Essa aprovação substitui a
pendência do checkpoint anterior; não inclui reboot do host ou outros serviços.

Às 15:53:16 UTC foram criados os dois drop-ins permanentes por instância,
root:root 0644, CPUQuota=200%. Somente os dois overrides transitórios exatos
previamente identificados foram removidos. Daemon-reload preservou os PIDs
dos publishers e os demais limites/drop-ins; quota efetiva 2s em ambas.

O primeiro aceite de reinício Autonomia falhou em um guard depois do stop e
restaurou os quatro serviços e o estado disabled anterior. A razão original
não foi registrada; não atribuir causa sem prova. Nova captura legítima às
15:54:06.881 UTC, publicada às 15:54:29.017301, confirmou perfil preservado.

O segundo teste, com SIGTERM dirigido ao wrapper principal, falhou em
profile_cleanup_wait / manager_cleanup_deadline. O wrapper saiu com 143;
systemd retomou o manager após RestartSec=30, NRestarts=1. A restauração foi
verificada; captura legítima 15:59:25.162 UTC, publicação 15:59:50.293532 e
heartbeat saudável 16:00:11.160. Isso não conta como renovação natural.

O guard usado até então tratava qualquer SingletonLock como lock vivo. Leitura
com o navegador ativo mostrou link simbólico com exists=false e PID Chrome
vivo: existência do destino do link não comprova liveness. Um terceiro aceite
está preparado, ainda não executado neste checkpoint: stop normal, ausência
do lock próprio e de processos Chrome, e eventual SingletonLock aceito somente
se hostname local e PID comprovadamente morto. Nenhum lock ou perfil é apagado.
As duas renovações naturais já comprovadas ficam em evidência congelada antes
dos reinícios; saúde atual é lida separadamente.

Saúde AWS/CURRENT/listeners/targets/web/worker 383ed42f foi revalidada 16:01 UTC.
Main ainda é esse SHA e os dois workflows anteriores estão concluídos. Nenhum
gate SSM, bit da conta 1 ou novo deploy do bloco final foi aplicado até aqui.


## Aceite de reinício e ativação restrita — 16:14 UTC

Autonomia V3 passou às 16:04:37 UTC: quatro units enabled/active, NRestarts=0,
limites e drop-ins iguais, perfil preservado. Exclusividade pós-stop comprovou
lock próprio ausente, nenhum Chrome e SingletonLock com PID local morto.
Captura pós-reinício 16:04:49.112, publicação 16:05:17.291133 e heartbeat
16:05:33.132 UTC. Reinício do host não foi executado.

Hub V3 falhou no lock próprio após stop normal; o restore iniciou, mas o manager
falhou ao adquirir o arquivo restante. Leitura mostrou manager sem PID, cgroup
vazio, apenas Xvnc no UID, arquivo vazio/inode/mtime antigos. O reparo parou o
manager, confirmou stat inalterado, fuser sem holder, tipo regular/UID/nlink/
inode/mtime exatos e removeu somente esse lock comprovadamente órfão. Perfil e
SingletonLock foram preservados. StartLimitBurst foi atingido pelas tentativas
automáticas; journal confirmou a causa antes de reset-failed/start pontual.
Recuperação legítima: captura 16:07:37.759, publicação 16:08:01.778118, heartbeat
16:08:18.816 UTC. A causa de encerramento incompleto segue hipótese, sem alteração
de KillMode, sinais no runtime, timeouts ou retries.

Hub V4 passou às 16:12:01 UTC: SIGTERM apenas no wrapper MainPID, espera de
exclusividade limitada, seguida de stop para cancelar RestartSec=30. Predicate
aceita apenas ausência do lock próprio, nenhum Chrome e SingletonLock ausente
ou PID local morto; nenhum lock foi removido nesse aceite. Quatro units
enabled/active, NRestarts=0 e limites/drop-ins preservados. Captura pós-reinício
16:12:14.968, publicação 16:12:38.803698 UTC. Usar essa drenagem antes de parar
serviços em futuras operações; não declarar reinício abrupto do host homologado.

O CLI AWS local rejeitou cli-input-json por stdin com ParamValidation antes da
requisição de escrita. Diagnósticos usam somente conteúdo dummy; nenhum secret
foi gravado em argv/arquivo. A escrita passou ao SDK oficial boto3, isolado via
uv no Mac administrativo, com STS, timeout finito e uma tentativa. Guards de
versão/valor/metadata e readback foram preservados. Rollback também exige metadata
estável igual ao plano e versão aplicada; não sobrescreve outro escritor.

SSM Autonomia versão 8 aplicada/readback 16:11:30 UTC; Hub versão 9 aplicada/
readback 16:12:41 UTC. Alteradas somente duas linhas: enabled=true e allowlist
1/18, respectivamente. Contas fora desse alcance continuam inelegíveis.
Conta 1 ativada pelo modelo sob lock em 16:12:08.908368 UTC, marcador true;
outros recursos e atributos preservados. Conta 18 já true foi preservada.

Até o deploy de ativação, runtimes ainda reportam global=false, distinção
esperada entre SSM salvo e ENV carregado. Saúde CURRENT/listener/target e
web/worker SHA383, com rollback distinto registrado, revalidada às 16:14:22 UTC.
Os dispatches autorizados carregam as configurações na mesma main383; não
repetem os deploys automáticos originais nem incluem novo código/merge.


## Deploys concluídos; bloqueio funcional identificado — 16:29 UTC

Workflows de ativação Autonomia 37650526041 e Hub2You 37650584861:
Deploy Green concluído com sucesso; job de rollback skipped. Nenhum redispatch.
Prova runtime às 16:29:27 UTC: CURRENT running, listener apontando para CURRENT,
target saudável; web/worker nos dois ambientes SHA383, automation=true e
allowlist exata 1/18. Instâncias anteriores stopped; alvo de rollback distinto
continua registrado. As duas renovações naturais permanecem na evidência
congelada anterior aos reinícios; não usar novas capturas de startup para inflar
esse critério. CPU persistente e oito units habilitadas já aceitas.

Busca real única de cada perfil autorizado pelo painel: configuration200;
search403, 71ms Autonomia e 12ms Hub2You, mensagem genérica de indisponibilidade.
Leitura somente de configuração às 16:28:47/16:29:25 UTC comprovou
Configuration#ensure_available! => forbidden devido a
DISABLE_META_INBOX_CREATION=true tanto no banco quanto em GlobalConfig.
Ambos chatwoot_cloud=false. A operação é bloqueada antes de Client#search;
esses pedidos não comprovam falha de transporte/proxy/sessão no typeahead Meta.
Não repetir login/bootstrap nem atribuir o 403 ao upstream.

DISABLE_META_INBOX_CREATION é configuração global de incidente. O catálogo
contém default=true; registro está atualizado desde 03/09/2026 nos dois
ambientes. Não há evidência sobre quem definiu esse valor ou se houve incidente.
DISABLE_META_MESSAGE_SENDING também true; preservado. Remover a trava de criação
pode ampliar criação/reconexão Meta além das duas contas do assistido. Não cabe
na autorização restrita anterior; exige aprovação específica do alcance global.

Plano concreto: somente DISABLE_META_INBOX_CREATION true -> false nos dois
ambientes, pelo modelo existente, com invalidação de cache após commit. Sem
novo merge/deploy, sem mudar envio, allowlists, features, secrets ou demais
configs. Preflight readonly + comparação exata de value/updated_at/locked sob
row lock no apply; rollback restaura valor original somente se snapshot ainda
igual ao aplicado. Script privado manage-meta-creation-gate.py preparado, não
aplicado. Nenhum inbox/token/cliente recebido ou enviado nesse diagnóstico.

Duas correções locais em readers operacionais, sem alteração de produção:
listener em ForwardConfig ponderado passou a usar o predicate do runbook;
substituição textual ACCOUNT_ID antes colidia com nome de ENV ALLOWED_ACCOUNT_IDS,
corrigida por limite de palavra. Readback final validou allowlist real exata.

Issue995 permanece aberta; PR1112 mergeada. Conexão/teste do painel ainda sem
aceite. Screenshot privado do erro Hub preservado para comunicação ao operador.


Revisão independente Nexo: plano operacional aceito com approval global de
creation por ambiente; enviar mensagens permanece intacto. Se SSM/runner perder
resposta após save!, reconciliar banco e GlobalConfig antes de retry/rollback;
não interpretar timeout/statusfailed como prova de ausência de escrita. Nunca
repetir apply automaticamente. Plans readonly de ambos passaram às 16:30 UTC,
value=true/locked=false e updated_at antigo exatos, sem mutação.

Project995/1112: próximos passos atualizados e sete campos lidos de volta.
Checkpoint público: https://github.com/autonom-ia2/chat/issues/995#issuecomment-6042247856.


## Aprovação global e aplicação — 16:35 UTC

Rodrigo respondeu “pode seguir” ao pedido explícito de desligar apenas a trava
global de criação em ambos ambientes. Aplicação pelo modelo/callback:
Autonomia 16:35:27.984444 UTC e Hub2You 16:35:39.820139 UTC,
DISABLE_META_INBOX_CREATION=false com readback DB/cache consistente. Snapshots
originais/after e rollback condicionado preservados em recibos privados.
DISABLE_META_MESSAGE_SENDING=true foi preservado; nenhuma outra configuração
escrita. Sem novo deploy/merge. Busca do perfil repetida uma única vez por
painel após essa mudança material; ambos retornaram indisponibilidade. Nova
verificação saneada do Client#search irá separar provider/transport/parser;
não inferir necessidade de login a partir do alerta genérico.


## Bloqueio backend/Meta — 16:42 UTC

Após liberação aprovada, uma busca real por painel continuou indisponível.
Diagnóstico único de Client#search por ambiente às 16:36:34 UTC: HTTP400,
HTML1542bytes, meta_unavailable. Não houve401/403, portanto não atribuir à
expiração da sessão. O parser de candidatos não chegou a executar.

Controle de leitura às 16:39:25 UTC usou somente Client#request interno para
RolesTable_Query com configuração canônica e proxy existente; não chamou
InvitationOutcome#reconcile nem enviou convite. Mesma resposta400HTML1542 nos
dois ambientes. Não concluir que somente o endpoint typeahead mudou.

Uma leitura dirigida adicional às 16:40:43 UTC classificou a rejeição sem
exportar corpo/headers/valores privados: headersFacebook presentes, HTML com
marcaFacebook e something-went-wrong, sem marcadores de header-too-large,
plainHTTP-to-TLS ou Squid. Cookie427/349bytes e formulário714bytes; sem valores.
Serverfora de whitelist/ausente. Isso comprova resposta da camada HTTP, não
causa específica. Nada de variantes de host, proxy, payload, av, User-Agent,
TLS/client-hints, retry, doc_id ou bypass foi aplicado.

Backend às16:42:03 UTC: sessão active/presente, managerhealthy em ambos,
restricted_to_authorized_account=true, available/enabled=true, runtime383.
Novas capturas legítimas16:32:38.868 Autonomia e16:40:16.411 Hub2You publicadas
16:32:59.402852 e16:40:44.122915. O navegador legítimo continua renovando sessão;
as chamadas do adaptador Rails permanecem rejeitadas. Essa distinção impede
considerar o assistido homologado ou pedir novo login sem challenge real.

Próximo ponto técnico: conferir contrato real emitido pelo browser e diferença
para o adaptador; não alterar campos/assinaturas por tentativa. Recibo anterior
de browserRolesTableQuery tem200 e roles_valid=true; não existe captura legítima
de typeahead nos recibos atuais. Abertura forçada do canal operador saudável,
replay de captura completa ou acesso oculto ao perfil não foi executado.
Issue995 permanece aberta; conexão/OAuth/teste e eventual reconexão da caixa
não realizados. Infra aceita não substitui esse aceite funcional.


Logs dos pedidos reais pós-liberação, lidos16:43:42 UTC: uma busca por ambiente,
HTTP503 em1428ms Autonomia e1413ms Hub2You. O403 anterior foi resolvido;
a resposta503 do produto foi observada junto da rejeição400 no provider.
Revisão independente Nexo confirma bloqueio de contrato reconstruído antes do
aceite, sem diagnóstico fechado de causa. Menor próximo passo é comparação de
fingerprints estruturais browser/Rails, sem valores privados, e correção apenas
se divergência comprovada; formatoigual exige investigar rejeiçãoMeta semretry.
Project995/1112 atualizado e sete campos conferidos. Checkpoint público:
https://github.com/autonom-ia2/chat/issues/995#issuecomment-6042496526


## Continuação do diagnóstico do pedido backend — 17:02 UTC

Rodrigo pediu resolver o bloqueio; continua o escopo original de observação
legítima e correção, sem novo login por tentativa. Iris prepara observer privado
passivo; Atlas compara client/encoding; Nexo revisa isolamento e retomada.
Root é único executor da VPS. Não tocar os seis deltas antigos, demais serviços,
proxy/Redis/DNS/IAM/Tailscale/n8n ou novo deploy sem aprovação concreta.

Fingerprint Rails obtido às17:02:07 UTC sem nenhuma chamada HTTP adicional:
Client#request_options e sessão canônica atual, somente nomes/tipos/tamanhos de
campos e headers. POSTdevelopers.facebook.com/api/graphql/,20campos,7headers
explicitamente montados, formulário codificado714bytes. Não é prova dos headers
automáticos adicionados pelo Net::HTTP; comparar esse limite com o browser.

Candidato operacional privado preparado: .codex/run-fingerprint-observation.py.
Um único perfilAutonomia, drenar apenas wrapperMainPID, verificar exclusividade,
stopcancelrestart e executar observer sob mesmosUID/groups/env/sandbox/Nodebind/
recursos do manager; deadline e limpeza obrigatórios antes de retomar original.
As outras sete units permanecem iguais. O script não foi executado neste
checkpoint; fingerprint natural ainda precisa de200+roles_valid=true.

### 17:12 UTC — comparação estrutural legítima

Revisão independente liberou observer SHA-256 `e12d8959e8c82191b59fee3f5f4282c6d7c5ca91d30c0cfcf5072af6c1a283e0` e executor com conclusão condicionada a Roles HTTP 200 validado e cleanup comprovado. Execução única, no perfil exclusivo da Autonom.ia, concluiu sem publicação. Browser encerrado, lock próprio liberado, gestor restaurado active/running/PID positivo, outros sete serviços e recursos do gestor preservados.

Resposta natural Roles: HTTP 200, JSON válido, papéis validados, 3.232 bytes. Pedido natural: 21 campos, 737 bytes; aplicação Ruby: 20 campos, 714 bytes. Único nome de campo ausente no Ruby: `server_timestamps`; campo natural é booleano de quatro bytes. Campos comuns e headers explícitos têm os mesmos tamanhos; ordem dos campos difere. Navegador tem também client hints, Accept e `x-asbd-id`; headers automáticos do Net::HTTP não estão no fingerprint das opções Ruby. Nenhum valor de formulário/header, corpo, cookie, token ou ID de cliente foi registrado.

Diferença estrutural ainda não demonstra causa do HTTP 400. Nenhum patch funcional aplicado nesta etapa. Próximo controle em revisão: consulta de leitura Roles pelo cliente existente, isolando esse campo sem alterar identidade, cookies, proxy, TLS ou headers.

### 17:15 UTC — hipótese do campo isolada e refutada

Revisão independente liberou uma única execução privada em Autonomia, com até duas leituras RolesTable_Query pelo Client existente. O snapshot foi congelado no Configuration do processo; todas as opções/headers/cookies/proxy/campos foram comparadas em memória, permitindo apenas `server_timestamps=true` no segundo pedido. Retries e redirects permaneceram desligados. Guards interrompem 401/403/429 e transporte; invalidação da sessão foi neutralizada na instância do diagnóstico para impedir escrita Redis. Nenhum convite, reconciliação de InvitationOutcome, publicação ou alteração persistente.

Recibo completo às 17:15:28.931 UTC: `paired_read_control`, mesma sessão, duas requests e nenhuma interrupção. Baseline 714 bytes: HTTP 400/HTML 1.542 bytes. Controle 737 bytes: mesma resposta HTTP 400/HTML 1.542 bytes. Essa hipótese não explica a rejeição nesse snapshot. Não extrapolar para typeahead/invite, nem copiar client hints ou alterar TLS/proxy por suposição.

### 17:19 UTC — controle público do transporte

Execução única, revisada, de GET público `https://developers.facebook.com/` via Configuration#transport_options da Autonomia, sem session_snapshot, Cookie, Authorization, Proxy-Authorization ou x-fb-*. Timeout 10s, max_retries=0, redirects desligados e proxy explícito sem usuário/senha. Guard no Net::HTTPGenericRequest#exec comprovou GET em origin-form, Host canônico, HTTP/1.1 e somente os nomes de cinco headers automáticos.

Recibo completo às 17:19:03.380 UTC: uma request, HTTP 200, HTML 255.785 bytes, header Facebook presente. Nenhum valor de header ou corpo registrado. Demonstra acesso público pelo transporte configurado; não prova a validade do contrato autenticado nem identifica anti-bot, TLS ou causa específica. Correção permanece bloqueada na rejeição da chamada autenticada, com as sessões e o browser funcionais. Nenhum novo login, deploy ou mudança de configuração foi solicitado/executado nesta etapa.

### 17:26 UTC — estado final de retomada

Leitura de backend 17:25:44 UTC comprovou nas duas stacks: snapshot presente, pointer active, manager healthy, enabled/available/global true, allowlist exata do alvo aprovado e runtime AWS 383ed42f. Hub renovou naturalmente novamente às 17:22:06.573 UTC; isso não altera a contagem de aceite congelada antes dos reinícios. Autonomia preserva a sessão publicada após retomada do diagnóstico, capturada às 17:12:26.856 UTC. Nenhuma publicação pelo reader.

Leitura física VPS 17:26:04 UTC: oito units active/running, MainPID positivo, UnitFileState=enabled. Publishers CPUQuotaPerSecUSec=2s; managers 1.5s/MemoryHigh=1536MiB/MemoryMax=2GiB/TasksMax=256; display/gateway 500ms, demais limites preservados. Sem intervenção nessa leitura.

Continuação documental isolada em branch `codex/995-instagram-provider-evidence-20261007`, baseada em main383; branch anterior e seis deltas antigos preservados. Novo diagnóstico não gerou patch do produto, merge, deploy ou alteração de configurações. Handoff e manifesto recebem checkpoint que substitui estados antigos sem apagar evidências históricas. Próximo trabalho funcional permanece esclarecer a rejeição autenticada/contrato natural de typeahead; não há causa confirmada que justifique nova alteração de produção.

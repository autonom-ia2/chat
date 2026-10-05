# #995 — execução autorizada do runtime Instagram na VPS

Data: 05/10/2026. Checkpoint: 18:43 UTC. Coordenador: root, com seis subagentes para release/corte,
dependências/transporte, identidades AWS, runtime/env, HTTPS e revisão independente.
Esta auditoria acompanha a execução posterior aos relatórios de preparação.
Os recibos anteriores foram preservados; uma observação nova não altera o horário
ou o resultado de uma verificação antiga.

## Autorização e escopo

Rodrigo reiterou autorização às 13:48:39 (America/Sao_Paulo) para publicar a
[PR #1023](https://github.com/autonom-ia2/chat/pull/1023), repetir a preparação
das dependências e prosseguir com implementação, revisão e testes. A autorização
anterior da [Issue #995](https://github.com/autonom-ia2/chat/issues/995) inclui
runtime VPS, identidades de serviço, HTTPS privado, corte coordenado e rollback.
A identidade SSH da VPS já havia sido confirmada independentemente.

Às 15:17:36 (America/Sao_Paulo), Rodrigo autorizou explicitamente os merges e
deploys adicionais necessários quando testes, revisão e CI estiverem verdes.
Pediu consultar a fila da equipe Claude antes de enfileirar e coordenar pelas PRs.
A autorização permite essa comunicação nos comentários pertinentes; não dispensa
os gates técnicos nem autoriza interromper publicações alheias.

O assistido permanece `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false`.
Perfis, cookies, Redis dedicado/geral, outcomes, epochs, caixas e conversas não
foram apagados. Chaves privadas de serviço são geradas na VPS; credenciais
pessoais e sessões dos Macs não são copiadas.

## Estado operacional

Este quadro é um checkpoint, não uma declaração de aceite integral.

| Etapa | Evidência concluída | Pendente |
| --- | --- | --- |
| Correção Rails #1023 | Merge, CI obrigatório, dois deploys e leitura real pós-deploy | Nenhum gate de publicação da corretiva |
| Dependências VPS | TigerVNC, Node privado e helper; host e containers preservados | Nenhum gate dessa instalação |
| Runtime VPS | Release instalada; seis UIDs, oito GIDs; prova DAC; rollback focal confirmado após falha de partida | Corrigir entrypoint via symlink e repetir ativação revisada |
| Env VPS | Oito envs privados, chaves distintas, certificados/config relidos; verify-pair completo PASS | Aceitação com processos ativos |
| IAM/PKI | Duas identidades e CRLs criadas/relidas; certificados/config instalados | Prova Hub recusada; ajuste de trust revisado, nova prova pendente; Aut disabled |
| Env Rails | Transporte privado revisado; capacidade dos parâmetros medida; overlay existente comporta as três chaves | Publicar allowlist compatível, revisar executor e aplicar; nenhuma escrita SSM nessa fase |
| HTTPS | Executores e revisões preparados | Serve, negativos e autenticação real ainda não executados |
| Corte | Inventário Mac, executor revisado e 44/44 testes offline | Parada, troca de pública e ativação dos produtores VPS |
| Meta | Nenhum login/publicação produzido por esta operação | Login/2FA, primeira publicação, renovação e independência dos Macs |

Atualizar o quadro somente após ler os recibos de cada etapa. A Issue #995 continua
aberta até todos os critérios de aceite serem demonstrados.

## Release e produção concorrente

A #1023 foi mergeada pela fila normal em
`4998091221c2a60ab8e7e6ee3316a6ceb0c0a0bc`, às 17:09:02 UTC.
O head aprovado era `ff68ecc1125252e10c5f12a09d201d4faceaf6c1`.
A integração continha alterações adicionais de main, mas nenhum diff nos scripts
Instagram ou na correção de elegibilidade em relação ao candidato aprovado.

Os cinco checks obrigatórios passaram no merge group: RSpec, Vitest, trava,
central e fork-i18n. Os oito shards RSpec passaram. A contagem final do head
incluiu 28 execuções/26 nomes distintos porque trava e central foram reexecutados.
Não confundir essa contagem com a fotografia anterior de 26 checks concluídos.

| Plataforma | Deploy da #1023 | Conclusão |
| --- | --- | --- |
| Hub2You | [37346260662](https://github.com/autonom-ia2/chat/actions/runs/37346260662) | success, 17:23:20 UTC |
| Autonom.ia | [37346260639](https://github.com/autonom-ia2/chat/actions/runs/37346260639) | success, 17:24:01 UTC |

Leitura via SSM às 17:22:41/17:23:01 UTC confirmou, respectivamente, web/worker
no SHA esperado, hashes da correção, API 200, assistido OFF e alinhamento saudável
de CURRENT, listener e target. O teste automático Instagram do push,
[37346260730](https://github.com/autonom-ia2/chat/actions/runs/37346260730), passou.
Não houve dispatch duplicado nem execução de rollback nessa release.

Depois, outro trabalho publicou a #1031 em
`a84196ba4f22888d1bfbd886fd263d73e84e41de`, descendente de `4998091`.
O diff contém CTWA, i18n e guia, sem alteração do runtime/contrato Instagram.
Os deploys [Hub 37349505335](https://github.com/autonom-ia2/chat/actions/runs/37349505335)
e [Aut 37349505336](https://github.com/autonom-ia2/chat/actions/runs/37349505336)
concluíram com sucesso às 17:52:37 e 17:50:26 UTC. Isso não substitui a leitura
de CURRENT antes de cada operação. Uma nova carga de env deve preservar a versão
atual publicada; não reexecutar uma release antiga e reverter mudanças alheias.

A #1033 avançou main para `f5c001261cc0943fefc17e2fd042de4c8e1cdb4f`.
Seus deploys [Hub 37354046416](https://github.com/autonom-ia2/chat/actions/runs/37354046416)
e [Aut 37354046471](https://github.com/autonom-ia2/chat/actions/runs/37354046471)
passaram às 18:26:25 e 18:26:17 UTC. Às 18:35, a #1036 estava na posição 1 da fila,
aguardando os checks. A coordenação ficou registrada nos comentários das
[PR #1036](https://github.com/autonom-ia2/chat/pull/1036#issuecomment-6000632483)
e [PR #1037](https://github.com/autonom-ia2/chat/pull/1037#issuecomment-6000513635).
Essas são fotografias históricas: consultar a fila e os workflows novamente antes
da nossa publicação, sem cancelar nem ultrapassar trabalhos alheios.

## VPS, dependências e isolamento instalado

Destino: `n8n`, hostname `srv707880`, IP `85.31.60.100`.
A manutenção usa SSH com BatchMode, StrictHostKeyChecking=yes, algoritmo
ssh-ed25519, ForwardAgent=no e UpdateHostKeys=no. A divergência do conector SSH
separado não foi corrigida por bypass ou relaxamento de verificação.

A tentativa autorizada do script de dependências, SHA256
`d5cfe54ebcea3610b16c4c4260389ec6748c3bf5d1f1d4866313cc09908ea4c6`,
terminou às 16:56:13 UTC, exit 0, em 32 segundos:

- Três pacotes novos: tigervnc-standalone-server, tigervnc-common e
  libfile-readbackwards-perl; zero upgrades e remoções.
- `dpkg --audit` limpo e suporte Unix do Xtigervnc verificado.
- Node 24.21.0 privado em `/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node`.
- Helper AWS 1.8.5 em `/opt/instagram-meta-tools/aws_signing_helper-1.8.5`,
  conferido contra o checksum oficial.
- Node 18.19.1 do host preservado. Restarts sugeridos por needrestart foram
  adiados; nenhum foi executado pela instalação.
- A verificação de dependências comparou os 47 containers então em execução,
  pelos IDs, Running e StartedAt. O gate posterior de stage/install do runtime
  comparou os 115 containers totais, incluindo parados, acrescentando RestartCount.
  São provas em momentos distintos; não atribuir a segunda à primeira etapa.

A revisão detectou que o primeiro recibo consultava nomes antigos de units.
O original foi mantido. Uma nova leitura às 17:11:33 UTC usou os oito nomes reais
`instagram-vps-{manager,publisher,gateway,display}@{hub2you,autonomia}`
e os encontrou então ausentes/inativos, MainPID 0. O resumo registra 16 critérios
atendidos, sendo um revalidado posteriormente.

O pacote runtime `4998091` tem 40 arquivos e 49.587 bytes, tar SHA256
`356bfcd019ffab705a43bb3da293deba28fe6ecd6e687b1bfc6d3e316577fbc9`.
Stage e preflight passaram na VPS; `npm ci --ignore-scripts` usou o lock Linux.
INSTALL concluiu às 17:28:20 UTC; a verificação separada, às 17:29:33 UTC.
Release/current, seis usuários, oito grupos, memberships, homes e quatro drop-ins
de Node privado foram conferidos. As oito units permaneceram inativas e disabled.

A prova DAC usou os seis UIDs reais: entre os paths privados testados, cada UID
acessou o próprio home/subdiretório e não atravessou os outros cinco homes ou
/etc/instagram-meta. Gateways podem fazer
stat do home browser para derivar UID, sem ler perfil. Esse teste não prova ainda
sandbox Chrome, sockets ativos ou funcionamento Meta.

### Partida real, falha detectada e correção em preparação

A primeira ativação Hub falhou às 18:11:07 UTC no gate startup_unit_failed.
O display iniciou; o gateway saiu com status 0 antes de abrir o servidor.
O rollback focal confirmou ambos parados, com produtores inativos e preservação
da outra stack e dos serviços existentes. Não houve tentativa Aut nem repetição
cega do start. Intenção e recibo de falha permanecem preservados.

A prova no Node 24 da VPS, sem importar/iniciar o gateway, confirmou que
`import.meta.url` usa o caminho canônico da release, enquanto argv[1] aponta ao
symlink `current`. A comparação anterior falha e pula o bootstrap. O mesmo guard
foi encontrado nos demais entrypoints usados pelo fluxo. A correção usa um helper
de stdlib que compara o caminho real do entrypoint, aplicado às sete CLIs, e foi
incluída no empacotamento e CI. O teste de regressão corrigido reproduziu oito
falhas esperadas antes da mudança; após a correção, 21/21 passaram às 18:33:19 UTC,
incluindo imports, stdin, eval e `-pe`. ESLint e diff check passaram. A revisão
independente do código não encontrou bloqueadores; a suíte Python de instalação
está em validação. Nenhum commit/deploy desse candidato foi feito neste checkpoint. Não foi usado flag Node, shell wrapper ou relaxamento de sandbox
para ocultar o defeito. O readiness HTTP impediu a promoção do processo que saiu.


## Webshare e estado dos Macs

Às 17:17:56 UTC, uma requisição da própria VPS a
`https://ipv4.webshare.io/`, pelo proxy Direct `45.58.229.84:5256`,
retornou CONNECT 200, HTTP 200 e egress `45.58.229.84`, em 1,175 s.
TLS foi verificado, .curlrc desabilitado, sem redirects, fallback direto,
usuário/senha de proxy ou acesso à Meta.

O primeiro agregado misturava esse sucesso com uma busca por PermitOpen em
sshd_config. Essa busca não verifica autenticação Webshare e foi separada,
mantendo o recibo bruto. O painel/lista de autorizações do fornecedor não foi
inspecionado; a evidência é a requisição real aceita naquele instante.

A leitura de 17:14–17:16 UTC encontrou os dois LaunchAgents
`com.autonomia.instagram-tester-manager.{hub2you,autonomia}` ativos no M4,
na release privada `afcc85bf7961a5ac23d671136f969f0a75e27169`, com perfis
separados 0700. M2 não apresentou os managers/waiters/browsers/publishers conhecidos.
PIDs desse inventário não autorizam uma parada futura: o corte deve resolver
novamente label, processo, descendentes, tentativa ativa e CURRENT.
Nenhum Mac foi parado nesta fase.

## PKI e correções verificadas na API AWS

Uma CA exclusiva foi criada às 17:19:34 UTC. Sua privada fica em item dedicado
do Keychain do M4, fora da VPS, SSM, repo e artefatos. O helper tem ACL exclusiva,
sem sincronização nem acesso amplo. O probe conferiu roundtrip, recusa de outro
binário sem UI e remoção do item sintético. Temporários privados foram removidos.

O estado público fica em
`/Users/rodrigosilva/dev/chat2you/.codex/instagram-vps-pki/public`.
O certificado CA tem SHA256
`c8746fb3bedfe2a81e55b33e6ba912efc9b54f2e150676f28de71221b4575925`;
expira em 04/10/2029. O binário Keychain estável tem SHA256
`05bdc103d5a0105bcacc030ff504a50e939076eaa5c738f40e52a348411f2b9a`.
Não confundir o hash do binário com o hash de sua fonte Swift.

A execução revelou dois ajustes no plano inicial:

1. ImportCrl exige **CRL PEM**. A forma anterior `fileb://CRL_DER_REVISADA`
   estava errada e foi corrigida antes do import aceito.
   Fonte: [API ImportCrl](https://docs.aws.amazon.com/rolesanywhere/latest/APIReference/API_ImportCrl.html).
2. A API rejeitou a CRL vazia com ValidationException:
   “At least one of the included CRLs doesn't include a revoked certificate.”
   Essa condição é sustentada pela resposta real guardada no recibo.

A solução revisada emite um certificado inaugural real pela CSR, emite o definitivo
com outro serial e revoga o inaugural como superseded. O inaugural nunca é
instalado como certificado ativo. Não foi inventado serial, removida a CRL ou
relaxado o controle de revogação. Fixture OpenSSL: 19/19, incluindo rejeição do
inaugural com error 23 e aceitação do definitivo contra a mesma CRL.

Pares P-256/X509 e SSH ED25519 distintos foram gerados nos homes dos publishers
na VPS, private 0600 e diretórios 0700. Somente CSRs e material público saíram.

| Stack | Emissão real | Inaugural revogado | Definitivo | Validade final |
| --- | --- | --- | --- | --- |
| Hub2You | 17:50:34 UTC | 1000 | 1001 | 04/11/2026 17:50:34 UTC |
| Autonom.ia | 17:55:00 UTC | 1002 | 1003 | 04/11/2026 17:55 UTC |

A CRL compartilhada final contém as duas revogações, SHA256
`b975a02db746a1afc71f222697a0c6214dff27fd56ada9de8284c745c510119e`.
O import/readback Hub concluiu às 17:55:35 UTC; Aut, às 17:57:48 UTC.
Documento, role, trust, policy inicial, anchor e profile foram criados/relidos por
conta. Os profiles estavam disabled ao fim desse provisionamento. Não houve
StartSession ou abertura de canal nessa etapa.

O profile Hub foi habilitado para a prova às 18:26:10 UTC. A identidade de serviço
foi recusada conclusivamente com CredentialRetrievalError; não criou sessões nem
ficou com resultado pendente. O helper retornou AccessDenied com aviso de atributo
O não mapeado. CloudTrail confirmou ARNs, sessionName e duração solicitados, sem
AssumeRole observado; o aviso de O não foi tomado como causa demonstrada.

A revisão identificou que a trust aplicava `sts:RoleSessionName` também às ações
auxiliares. O candidato separa TagSession/SetSourceIdentity de AssumeRole, mantém
SourceArn, SourceAccount, CN e OU em ambos e conserva o nome fixo em AssumeRole.
As referências primárias são [STS](https://docs.aws.amazon.com/service-authorization/latest/reference/list_sts.html)
e o [exemplo Roles Anywhere da AWS](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-creds.html).
Access Analyzer não encontrou findings antes nem depois; 24 fixtures passaram,
mas isso não comprova a hipótese no serviço. O executor foi revisado e liberado
para disable/readback Hub, delta exato, readback, enable e nova prova de identidade.
Aut continua disabled neste checkpoint. Política final de canal depende de um
SessionId real e de testes próprios/alheios; não ampliar recursos para fazer passar.

O helper renova credenciais temporárias, não o certificado X509. Clientes têm
30 dias de validade, com renovação prevista por volta do dia 20; a CRL também
exige atualização antes do vencimento. A custódia offline é uma dependência de
manutenção, não um daemon necessário a cada publicação. Nenhum agendamento
automático de renovação foi criado ou presumido.

## Configuração privada e publicação Rails

O inicializador VPS criou apenas display.env, manager.env e gateway.env por stack.
O readback às 17:42:16 UTC confirmou seis arquivos root:root 0600, diretórios
0700, duas chaves distintas geradas na VPS e oito units ainda inactive/disabled.
A publicação de certificados/config/publisher.env concluiu nas duas stacks,
com instalação e readback unchanged: Hub às 18:09:47 UTC, Aut às 18:11:07 UTC.
As privadas foram revalidadas como regulares, nlink 1, 0600, UID/GID corretos;
o certificado definitivo corresponde à privada. Profiles ficaram disabled e
produtores inativos. Verify-pair completo retornou `instagram_vps_env_pair_ok`,
exit 0, sem executar helper, AWS ou serviços. Nenhum valor secreto foi emitido.

Origens efetivas já conferidas em web/worker:

| Stack | Issuer Rails/gateway | URL privada proposta |
| --- | --- | --- |
| hub2you | https://chat.hub2you.ai | https://srv707880-claudete.tail0c0b18.ts.net/hub2you/ |
| autonomia | https://agents.autonomia.site | https://srv707880-claudete.tail0c0b18.ts.net/autonomia/ |

O plano inicial usava o SecureString principal `/chatwoot/prod/env`, mas as leituras
reais de 18:28 revelaram que o Hub já tinha 4.060 bytes, versão 375 e 87 variáveis,
no Tier Standard. Acrescentar as três linhas exigiria mais 242 bytes e excederia
o limite de 4.096. Aut tinha 3.387 bytes, versão 351 e 73 variáveis. Nenhum parâmetro
foi escrito; não houve mudança de Tier nem remoção de entradas antigas.

A alternativa aprovada usa o SecureString específico já existente
`/chatwoot/prod/instagram-tester-env`, após adicionar exatamente três nomes às
allowlists dos dois deploys. Medição real às 18:35:30 UTC:

| Stack | Versão do overlay | Antes | Após as três linhas previstas |
| --- | --- | --- | --- |
| Hub2You | 7 | 699 bytes / 13 variáveis | 941 bytes / 16 variáveis |
| Autonom.ia | 6 | 522 bytes / 12 variáveis | 768 bytes / 15 variáveis |

Ambos são Standard, SecureString, alias/aws/ssm, automação false e sem as três chaves.
Os workflows apenas leem esse overlay; suas regravações atingem o parâmetro
principal e os ponteiros de release. Isso elimina a disputa de escrita com o
principal. Permanece o gate de compatibilidade: nenhum deploy/bootstrap com a
allowlist antiga pode ler o overlay após a inclusão, pois o recusaria.

O candidato do executor conserva a leitura de FRONTEND_URL no principal, mas
direciona snapshot, backup, versão, gravação e rollback ao overlay. Preserva todas
as entradas anteriores, metadados/KMS e backup 0600. Essa revisão está em andamento;
nenhum apply foi liberado. SSM não oferece CAS e não há lock global contra outros
escritores. Não duplicar as três variáveis no principal.

O rollback exige a versão gravada e o digest do conteúdo aplicado, preserva as
demais entradas e restaura somente quando não existe alteração concorrente.
A revisão corrigiu um P1: esse rollback não depende de SSH à VPS ou exportação
de chave. Se versão/conteúdo mudarem, não restaurar cegamente.

A primeira rails-plan executada retornou falha AWS sem escrever SSM. O diagnóstico
com JSON sintético `{}` reproduziu exit 252/Invalid JSON em
`--cli-input-json file:///dev/stdin`; sem a opção, STS passou nas duas contas.
O caminho é um symlink para o binário oficial Mach-O AWS CLI 2.34.42, não um wrapper
de texto. A função Python passa os bytes explicitamente. Não atribuir o erro a
credenciais expiradas, indisponibilidade AWS ou wrapper inexistente.
O transporte oficial por arquivo JSON regular 0600 em diretório temporário 0700
passou seis provas sintéticas no mesmo CLI, incluindo STS nos dois profiles,
validação PutParameter somente com skeleton e limpeza em sucesso/erro/timeout.
A revisão independente aprovou a alteração focal de aws() com sete fixtures de
privacidade e cleanup. O payload não vai para argv/stdout; stdin fica DEVNULL.
Nenhuma API SSM de leitura de env ou escrita foi chamada por essas provas.

Alterar SSM não atualiza containers já em execução. Após aplicação validada será
necessária uma publicação blue/green autorizada na versão atual, sem dispatch
duplicado ou reversão de código alheio.

## Ferramentas: falha transitória e não execução

Ocorreram retornos “Native routing blocked: enrollment outcome unavailable;
no local replay” em uma tentativa de INSTALL, na cópia de pki.py e em uma chamada
rails-plan. A inspeção do middleware mostrou o catch antes do executor; registro
e ledger não receberam operações correspondentes. Recibos e estado dos alvos foram
reconciliados por leitura antes de cada nova tentativa.

Canários inofensivos pelo caminho normal passaram. As novas tentativas liberadas
usaram a mesma ferramenta, comando e guardas: INSTALL e cópia PKI concluíram;
rails-plan executou e revelou a falha distinta do parser AWS descrita acima.
Nenhum dispatcher interno, LaunchAgent, timeout, registro, ledger, permissão ou
rota foi alterado. O detalhe do erro de enrollment é descartado pelo wrapper;
a causa específica permanece desconhecida, sem atribuição causal à concorrência.

## Próximos gates e rollback

1. Publicar a correção do entrypoint após revisão, testes/CI e consulta à fila;
   certificados/config/publisher.env e verify-pair já passaram.
2. Iniciar somente display/gateway de uma stack; exigir readiness HTTP real,
   UID/GID, Unix VNC, permissões, Node privado e preservação dos demais serviços.
3. Aplicar Serve e executar negativos/autenticação sintética na primeira janela
   sem operador, uma stack por vez, preservando nonces.
4. Habilitar identidade somente na prova coordenada; demonstrar STS, revogação,
   nome de sessão, SessionId real, canal próprio e recusa de sessão alheia.
5. Confirmar allowlist nova em main e ausência de leitores antigos; aplicar as
   três chaves no overlay dedicado e carregar pela publicação normal.
6. Cortar Mac/pública SSM/CURRENT com backup e drain; não restaurar enquanto
   existir comando SSM anterior não terminal ou resultado incerto.
7. Ativar publisher/manager VPS; provar sandbox, transporte e fluxo SuperAdmin.
8. Handoff humano Meta, primeira publicação, renovação e independência dos Macs.
   Somente após aceite habilitar as units para boot.

Rollback da primeira instalação: parar somente units novas e remover somente
mounts desta entrega. Preservar perfis, chaves, nonces, Redis e releases.
Rollback de pública SSH restaura o valor anterior numa **nova versão SSM** e no
CURRENT revalidado, depois recupera somente o LaunchAgent original correspondente.
O executor do corte deve preservar a outra stack e esperar término real dos
comandos SSM antes de qualquer restauração.

## Localização dos recibos e rastreabilidade

Recibos operacionais sanitizados ficam no diretório da sessão
`tmp/approved-1023-20261005/`, dentro da worktree do projeto: release/,
dependencies/, runtime/, aws/, https/ e review/. Arquivos privados de backup/env
não integram este documento nem devem ser commitados. O HANDOFF dessa sessão
contém o ponto de retomada; approved-1003-20261005 é histórico.

O Project [Autonom.ia Dev](https://github.com/users/autonom-ia/projects/3) foi
atualizado e seus sete campos foram relidos: Issue #995 Em desenvolvimento,
Infra/P1/Alto/Produção; PR #1023 Mergeada, Bug/P2/Médio/Produção, ambas Hub2You.
A branch de continuidade é `fix/995-vps-symlink-entrypoint`, renomeada após a
falha real de partida para incluir a correção e suas evidências.
A worktree foi reutilizada; não foi criada uma 32ª worktree nem removido o diretório
que contém executores e evidências ativos.

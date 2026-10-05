# Release operacional Instagram — #960

## Bootstrap bloqueado depois da preparação local — correção #960

A PR #962 já foi publicada nas duas stacks e os cinco metadados foram salvos.
Os estados históricos abaixo não são instrução para repetir deploy/Redis/SSM.
No teste humano de 04/10/2026 às 23:49 UTC, a preparação local terminou, mas
nenhum gestor foi carregado. O log SSM da própria tentativa registrou:
`Forwarding to IP address 127.0.0.1 is forbidden.`

O publisher encaminha SSH da **própria instância gerenciada**, portanto deve usar
`AWS-StartPortForwardingSession` com `portNumber=22` e porta local, sem `host`.
`AWS-StartPortForwardingSessionToRemoteHost` é destinado a outro host. Não
desabilitar a proteção de loopback, trocar IP para contornar a regra nem ampliar
permissões. Validar autorização do documento correto nas duas contas.
Referência: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html

O comando forçado usa `bundle exec ruby scripts/instagram_testers/session_publisher.rb`.
A entrada reserva stdout/stderr do protocolo e silencia logs **antes** de carregar
o Rails; somente JSON validado ou erro fixo saem pelos canais reservados.
Não chamar essa entrada por `rails runner`, pois logs anteriores ao script
contaminariam a resposta. Não mudar o logger global do web/worker.

Publicar CLI e wrapper compatíveis antes da retomada pessoal. Na preparação
parcial, preservar perfil/cookies/locks e os arquivos existentes. `STARTING`
sozinho não certifica prontidão: conferir fontes, wrapper, os dois plists, ausência
de gestores/atividade e as três leituras tipadas em **ambas** as stacks antes do
primeiro carregamento. `LOADED` ausente não prova que nada chegou a iniciar.
Global OFF continua obrigatório até homologação; não enviar novos convites.

Diagnóstico e limites: `docs/audit/960-bootstrap-local-ssm-20261004.md`.

## Estado confirmado — 04/10/2026, 20:53 UTC

**Transporte PASS encerrado; ativação funcional pendente.** O confronto AWS das
20:48 UTC confirmou recibos Success de TLS/auth/epoch Redis, HTTPS pelo proxy e
egress residencial nas duas stacks, preservando CURRENT e aplicação.
Não exige reinstalação do transporte. Não comprova autenticação Meta, runtime
ativo, exclusão entre stacks ou publicação do candidato novo.

Leitura READONLY das 20:53 UTC, sem Rails/Redis:

| Stack | SHA da aplicação | ENV assistido | ENV coordenação presente |
|---|---|---|---|
| Hub2You | `3eedd520` | `true` | `true` |
| Autonom.ia | `8be08f50` | `true` | `false` |

Presença do ENV de coordenação legado não prova uso do auxiliar novo testado;
ausência desse ENV na Autonom.ia não desfaz o PASS de transporte do auxiliar.
Fontes locais: `tmp/final-release-20261004/{activation-readiness.md,release-safety-review.md,transport-aws-confirmation.json,cutover-readiness.json}`.
São recibos datados; esta documentação não executou nova inspeção de produção.

## Corte mínimo — plano ainda não executado

1. Manter Issue → Branch → PR → Project update → Review → Approval → Merge →
   Deploy/Rollback. Merge/deploy e ações operacionais exigem aprovação explícita
   do Rodrigo; documentação e PASS de transporte não concedem essa aprovação.
2. Compor um único candidato incluindo #937 e #956, sem merges intermediários.
   Conferir SHA, CI/review e PR/Project; não reutilizar aceite de outro SHA.
   Backend, publisher Ruby, protocolo Node, transporte, forced-wrapper,
   browser, observer, gestor, wrapper/waiter e supervisor devem ser compatíveis.
3. Antes de enfileirar o candidato aprovado, suspender o assistido **por stack**
   no overlay dedicado e manter publishers
   suspensos; drenar emissores/invalidadores antigos antes do cutover. Registrar
   última escrita antiga. ENV assistido `true` observado não significa suspensão
   executada. Reiniciar states/seleções/capturas em trânsito após estabilizar versões.
4. Enfileirar somente após aprovação; aguardar estado **MERGED**, não apenas
   aceite da fila. Na green, instalar o auxiliar com scripts **da imagem candidata** e passar
   preflight antes de mover workers/tráfego; conferir protocolos e novo CURRENT.
   Não reprovisionar o Redis dedicado para repetir prova já encerrada.
5. Antes de **NOVOS convites**, exigir reconciliação verificada dos outcomes antigos
   ou expiração efetiva de **24h após o último escritor antigo**, com escritores
   drenados. Não há migrador automático demonstrado nem ordem operacional já
   executada. Este plano não autoriza varredura, limpeza ou mudança global.

## Preparação e ativação controlada, após deploy aprovado

1. Em cada instalação, salvar os cinco metadados pelo **SuperAdmin → Settings →
   Instagram → Abrir automação Instagram**: App pai, Business, nome do App,
   administrador e `doc_id`. Preservar `INSTAGRAM_APP_ID` e configuração OAuth.
2. Validar `bootstrap` pelo publisher privado: cinco registros válidos no banco,
   configuração/revisão canônicas. ENV antigo não substitui essa etapa.
3. Conferir versão e metadados antes de iniciar o gestor. Preparar runtime,
   wrapper, waiter e supervisor coerentes por stack; o template `hub2you` não
   prepara Autonom.ia. Usar dois perfis privados independentes no M4: preservar
   o perfil Hub2You existente e reservar um perfil próprio da Autonom.ia, sem
   copiar cookies/perfis. Cada LaunchAgent tem Label, logs e publisher próprios:
   `--stack hub2you` usa AWS `hub2you`; `--stack autonomia` usa AWS `financial`.
   Gestor e waiter da mesma stack recebem o mesmo ambiente. Código/dependências
   podem ser compartilhados; nunca executar dois gestores no mesmo perfil.
   Esse arranjo é suportado pelo código e foi revisado; instalação/ativação dos
   dois runtimes e eventual login do perfil Autonom.ia continuam pendentes.
4. Reutilizar sessão/perfil válido existente, sem novo login se possível. Se Meta
   exigir recuperação, humano faz login/2FA e fecha a janela; wrapper/waiter
   conduzem a publicação. Botão de reconexão não instala nem liga gestor parado.
5. Comprovar primeira e segunda publicação/renovação, heartbeat, alerta recebido,
   reconexão e exclusão entre stacks. `202` é pedido aceito; `succeeded` é sessão
   publicada, não inbox conectada. Homologar convite/aceite quando necessário,
   OAuth, webhook e DM de ida/volta **por stack**, além dos caminhos ON/OFF.
6. Gate de rollout: novas contas ON conforme contrato/default; existentes somente
   em lote controlado, com dry-run, contagens revisadas e aprovação. Preservar OFF
   e marcadores; não religar OFF. OFF histórico sem marcador exige revisão humana.
   Ampliar assistido somente com os gates anteriores comprovados por stack.

## Rollback e preservação

Reversão conjunta deve estar aprovada antes do corte: retornar à instância
imediatamente anterior, entregando o helper ao host legado; restaurar web/worker
com assistido OFF no overlay, **sem depender do Redis/proxy novos**. Conferir
listener, workers, CURRENT e destino do publisher juntos. Cobertura offline não
prova rollback real. Preservar nomes SSM, ENV global/base, chaves de cifra,
sessões, outcomes, namespaces, tokens, inboxes, conversas e marcadores.
Não apagar proteção de resultado incerto nem invalidar sessão ativa para destravar.

O launcher **M2 ainda referencia scratch**: preservar este worktree até o
empacotamento definitivo e conferir caminhos/versões antes de iniciar. Preparação
inativa não comprova runtime ativo. Runtime/Meta/homologação permanecem pendentes.

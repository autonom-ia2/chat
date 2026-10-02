# WAHA 2026.9.2 — revisão independente de preparação

Data: 2026-10-02
Issue: https://github.com/autonom-ia2/chat/issues/846
Origem revisada: `ff0f05293271c3d9c2d9fa25ef228188ace86b2d`
Base do candidato: `43901a40c2eb6ef43cf3e5052c297879e0abdbd4`
Status: **REGISTRO HISTÓRICO DA ÁRVORE ANTERIOR**.

Os dois P1 e o P2 abaixo foram corrigidos na origem em commits isolados #850/#851/#852.
O candidato atualizado sobre a main `ffa7ce96920687f3d4d7d43124b78063006b407e` incorpora essas correções.
Não usar a bateria nem a decisão antigas abaixo como gate da nova árvore. Estado atual e validação final:
[fechamento do candidato](2026-10-02-waha-final-candidate-readiness.md).

## Método e limites

Dois revisores independentes, separados por domínio, seguiram a skill
`dispatching-parallel-agents`: um revisou cliente, configuração, provisionamento, planner/executor/updater,
cleanup e rake; outro revisou conversa, eventos, métricas, jobs e compatibilidade Enterprise/blue-green.
Ambos trabalharam somente leitura, sem banco compartilhado, HTTP/WAHA ou produção. O coordenador executou
a bateria local de release sobre um candidato separado. Nenhum código de produto foi corrigido nesta etapa.
R1–R5/N1–N3 e o ajuste local do relógio foram preservados integralmente no candidato.

Suíte verde não elimina os dois caminhos bloqueantes abaixo: faltam cenários que os cubram.
O [plano de publicação/piloto/rollback](2026-10-02-waha-release-and-pilot-plan.md) depende de seu fechamento.

## P1 — snapshot incoerente entre as leituras do planejamento

Arquivo: `app/services/waha/existing_inbox_migration_planner.rb`, linhas 48–62 e 126–135.

O planner captura o Chatwoot em `get_app`, mas captura a lista completa depois, em `list_apps`.
Ele verifica presença/tipo/ID do Chatwoot na lista, sem comparar sua configuração com o App individual.
Se outro escritor mudar o Chatwoot entre essas leituras, o snapshot guarda a versão antiga em `chatwoot`
e a nova em `apps`. O plano deriva o payload do App antigo; N1 compara a lista atual com a lista nova do
snapshot e aceita. O PUT sobrescreve a mudança que aconteceu durante o próprio planejamento.

Isso é diferente da janela residual já documentada entre a última leitura e o PUT. Aqui a intervenção
ocorre antes do preflight N1 e deveria ser detectada. Presença dos checks N1 atuais não garante proteção
contra esse caminho.

Correção mínima proposta, um item por vez: conferir integralmente que o App individual coincide com o App
correspondente da lista; em divergência, abortar o planejamento sem escrita, sem merge e com motivo explícito.
Outra solução seria planejar inteiramente a partir do App da lista, com as validações de identidade aplicadas
a ele; a opção fail-closed torna a intervenção concorrente explícita. Preservar a comparação N1 antes do PUT
e a parada do lote. Novo teste deve intercalar a alteração entre `get_app` e `list_apps`, confirmar ausência
de PUT/gravação local e preservação da configuração nova.

## P1 — confirmação final ignora sessão que voltou a parar

Arquivo: `app/services/waha/existing_inbox_migration_executor.rb`, linhas 60–64.

O polling pode observar `WORKING`, e a sessão pode cair para `STOPPED` antes da leitura seguinte.
`verify_remote_state!` confirma configuração/Apps, mas não verifica o status dessa leitura final.
Nesse caminho, o executor grava os atributos locais e retorna `UPDATED` mesmo com a sessão parada,
violando a condição de sucesso exigida por R1.

Correção mínima proposta: exigir `WORKING` na mesma verificação final que confirma configuração/Apps.
Se não estiver operacional, acionar a recuperação existente, sem persistência local. Novo teste deve
reproduzir `WORKING` no polling e `STOPPED` na confirmação final, garantir ausência de gravação local,
verificar a recuperação e a parada do lote. Não acrescentar retry ou fluxo de pareamento.

## P2 — duplicidade do resolver não é bloqueada

Arquivo: `app/services/waha/existing_inbox_migration_planner.rb`, linhas 122–166.

`find_phone_numbers_app` seleciona o primeiro App pelo nome. Havendo dois `brazilian-phone-numbers`,
o plano preserva ambos e pode anunciar sucesso/compatibilidade, enquanto o aceite exige exatamente um.
Só um ID fica vinculado localmente ao cleanup. O revisor também apontou que ID/sessão do App escolhido
não são validados; a ocorrência de payload inválido vindo da WAHA não foi demonstrada nesta etapa.

Tratar duplicidade como pré-requisito bloqueante, sem apagar ou fundir Apps automaticamente. Revisar uma
eventual validação de identidade conforme o contrato real da API, evitando ampliar escopo com guardas
especulativas. Cobrir duplicidade em teste separado antes de liberar caixas nesse estado.

## Métricas: limites residuais e condições operacionais

- A duração de `conversation_resolved`, horário comercial, bot e rollup usa o mesmo início capturado.
  O evento próprio de `conversation_opened` continua dependente da resolução anterior já persistida:
  se seu job executar antes, grava zero e não recalcula depois. Limitação P2 já declarada no documento de
  backfill; não foi parte da alteração N2 de duração da resolução. O spec de ordenação verifica a resolução,
  não garante a duração de abertura. Não apresentar esse evento como corrigido.
- O listener reavalia WAHA + `lock_to_single_conversation` no consumo. Desativar a trava depois de resolver
  e antes de consumir o job descarta o timestamp capturado e volta ao cálculo legado. A trava é mutável pela
  API. Manter provider/trava estáveis até o escoamento dos eventos e a aceitação do piloto; se o produto
  precisar suportar sua alteração nesse intervalo, tratar como item separado.
- Blue-green mantém a assinatura do `EventDispatcherJob`. Worker antigo ignora a chave nova; worker novo
  aceita evento antigo sem snapshot e conserva `created_at`. Não foi encontrado erro de classe/serialização;
  métricas durante a transição mantêm os limites legados. Todos os workers devem estar na imagem nova antes
  do piloto, que deve iniciar um ciclo novo após o deploy. Não há recálculo histórico.
- `freeze_time` permanece limitado ao grupo de specs de tempo de resposta em `conversation_spec.rb:1133`,
  sem mudar assertions, tolerância ou comportamento de produção.

## Provisionamento: risco anterior, fora das correções deste candidato

O revisor identificou no caminho de criação/cleanup a possibilidade de apagar uma sessão preexistente
quando o POST falha e a Inbox é destruída: o callback local e o cleanup remoto podem tentar removê-la.
Referências: `inbox_provisioner.rb:55–64` e `channel/api.rb:73–83`. A leitura do código sugere risco em retry
com nome já existente; não houve reprodução operacional. Não é uma regressão nova deste delta e não foi
corrigido neste preparo. Piloto do backfill não cria Inbox/sessão e não deve usar novo provisionamento como
fallback para uma falha. Uma correção desse caminho exige escopo e teste próprios.

## Reprodução isolada dos achados do migrador

Harness fora do repositório:
`/Users/rodrigosilva/dev/projetos.noindex/waha-review-proof-20261002/proof.rb`.
SHA-256: `2f91869fe78de4add9b5f2c998bf1445cdf29231008f2ce28bf99a89e394f334`.
Carrega BrazilianPhoneNumbers, planner, executor e updater reais da origem revisada;
cliente, objetos de modelo e transação são mocks locais. Não carrega Rails, banco ou HTTP.

```bash
env -i PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:/usr/bin:/bin \
  /Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby \
  /Users/rodrigosilva/dev/projetos.noindex/waha-review-proof-20261002/proof.rb
```

Saída confirmada pelo revisor:

```text
CASE 1: individual GET is old, list GET is new
GET_APP_CUSTOM=old
LIST_APP_CUSTOM=new
PREFLIGHT_LIST_CUSTOM=new
PUT_CHATWOOT_CUSTOM=old
OUTCOME=updated
CASE 2: WORKING polling followed by STOPPED final verification
SESSION_STATUSES=WORKING>WORKING>STOPPED
PUT_CALLED=true
DESIRED_PHONE_APP_ID=br_new
OUTCOME=updated
LOCAL_LOCK=true
LOCAL_PHONE_APP_ID="br_new"
CASE 3: two brazilian-phone-numbers Apps remain preserved
DUPLICATE_COUNT=2
PRESERVED_IDS=br_1>br_2
ALREADY_COMPLIANT=true
RETURN=unchanged
RESULT_UNCHANGED=1
LOG=[waha][existing_inbox] OK account=7 channel=11 inbox=11 already compliant
```

Dados inteiramente sintéticos. A terceira prova chama `process_channel` do updater real com Result real,
sem entrar no escopo de banco do `perform`; demonstra classificação como compatível, sem invocar o executor.
As duas primeiras exercitam o executor real. Essas provas reproduzem bugs; não são evidência de correção.

## Validação local

Ruby 3.4.4 via rbenv, `RAILS_ENV=test`, `POSTGRES_HOST=localhost`, `POSTGRES_DATABASE=chatwoot_test`.
Banco local de teste somente; os revisores não executaram suítes concorrentes nesse banco.

```bash
bundle exec rspec spec/services/autonomia spec/requests/api/v1/accounts/autonomia \
  spec/models/autonomia spec/jobs/autonomia spec/services/crm spec/controllers/super_admin \
  spec/configs spec/lib spec/services/waha \
  spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb \
  spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb \
  spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb
```

Resultado lido: **5566 examples, 0 failures, 12 pending**; saída 0, 8m22s mais 54s de carregamento.
Os pendentes são três avaliações pagas desativadas e nove quarentenas já marcadas nos specs.
Incluem os três pendentes do handoff (WebhookListener:127 e Conversation:774/802) e mais seis selecionados
pela bateria fixa do release. Nenhum exemplo foi removido/desabilitado nem tolerância ampliada nesta etapa.
As avaliações pagas não foram habilitadas.

Node 24.11.0 e pnpm 10.2.0 do projeto:

```bash
pnpm test app/javascript/dashboard/routes/dashboard/autonomia \
  app/javascript/dashboard/components/autonomia app/javascript/dashboard/components-next/sidebar \
  app/javascript/dashboard/i18n app/javascript/dashboard/api
pnpm guia:build
pnpm guia:check
pnpm central:check
```

Vitest: **133 arquivos passaram, 1354 testes passaram**, saída 0. A primeira tentativa falhou antes de
coletar testes por `fake-indexeddb/auto/index.mjs` ausente no `node_modules` emprestado da origem.
O symlink foi removido somente no candidato; `pnpm install --frozen-lockfile` instalou as dependências
nesse worktree e a repetição passou. Nenhuma dependência/lockfile versionada foi modificada.

Guia: build/check passaram, 174 fluxos, 171 telas, zero telas sem explicação; quatro explicações sem rota
informadas pelo build. A geração não produziu delta adicional. Central: saída 0, `Central em dia: 175 artigos,
171 telas cobertas`, com avisos não bloqueantes de evidências/linhas; nenhum artigo foi reescrito nesta etapa.

RuboCop de todos os `.rb`/`.rake` do delta: **19 files inspected, no offenses detected**, saída 0.
O delta não inclui JS/Vue, portanto o lint frontend restrito a arquivos tocados não tem entrada.
`git diff --check` e `git diff --cached --check` passaram; o único whitespace corrigido é a linha Data do handoff copiado.
Commit do candidato: `0605e7671a4c1605f871ef5f10ec43cb37db1a5f`, com hooks normais aprovados.
O patch commitado coincidiu byte a byte com o revisado; o hook não reescreveu arquivos.
SHA-256 do patch: `2d6126ec7e6113f22df59c399b6a169cd41ec32f45e8fb25a8257ca4fdfb0b42`.
Push confirmado por `git ls-remote`; PR draft https://github.com/autonom-ia2/chat/pull/848.
Não houve alteração funcional em relação à origem e nenhum achado foi fechado.

Durante a preparação, a `main` avançou pelo merge do lote Kanban #847 para
`ab84a219bdd30f287ed0011ed61d62ec43f1fab4`. Na consulta de 2026-10-02 16:42 UTC, ambos os deploys
estavam em andamento. O candidato validado continua baseado em `43901a40c2`; não foi feito rebase,
merge ou deploy nesta tarefa. Os resultados acima não certificam a nova base. A montagem do lote WAHA
precisa aguardar a aceitação do anterior e repetir a bateria na árvore final.

## Decisão

Não liberar o candidato mesmo com testes e CI verdes. Prioridade: fechar primeiro a incoerência de snapshot,
depois a confirmação final de saúde, cada um com commit/teste/revisão isolados. Resolver a duplicidade
antes de liberar caixas em estado ambíguo. Manter os limites das métricas explícitos e o procedimento do
piloto restrito. Ainda são necessários lote exclusivo após o lote atual, evidência de rollback das duas
instalações, IDs do piloto e autorizações operacionais de Rodrigo.

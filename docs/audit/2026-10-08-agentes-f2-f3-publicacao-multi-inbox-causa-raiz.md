# Publicação multi-caixa — causa raiz e contrato

**Data:** 2026-10-08  
**Escopo:** publicação do agente na etapa **Ligue**  
**Estado:** registro antes da implementação

## Causa observada

O contrato atual de `POST /autonomia/agents/:id/publish` aceita somente o campo
top-level `inbox_id`. O `Publisher` recebe uma única caixa e o
`InboxConnector` cria um único vínculo por chamada. O modelo já permite várias
caixas por agente, mas a unicidade ativa é por `inbox_id`; por isso repetir
chamadas independentes não fornece a atomicidade exigida para a publicação.

O painel antigo continua associando caixas uma por vez por
`POST .../channels`, e esse caminho precisa permanecer compatível. A extensão
de publicação será aditiva: `inbox_id` singular continua válido e
`inbox_ids` aceita somente um array JSON de inteiros positivos, sem coerção,
duplicatas ou mistura dos dois campos.

## Correção contratual planejada

Antes de qualquer escrita, todas as caixas serão resolvidas na conta atual e
validadas. A publicação deverá manter um único `transaction`, com lock do
agente e das caixas em ordem determinística. Webhook ocupado, vínculo nativo
existente, conta incorreta ou erro em qualquer caixa abortam a operação inteira;
nenhum agente parcialmente ativo nem vínculo parcial pode permanecer.

Agente interno continua sem caixas. A criação de cada vínculo preserva o
espelho nativo individual (`AgentBot`, `AgentBotInbox` e `AgentInbox`). Não há
mudança de schema prevista: a unicidade ativa por caixa já existe na migração
`20261006170000_add_soft_deletion_to_autonomia_agents.rb`.

## Evidência local consultada

- `app/controllers/concerns/autonomia/agents/publish_contract.rb`
- `app/controllers/api/v1/accounts/autonomia/agents_controller.rb`
- `app/services/autonomia/agents/publisher.rb`
- `app/services/autonomia/agents/operate/inbox_connector.rb`
- `app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb`
- `app/models/autonomia/agents/agent_inbox.rb`
- `db/migrate/20260617120000_create_autonomia_agent_inboxes.rb`
- `db/migrate/20261006170000_add_soft_deletion_to_autonomia_agents.rb`

Nenhum banco, serviço, teste Rails ou produção foi acessado nesta etapa.

## Correções e validação local após o aceite parcial do Rodrigo

Rodrigo aceitou as demais telas de criação e apontou dois ajustes: alinhar os
controles do compositor de Teste e permitir várias caixas existentes em Ligue.
A implementação continua restrita à worktree e à branch indicadas no handoff.
WhatsApp continua conectado na área central Canais.

A causa do compositor inclui a regra global de textarea em _base.scss: margem
inferior de 1rem e altura de 4rem. O campo de Teste agora usa mb-0, h-11 e
resize-none; os dois botões usam size-11 e a linha usa items-center. A regra
global não foi alterada. O navegador valida centros verticais com diferença
inferior a 1px e alvos de pelo menos 44px.

A primeira execução nativa52 encontrou uma perda real de seleção: a tela
mostrava canais da etapa anterior enquanto loadEntry aguardava loadAgent/resume.
Depois o fetch de canais limpava eligible e o watcher removia os IDs marcados.
A captura06 registrou duas caixas; o contexto posterior registrou nenhuma e
Ligar agente desabilitado. Não foi corrigido com espera ou retry no teste:
loadChannels começa junto com loadAgent no início de loadEntry, e o fetch tardio
foi removido. Um unit com resposta atrasada do agente e asserts nativos após a
checagem de acessibilidade cobrem a regressão.

Snapshot53: 20261008-103248-532a5b7b-a52da2fa5d-0f32aeaa, SHA-256
 a52da2fa5dfc6673743d31f1d4c2fdd32e63b6f4d5306aa0aa8eb3d8a649cfde.
RSpec: 34 exemplos, zero falhas. RuboCop: 9 arquivos, zero ofensas.
Os formatos foram gerados pelo método oficial Formatos.gerados em Rails isolado,
exportados fora do snapshot e importados mecanicamente; formatos:check passou.
As réplicas M2/M4 foram verificadas. Recibos: .codex/preview/check53/backend53-logs.
A conferência visual e o parecer R1 deste escopo ainda estavam pendentes neste
registro; os resultados finais serão acrescentados abaixo.

As falhas de fixture/lint e a execução interrompida por proteção térmica são
validação, não rodadas de revisão. Nenhuma proteção térmica foi contornada.
Não houve nova migration, commit, push, PR, fila, merge, deploy ou produção.

## R1 e correção final de altura no celular

A R1 independente registrou somente F2-F3-MULTI-R1-01: em 400 px, o placeholder
quebrava em duas linhas, mas h-11 com py-2/leading-6 cortava a segunda. A
correção mínima passou a usar h-16 sm:h-11; mb-0, botões de 44 px e o
alinhamento pelo centro foram preservados. A aplicação não recebeu outra
alteração entre os snapshots53 e54. Parecer: docs/agentes-ia-redesign/revisoes/F2-F3-multi-inbox-r1.md.

Snapshot54: 20261008-105028-532a5b7b-5711deea65-548ec6fb, SHA-256
5711deea65fa462600d85866574c9a3c71f1d031d7cd07040d4a92ab36423ee4.
M2/M4 consistentes antes/depois. Lint do componente: zero erros, 46 avisos de
catálogo preexistentes. A jornada principal real foi repetida nos quatro
perfis, em banco sintético54 separado: quatro casos aprovados, zero falhas.
Recibo: .codex/preview/check54/driver54-final.log.

A matriz53 permanece a evidência dos demais cenários: 45 aprovados, zero
falhas, três repetições de mutação F1 omitidas por projeto e quatro extras
de material aprovados. JavaScript: 115 casos; i18n: 13 catálogos e 20.448
mensagens compiladas. Não se repetiram testes não afetados pela altura CSS.

A leitura da galeria53 confirmou HTTP200/HTML, 68 capturas, 20 comparações,
filtros16/16/18/18, autenticação200, Escolha real, claro30 preservado e duas
caixas marcáveis. Sem pageerror ou rede fora do loopback. O job de leitura
aguardava workspace-busy porque o servidor da mesma réplica mantém seu lock;
foi cancelado somente esse job e a leitura executada via maccluster exec
explícito M2 após o plan aprovado. Recibo: check53/gallery-direct53.log.

A primeira preparação54 foi interrompida antes dos testes ao detectar um
helper com caminho reservado à futura ligação ao banco50. Não havia symlink
ainda: era um diretório novo de teste. Ele foi arquivado, o helper foi corrigido
para runtime-m2-creation54 e semeadura exclusivamente sintética54. O banco50
com o agente do Rodrigo não foi semeado, apagado ou substituído.

Exportação54, prévia preservada e revisão R2 continuam pendentes neste ponto;
o resultado final será registrado abaixo. Sem nova migration ou ação de release.

## Conclusão local54 — dois ajustes encerrados

A R2 do mesmo revisor encerrou F2-F3-MULTI-R1-01 e não encontrou outro achado
acionável. Parecer: docs/agentes-ia-redesign/revisoes/F2-F3-multi-inbox-r2.md.
Não foi necessário R3, nem se abriu quarto ciclo.

A prévia final usa código54 e preserva o banco50 com claro30. Somente a
altura do AgentTestPhone.vue mudou em app/enterprise/config/lib contra53,
confirmado por git diff --no-index --name-only nessas quatro árvores. Os
leitores isolados confirmaram no agente preservado: textarea44px desktop e
64px mobile, botões44x44px, diferença dos centros0px e espaço para o
placeholder nos quatro perfis. Nenhuma mensagem de teste foi enviada e não
houve publicação do agente do Rodrigo nessas leituras.

Galeria: HTTP200/text-html, 68 capturas reais, 20 comparações/108 imagens,
filtros16/16/18/18 e portal autenticado chegando à Escolha real. claro30
continua presente; duas caixas puderam ser marcadas localmente. Sem pageerror
ou rede fora do loopback. HTML servido e arquivo local têm o mesmo SHA-256:
c0f79734f0c1aad3bbe8683fd887e3b593ab02f0f9a1d276f9b964fdfbfa84c9.

As capturas regeneradas54 e as capturas não afetadas53 têm proveniência por
arquivo em .codex/preview/check54/capture-provenance.json. O compositor móvel
escuro, Ligue real com duas caixas, claro preservado e galeria móvel foram
lidos em resolução original. Os demais perfis do compositor e estados
Teste válido/invalidado foram inspecionados pelo revisor independente.

Recibos finais: check54/verify-preview54-read.json, read-composer54.log,
read-gallery54.log, served-gallery54.json e export-composer54.json.
Prévia: http://127.0.0.1:59720/preview-telas e /preview-criacao.

Esses resultados são locais: não representam CI verde ou aceite humano
final dos dois ajustes. Sem nova migration, novo PR, commit, push, fila,
merge, deploy ou produção. PR1115 permanece congelado; Automação mantém
a coordenação da fila e dos deploys.

Issue1138 atualizada com o resultado local54: https://github.com/autonom-ia2/chat/issues/1138#issuecomment-6061626847.
Project3 confirmado pela API do item existente: dono pessoal autonom-ia, URL
https://github.com/users/autonom-ia/projects/3, e não organização autonom-ia2.
O campo Próxima ação foi atualizado para o aceite visual dos dois ajustes;
nenhum status de release foi autorizado. Recibos: project1138-node.json,
project-fields.json, project1138-update-receipt.json e project1138-after.json.
A consulta inicial ao dono errado retornou ProjectV2 não encontrado; a causa
foi identificada pela URL do projeto no node do item, sem repetição cega.

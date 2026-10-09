# F0 — RED de rotas, compatibilidade e retomada

**Data:** 2026-10-07  
**Estado:** RED preparado; não executado.  
**Escopo:** somente specs novas de frontend e este registro. Nenhum componente, rota, store,
catálogo, API, banco ou ambiente foi alterado nesta fatia.

## Fonte e contrato

O contrato primário é `docs/agentes-ia-redesign/design/F0-mapeamento.md:122-172`, com a
subfatia de retomada em `docs/agentes-ia-redesign/design/B3.md:67-106,208-225`. O gate do
redesign é aditivo ao `autonomia_agents_enabled`; a lista conserva o nome
`autonomia_agents_index`, o painel novo tem `performance` como aba padrão e a entrada
`autonomia_agent_panel_legacy` é o caminho compatível explícito durante o staging. E2m
manual ramifica antes de BE-05 e não lê nem cria `build_thread`. A retomada guiada E1–E4
usa o GET nested antes de montar `PanelTune`, preserva o mesmo id no primeiro envio e
trata 401/404/422 com aviso localizado sem apagar a lista.

O convite global continua em `autonomia_invite_connection`, com a permissão e os chamadores
atuais. A conexão de WhatsApp permanece na área central de Canais; estes specs não criam
rota, QR, convite ou atalho alternativo dentro de Agentes.

## Causas observadas antes do produto

1. `autonomia.routes.js:58-76,115-139` só possui o guard do gate antigo e as três rotas
   legadas; não há seleção verificável pelo booleano de redesign, rota compatível nomeada
   nem default `performance` nas props do painel.
2. `AgentPanelPage.vue:1-191` busca o agente em `onMounted`, sem hidratar BE-05 antes de
   montar o painel. Isso permite que um deep link guiado mostre `PanelTune` sem a thread
   real, ou comece por uma nova thread.
3. `PanelTune.vue:209-215` faz `RESET` ao abrir a reconversa. Esse reset apaga a hidratação
   que o GET acabou de fornecer; `:228-245` ainda chama `start` quando não encontra id.
   O segundo caminho é legítimo para criação antiga e deve continuar coberto separadamente.
4. Não existe no código atual uma fronteira que, para falhas 401/404/422 do resume, preserve
   a projeção da lista e mostre uma mensagem localizada. A checagem precisa observar a
   navegação de saída e o aviso, sem fabricar uma thread ou payload de sucesso.

## RED novo

Os três arquivos novos cobrem apenas contratos observáveis:

- `f0-routes-compat.spec.js`: isolamento do gate antigo/novo, preservação do Hub e do
  convite global, props padrão/abas explícitas, rota legada disponível sob os dois estados
  da flag, E2m sem chamada BE-05 e caminhos de deep link/erro sem `start`.
- `pages/AgentPanelPage.f0-resume.spec.js`: editor guiado hidrata a thread nested antes de
  montar o painel; manual E2m e viewer não fazem resume nem escrita; falhas 401/404/422
  deixam o agente/lista intactos e emitem aviso traduzido.
- `components/panel/PanelTune.f0-compat.spec.js`: abrir uma reconversa preserva a thread
  já hidratada; o primeiro envio usa `send` com o id existente; a criação antiga sem id
  continua usando `start` exatamente uma vez.

Os testes não importam páginas futuras, fixtures de produto ou componentes vazios. Os
stubs ficam confinados ao teste de ciclo para não esconder uma rota/import real. A execução
de Vitest, lint, build, banco, rede e navegador fica para o snapshot coordenado pelo root.

## Critério de saída desta fatia

O RED só pode virar GREEN depois que a implementação comprovar: gate aditivo por conta,
rota nomeada e permissões preservadas; hidratação antes da montagem para editor guiado;
ramificação E2m/viewer sem GET ou escrita; tratamento localizado das três recusas; e
compatibilidade do `start` apenas no fluxo antigo sem thread. Esta escrita não declara
nenhum desses pontos implementado, nem autoriza merge, fila, deploy ou produção.

## RED24 — execução real coordenada pelo root

O RED frontend foi executado no snapshot M2 pelo job `m2-5b21fa1517a94a7887c481f452e60242`, ticket
M4 `4321c51e2fe647999eddbf4714d1bf0c`. O resultado está em
`/tmp/chat2you-agentes-frontend-check24.json`, SHA-256
`d2271baed017208243cc26214f1bfec3879f36747be8d3abc66cd652a132776e`: 65 exemplos executados, 47
passaram, 18 falharam e 4 suítes não foram coletadas porque os módulos F0 ainda não existem.

API, store e Message ficaram verdes. No bloco desta ownership, `PanelTune` teve 7 casos: 3 passaram e 4
falharam, nos cenários de histórico/retomada e de falha 401/404/422. A distribuição restante foi: 4
falhas no bloco pai, 5 em rotas e 5 em foco. O resultado confirma o RED e não é aceite de produto, GREEN,
CI ou validação visual. As falhas de BE-05/PanelTune permanecem aguardando a correção coordenada pelo root;
este registro não abre uma nova revisão nem registra causa adicional do B3.

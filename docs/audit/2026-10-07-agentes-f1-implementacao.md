# F1 — implementação da lista “Seus agentes”

Data: 2026-10-07  
Worktree: `docs/agentes-ia-prd`  
Escopo: RED inicial e implementação local da primeira tela real do redesign.

## RED inicial

Antes da implementação, foram escritos specs significativos para a lista, seus
componentes e o composable:

- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/composables/useAgentsList.spec.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentRow.spec.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentsSummaryChips.spec.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentsEmptyHero.spec.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentModelCard.spec.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentsListPage.spec.js`

Os specs carregam os módulos sob teste dentro dos exemplos para que o RED
continue sendo contado pela suíte quando os arquivos ainda não existem. Neste
ponto, a implementação da página e dos componentes ainda estava ausente; o
RED esperado era a falha por módulo ausente, e não uma suíte sem exemplos.
O teste deve ser executado pelo coordenador em snapshot isolado antes de
considerar qualquer resultado GREEN.

## Contratos cobertos

1. O GET usa a API account-scoped com `AbortSignal`, preserva a projeção em
   caso de erro e não trata cancelamento como lista vazia.
2. PATCH envia somente `status` e `enabled` e faz um GET posterior; o cartão
   anterior continua visível quando essa releitura falha.
3. A linha usa `state.code` como autoridade, exibe canais e os quatro números
   externos, omite métricas do ajudante interno e não libera ações de escrita
   para quem só pode ver.
4. Estado desconhecido falha como erro de contrato, sem cair em rascunho.
5. Vazio só aparece após lista carregada sem itens; editor vê três modelos e
   leitor vê apenas orientação.

## Implementação autorizada

A implementação que segue permanece restrita a F1: página, linha, resumo,
vazio, cartões de modelo, composable/API account-scoped e catálogos
`AGENTS.V2.*` em inglês e português. O kit F0, as rotas, o painel, o token de
design e o backend continuam pertencendo aos owners indicados no handoff.

Não houve execução de banco, serviço, produção, merge, push ou deploy neste
registro. A aceitação visual continua pendente das telas reais em quatro
combinações (1440/400 e claro/escuro), depois que a implementação estiver
integrada no ambiente local isolado.

# RED dos contratos F2/F3 — 08/10/2026

Este bloco prepara o TDD da jornada nova de criação, sem implementar componentes
de produto. O escopo é Escolha → Conte → Teste → Ligue; **Pronto** é a tela de
conclusão e não uma quinta etapa da barra.

## Specs adicionadas

- `app/javascript/dashboard/api/specs/autonomiaCreation.spec.js`
  - abertura assíncrona do `build_threads` com `type`, `actuation` e
    `with_knowledge: true`;
  - publicação externa com `inbox_id` e `response_window`;
  - publicação interna sem associação de caixa;
  - `name` e `greeting` não entram no payload de `publish`.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/composables/useAgentCreation.spec.js`
  - início, retomada sem `start`, envio no thread hidratado e publicação do
    agente atual.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.spec.js`
  - props `agentId`/`step`, quatro etapas visíveis e conclusão `ready` fora da
    barra;
  - fixture account-scoped com Vuex/store, rota em memória e i18n, incluindo o
    gate do Teste, alteração de Nome/Primeira mensagem e saída para retomar.

## RED esperado

Os arquivos de produto `useAgentCreation.js` e `AgentCreationPage.vue` ainda
não existem neste snapshot. O cliente `AutonomiaAgentsAPI` também ainda não
expõe `publish`; essa implementação pertence ao bloco coordenado pelo root.
Assim, as falhas esperadas são de contrato ausente, e não podem ser convertidas
em stubs ou payloads fictícios. Nenhum teste, build, serviço ou banco foi
executado neste bloco; o root fará a captura e a execução RED combinadas antes
da implementação.

## Decisões de interface para a implementação

- `AgentCreationPage` recebe `agentId` opcional e `step` em
  `choice|tell|test|live|ready`.
- `useAgentCreation` delega início, retomada e envio ao módulo
  `autonomiaBuildThreads`; retomada usa o `agentId` da conta e não chama
  `start`.
- `publish` recebe somente `inboxId` opcional e `responseWindow`, deixando o
  nome e a primeira mensagem no contrato do Teste/PATCH.
- A publicação não cadastra WhatsApp: o Ligue lista e associa caixas já
  existentes.

## Fixture da página

O spec monta a página com conta habilitada, getters reais do fluxo, uma rota em
memória e os catálogos reais `en/agents.json` e `pt_BR/agents.json`. Os filhos
da jornada são stubs de comportamento apenas para isolar o contrato da página;
o teste ainda exige que a página dispare a retomada account-scoped, bloqueie
Ligue antes de uma resposta válida, invalide o teste ao salvar Nome/Primeira
mensagem e volte para a lista ao sair.

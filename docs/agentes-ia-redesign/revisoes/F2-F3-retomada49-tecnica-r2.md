# Revisão técnica 2 — F2/F3 — retomada 49

**Data:** 2026-10-08  
**Escopo:** revisão das correções solicitadas na R1 técnica, no recorte F2/F3:
limpeza do erro local da etapa Conte; remoção do eco otimista rejeitado e reuso do
`client_message_id` durante retry; proteção contra duplicação de bolha; testes de
mutações reais do store; prova nativa do retry de transporte; e os ajustes ARIA e
de alvo de toque dos materiais. Não reanalisei os 373 arquivos da linha de base,
nem alterei código, harness, banco ou produção.

**Fonte da validação:** snapshot 49, content SHA
`4fa8870ab2c1a9f932ab874f20b6975f28abf4e8ba91f97c7ba66f583345f3d8`, snapshot
`20261008-084433-532a5b7b-4fa8870ab2-12cb4cad`.

## Conferências da R1

### R1-01 — erro local residual

Sem achado residual. `onSend`, `onRetryTell` e `onAttach` limpam `entryError` antes
da nova operação (`AgentCreationPage.vue:188-210`). O `catch` recoloca somente a
mensagem localizada quando a operação atual falha. `buildError` continua
priorizando esse estado local e não expõe o erro bruto de Axios
(`AgentCreationPage.vue:111-116`).

### R1-02 — eco otimista duplicado

Sem achado residual. O store verifica o `pendingTurn` e a bolha local antes do
`APPEND_MESSAGE` (`autonomiaBuildThreads.js:217-238`). Em falha de transporte ou
409, remove o eco local rejeitado, preserva o `pendingTurn` e relança o erro
correspondente (`autonomiaBuildThreads.js:252-275`). O retry reinsere uma única
bolha e reutiliza o mesmo ID; depois de uma aceitação, `pendingTurn` é limpo e uma
nova mensagem idêntica recebe um novo ID.

## Evidência de testes

- O spec do store usa o estado real e as mutações reais para cobrir falha de
  transporte seguida de retry, 409 seguido de retry e repetição legítima após
  aceitação (`buildThreads.spec.js:99-200`). As três situações verificam o número
  de bolhas e o comportamento do ID.
- A jornada Playwright aborta uma vez o primeiro POST de mensagem, usa **Tentar de
  novo**, exige a resposta persistida, zero alertas e exatamente uma ocorrência da
  resposta do usuário no log (`tests/agents/creation.spec.ts:195-231`).
- O log nativo do snapshot registra `45 passed`, `0 failed`, `3 skipped`, além de
  quatro cenários de materiais aprovados pela API real em
  `.codex/preview/check49/native49-verify.log`.
- O JS direcionado registra `109 passed` em `18` arquivos; o lint registra `0
  errors` (57 avisos de catálogo); o check de i18n registra `13` catálogos e
  `20.442` mensagens compiladas, com chaves/parâmetros cobertos. Esses resultados
  são evidências locais do snapshot, não declaração de CI.

## Acessibilidade e materiais

Sem achado residual no ajuste conferido. O contêiner de materiais declara `role=list`
e cada `MaterialCard` recebe `role=listitem`, que cai no `div` raiz do componente
(`BuilderKnowledgePanel.vue:375-389`). Os controles de adicionar link, remover e
reenviar usam altura mínima de 44 px (`min-h-11`, e `min-w-11` no botão de remover)
em `BuilderKnowledgePanel.vue:300-310` e `MaterialCard.vue:164-172,232-240`.

## Conclusão

**Revisão 2 técnica: aprovada, sem achados acionáveis no escopo revisado.** As duas
causas apontadas na R1 têm correção implementada e prova correspondente no estado
real, incluindo o caminho de transporte abortado, o conflito 409 e a repetição
legítima. Este parecer não declara CI, aprovação do Rodrigo, merge, deploy ou
produção.

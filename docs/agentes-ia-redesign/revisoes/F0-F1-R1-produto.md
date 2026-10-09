# Revisão normal R1 — controles D9, adaptadores e locale

**Resultado:** há dois achados de cobertura de contrato que precisam ser fechados antes de considerar a fatia D9 pronta. Não encontrei regressão observável no contrato atual de Campanhas, no helper de locale ou no token `n-navy`.

**Escopo e método:** leitura estática do F0, PRD, catálogo en/pt-BR, controles `StepsBar`/`LabeledSwitch`, adaptadores de Campanhas/Agentes e seus consumidores. O snapshot 30 foi capturado antes desta escrita. Não executei Vitest, build, lint, navegador ou banco; não alterei produto.

## Achados

### F0-F1-R1-01 — média — os adaptadores de etapas não têm prova do contrato pt-BR

**Prova:** `JourneyStepBar` produz os três rótulos de Campanhas e o `aria-label` por i18n em `app/javascript/dashboard/components-next/CampaignJourney/JourneyStepBar.vue:14-37`; `AgentSteps` produz os quatro rótulos da jornada nova e seu `aria-label` em `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentSteps.vue:12-30`. Porém, `app/javascript/dashboard/components-next/stepper/specs/StepsBar.spec.js:4-17,25-92` usa rótulos e `stepAria` fabricados em inglês, e `app/javascript/dashboard/components-next/CampaignJourney/specs/JourneyStepper.spec.js:14-24,27-72` monta somente o catálogo en. Não há `AgentSteps.spec.js` nem caso do adaptador com `pt_BR`.

**Efeito:** uma chave `AGENTS.V2.steps.*` ausente, divergente ou um `stepLabel` errado pode deixar a barra nova com chave crua ou ARIA em inglês para uma pessoa brasileira, enquanto os testes continuam verdes. Isso deixa sem prova o requisito de catálogo en/pt_BR e de `toLocaleTag`/i18n da área (`docs/agentes-ia-redesign/PRD.md:675-676`; `docs/agentes-ia-redesign/design/F0-mapeamento.md:49,54,81`).

**Correção mínima:** adicionar specs dos dois adaptadores, com `createI18n` real em en e `pt_BR`: Campanhas deve ter exatamente 3 itens e Agentes exatamente 4 (`Escolha`, `Conte`, `Teste`, `Ligue`), conferindo o texto visível, `aria-label` e evento `go`. Manter `Pronto` fora da barra. Não é necessário criar um novo mecanismo de i18n.

### F0-F1-R1-02 — média — a integração do interruptor da lista de Agentes está escondida por stub

**Prova:** o comportamento que decide pausar/religar está em `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentSwitch.vue:14-20`: o `toggle` do `LabeledSwitch` é convertido em `!props.checked`. O cartão usa esse valor para E5/E6 em `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentRow.vue:197-204`. Entretanto, `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentRow.spec.js:35-46` substitui `AgentSwitch` por um botão stub e os casos `:66-106` só verificam a existência do stub; não há spec de `AgentSwitch` nem caso real E5/E6 que confira `aria-checked`, `busy/disabled` e o payload de pausa ou religação.

**Efeito:** uma inversão do payload, perda do `role="switch"`/`aria-checked` ou quebra do bloqueio durante a mutação pode passar na suíte da primeira tela. Para uma pessoa usuária, “Pausar” pode religar, “Religar” pode pausar, ou o controle pode aceitar segundo clique enquanto a lista está sendo atualizada. O requisito do kit exige `AgentSwitch` sobre `LabeledSwitch` e alvo/semântica de switch (`docs/agentes-ia-redesign/PRD.md:643-651`), e a primeira tela depende desse controle para a gestão E5/E6 (`docs/agentes-ia-redesign/design/F0-mapeamento.md:180-186`).

**Correção mínima:** manter o spec genérico de `LabeledSwitch` e acrescentar um spec curto de `AgentSwitch` para `checked=true/false`, `aria-checked`, `disabled` e payload `toggle`; no `AgentRow`, montar o componente real em pelo menos um caso E5 e um E6, conferindo o evento `toggleStatus` e o bloqueio quando `busy=true`. Não é necessário alterar a API.

## Conferências sem achado

- O adaptador de Campanhas preserva `AUDIENCE/MESSAGE/REVIEW`, `current`, `reachable`, `aria-current`, `go` e teclado; os specs existentes e o novo `StepsBar` cobrem esses invariantes. `NewCampaignPage.vue:739-743` usa o adaptador real.
- `LabeledSwitch.vue:13-37` mantém `role="switch"`, `aria-checked`, label visível e `min-h-11`; os consumidores migrados preservam os eventos e atributos de teste.
- A cópia de locale foi removida: os imports produtivos usam `dashboard/helper/localeTag`, e `CampaignOverviewPage.vue:14,47-58` usa o helper compartilhado. Não há import produtivo para o caminho antigo.
- O literal `#0D2344` não permanece no dashboard; `theme/colors.js:106-109` expõe `n.navy`, e os stops distintos de gradientes permanecem classificados conforme a decisão de integração (`docs/audit/2026-10-07-agentes-f0-integracao.md:7`). Não abri achado para a página pública de Links/QR, que o F0 classifica como exceção.

## Conclusão

R1 encontrou dois gaps concretos de prova dos controles que podem esconder regressões de i18n e de pausa/religação. O desenho D9 e a implementação comum continuam sem achado adicional nesta lente, mas a checagem limitada seguinte deve confirmar os dois casos após a correção. Esta revisão não aprova F0/F1, telas reais, merge, fila, deploy ou produção.


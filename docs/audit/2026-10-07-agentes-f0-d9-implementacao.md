# F0/D9 — implementação da extração comum

Data: 2026-10-07  
Branch: `docs/agentes-ia-prd`  
Escopo: D9 do `design/F0-mapeamento.md`, sem rotas, kit de Agentes, tokens, painel, catálogo, flags, autenticação ou migração.

## Mudança

- `components-next/stepper/StepsBar.vue` agora concentra a barra genérica: lista ordenada de etapas, etapa atual, maior etapa alcançável, `aria-current="step"`, rótulo acessível, evento `go` e navegação por Arrow/Home/End.
- `CampaignJourney/JourneyStepBar.vue` é o adaptador de Campanhas e entrega exatamente `AUDIENCE`, `MESSAGE` e `REVIEW`. `JourneyStepper.vue` permanece como adaptador de compatibilidade para o import legado; não há uma segunda implementação da barra.
- `components-next/switch/LabeledSwitch.vue` agora concentra o controle com `role="switch"`, `aria-checked`, `toggle`, label visível e alvo `min-h-11`. `JourneySwitch.vue` permanece como adaptador de compatibilidade.
- `AudienceChannelSwitches.vue`, `AudienceCompanies.vue` e `LiveChatJourneyPage.vue` passaram a consumir o componente comum diretamente, preservando props, eventos e atributos de teste.
- `dashboard/helper/localeTag.js` concentra `toLocaleTag` e `formatNumber`. Os quinze consumidores de Campanhas, o spec de locale e `CampaignOverviewPage.vue` foram migrados. O overview mantém o comportamento próprio de `—`, percentuais e datas; apenas a normalização BCP-47 foi compartilhada.
- A cópia antiga `CampaignJourney/localeTag.js` foi removida depois de não restar import produtivo para o caminho antigo.

## Evidência estática

- Os RED existentes cobrem `StepsBar`, `LabeledSwitch` e o helper comum em `components-next/stepper/specs/StepsBar.spec.js`, `components-next/switch/specs/LabeledSwitch.spec.js` e `helper/specs/localeTag.spec.js`.
- `JourneyStepper.spec.js` continua exercitando o contrato de três etapas por meio do adaptador.
- Busca no dashboard não encontrou import produtivo para `CampaignJourney/localeTag`, `JourneySwitch` ou `JourneyStepper`; o único import de `JourneyStepper` restante é o spec de compatibilidade.
- `git diff --check`: passou.
- Testes, build e lint completos ficam para o snapshot coordenado pelo root; não foram executados nesta fatia.

## Limites preservados

`useModalFocus`, `SidePanel`, rotas, kit de Agentes, tokens, i18n, Playwright, flags, banco, produção e qualquer migration não foram alterados.

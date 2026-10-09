# RED frontend F0/D9 — controles comuns e locale

Data: 2026-10-07
Escopo: specs RED para a extração das quatro peças comuns do #993. Nenhum componente ou consumidor foi
alterado.

## Base lida

- `docs/agentes-ia-redesign/design/F0-mapeamento.md`, integralmente, com foco em §§1–3 e nos critérios de
  parada da extração D9;
- `app/javascript/dashboard/components-next/CampaignJourney/JourneyStepper.vue` e
  `specs/JourneyStepper.spec.js`;
- `app/javascript/dashboard/components-next/CampaignJourney/JourneySwitch.vue`;
- `app/javascript/dashboard/components-next/CampaignJourney/localeTag.js` e `specs/localeTag.spec.js`;
- `app/javascript/dashboard/routes/dashboard/campaigns/journey/CampaignOverviewPage.vue`.

Os specs antigos do #993 permanecem intactos. Os destinos comuns ainda não têm implementação; os arquivos
abaixo são somente contratos RED para orientar a extração.

`useModalFocus` é a quarta peça de D9, mas fica deliberadamente fora deste bloco: sua API muda junto com
`SidePanel`/`AudienceSidePanel` e essa ownership foi explicitamente excluída desta preparação.

## Specs adicionados

### `components-next/stepper/specs/StepsBar.spec.js`

Fixa uma API genérica com `steps[{ key, label }]`, `current`, `reachable`, `ariaLabel` e `stepAria`:

- mantém três etapas de Campanhas, `aria-current="step"`, botão inalcançável desabilitado, rótulos ARIA
  localizados e evento `go` com número;
- aceita exatamente quatro etapas de Agentes: `CHOICE`, `TELL`, `TEST`, `LIVE`; `Pronto` é conclusão e não
  entra na barra;
- preserva foco com `ArrowRight`, `ArrowLeft`, `Home` e `End` entre etapas alcançáveis.

### `components-next/switch/specs/LabeledSwitch.spec.js`

Fixa `checked`, `disabled`, `label`, `ariaLabel`, `role="switch"`, `aria-checked`, evento `toggle` e o
  alvo mínimo Tailwind `min-h-11` (44 px).

### `helper/specs/localeTag.spec.js`

Fixa `pt_BR → pt-BR`, outros locales com `_` convertidos, fallback `en` para `undefined`/`null`, contagem
  com `formatNumber` sem passar `pt_BR` inválido ao `Intl` e `null → 0`. Também exige que
  `CampaignOverviewPage.vue` importe o helper compartilhado e não mantenha a cópia local de
  `locale.value.replace('_', '-')`.

## Estado e validação

Este bloco é RED por construção: `StepsBar.vue`, `LabeledSwitch.vue` e `dashboard/helper/localeTag.js`
nos destinos comuns ainda não existem, e `CampaignOverviewPage.vue` ainda contém o formatter local. Não
executei Vitest, build, banco ou navegador. Não alterei os componentes #993, consumidores, SidePanel,
token, rotas, i18n ou qualquer parte de BE-05.

Próxima etapa: executar estes specs para registrar o RED específico e só depois implementar a extração D9
em bloco, mantendo os specs antigos como não-regressão.

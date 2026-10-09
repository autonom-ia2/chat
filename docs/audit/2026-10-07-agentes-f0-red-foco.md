# RED frontend F0/D9 — foco, SidePanel e AudienceSidePanel

Data: 2026-10-07
Escopo: contrato de foco compartilhado da extração D9, sem mover nem implementar fontes de produto.

## Base lida

- `docs/agentes-ia-redesign/design/F0-mapeamento.md`, integralmente, com foco em §§3 e 10;
- `app/javascript/dashboard/components-next/CampaignJourney/useModalFocus.js`;
- `app/javascript/dashboard/components-next/side-panel/SidePanel.vue`;
- `app/javascript/dashboard/components-next/CampaignJourney/AudienceSidePanel.vue`;
- referências reais de consumidores do `SidePanel` e specs existentes de drawers.

## Contratos RED adicionados

### `composables/specs/useModalFocus.spec.js`

Exige o destino comum `dashboard/composables/useModalFocus` com API `{ container }` e retorno
`activate/deactivate` mais `focusableIn`. O composable não move foco ao ativar e só prende `Tab`/`Shift+Tab`
enquanto ativo; depois de `deactivate`, deixa de interceptar as teclas. Escape, scroll, gatilho e foco inicial
ficam fora do composable.

### `components-next/side-panel/specs/SidePanel.spec.js`

Monta o SidePanel real e cobre o lifecycle observável:

- foco em `data-autofocus` após `afterEnter` e scroll lock no corpo;
- Tab/Shift+Tab presos no painel;
- gatilho restaurado somente depois de `afterLeave`, com evento público `close` único;
- Escape fecha uma vez e o scroll é liberado depois de `afterLeave`.

Os primeiros casos expõem as regressões concretas da implementação atual: ela foca a raiz em vez de
`data-autofocus`, não tem trap no SidePanel e devolve o foco ao gatilho dentro de `close`, antes de
`afterLeave`.

### `CampaignJourney/specs/AudienceSidePanel.spec.js`

Monta o consumidor e espera a adaptação para o SidePanel compartilhado: `audienceId`/`canManage`, largura
legada de `37rem`, abertura via ref, foco inicial do botão de fechar com alvo de 44 px e emissão pública de `close`
somente depois de `afterLeave`. Também preserva os eventos `use` e `delete` com os payloads existentes.

## Estado e validação

Este bloco é RED por construção: o composable comum ainda não existe; `SidePanel` atual não instala o trap,
não honra `data-autofocus` e restaura o gatilho cedo; `AudienceSidePanel` ainda monta backdrop/aside próprio
e usa a API antiga do composable. Não executei Vitest, build, banco ou navegador. Não alterei fontes,
consumidores existentes, `Message.vue`, specs de B1, API/store BE-05 ou backend.

Próxima etapa: executar os specs para registrar o RED específico e só então migrar os quatro owners em bloco,
mantendo SidePanel como único dono de abertura, Escape, scroll, foco inicial, restauração e fechamento.

## Ajuste do RED de SidePanel antes da implementação

Na revisão da spec, o mount ainda deixava o `Transition` global como stub padrão. Isso pode impedir que
`afterEnter`/`afterLeave` sejam observados no lifecycle real. Além disso, o próprio `SidePanel` renderiza
um botão Fechar focável no cabeçalho antes do conteúdo; esperar que `Tab` de `last` caia diretamente em
`first` ignora essa ordem real. A correção é desabilitar apenas o stub de `Transition` e testar o ciclo
`last → fechar` e `fechar ← last`, sem alterar o produto para caber na expectativa do teste.

## Ajuste do RED de Audience antes da implementação

Na checagem do snapshot 22, a primeira spec do consumidor carregava uma exigência que não vinha do
contrato: `width="xl"` do `SidePanel` comum representa `max-w-xl` (36 rem), enquanto o consumidor
legado preserva explicitamente `sm:w-[37rem]` em `AudienceSidePanel.vue:115`. A correção é testar a
largura real preservada do painel renderizado, sem escolher o token `xl` apenas por conveniência.

Também foi identificado que o stub de `SidePanel` escondia justamente o lifecycle que F0 precisa provar.
O teste do consumidor deve montar o `SidePanel` real, mockar somente a API de públicos e observar o
`close` público depois do `afterLeave`; foco, transição, Escape e restauração continuam sendo contrato
do SidePanel e da spec própria. Essa causa é registrada antes da alteração dos testes.

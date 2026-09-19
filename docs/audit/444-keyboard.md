# Issue 444 — P2 keyboard-accessible dropdowns

Data: 2026-09-19. Escopo: somente finding 1 de `tmp/email444/adversarial-review.md`.

## Entrega ao parent

Arquivos escritos:

- `app/javascript/dashboard/components-next/filter/inputs/FilterSelect.vue`
- `app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js`
- Este registro.

`keyboardNavigation` é Boolean e permanece `false` por padrão. O parent deve ativá-lo nas três declarações de `FilterSelect`: uma em `EmailStatusFilter.vue` e duas em `CrmCampaignManagementPage.vue`. Esses arquivos não foram alterados nesta tarefa.

### Wiring exato

No `FilterSelect` de `EmailStatusFilter.vue`, acrescentar `keyboard-navigation` e `:aria-label="fieldLabel"`, reutilizando o nome do grupo. No slot, receber **`keyboardAttrs`** e aplicar **`v-bind="keyboardAttrs"` ao Button real**. Manter `@click="toggle"`:

```vue
<FilterSelect
  :model-value="modelValue"
  :options="options"
  keyboard-navigation
  :aria-label="fieldLabel"
  hide-icon
  variant="faded"
  @update:model-value="update"
>
  <template #trigger="{ toggle, keyboardAttrs }">
    <Button
      v-bind="keyboardAttrs"
      type="button"
      md
      slate
      faded
      trailing-icon
      icon="i-lucide-chevron-down"
      class="!w-full !h-10 !justify-between"
      :label="selectedOption?.label"
      @click="toggle"
    />
  </template>
</FilterSelect>
```

O slot também fornece **`expanded`**, Boolean com o estado atual. `keyboardAttrs` já contém `aria-expanded`, `aria-haspopup="listbox"`, `aria-controls` enquanto aberto, nome acessível e `onKeydown`. Não acrescentar outro handler de Enter/Space/setas nem chamar `toggle` duas vezes. A função de slot continua aceitando `toggle()`; `@click="toggle"` encaminha o evento e identifica precisamente o botão que deve recuperar o foco.

Nas duas declarações sem slot de `CrmCampaignManagementPage.vue`, manter props/eventos existentes e acrescentar:

| Uso                                 | Props adicionais                                                          |
| ----------------------------------- | ------------------------------------------------------------------------- |
| `v-model="selectedCampaignId"`      | `keyboard-navigation :aria-label="t('CAMPAIGN_MANAGEMENT.FILTER.LABEL')"` |
| `v-model="trackedLinkForm.inboxId"` | `keyboard-navigation :aria-label="t('CRM_KANBAN.TRACKED_LINKS.INBOX')"`   |

`aria-labelledby` também é encaminhado ao trigger padrão e à lista. O nome deve ser passado ao próprio `FilterSelect`, não apenas ao grupo ancestral, pois o menu pode estar teletransportado para `body`.

## Decisões e comportamento

- APIs reais inspecionadas: `Button`, `DropdownContainer`, `DropdownBody`, `DropdownItem`, `DropdownSection`, `DropdownFloating`, provider de teleport, `useKeyboardNavigableList` e `useKeyboardEvents`. Não foi necessária alteração no contexto/container compartilhado.
- `DropdownItem :click` produz os botões reais, com `type="button"`, `role="option"`, `aria-selected` e indicação de foco. A seção recebe `role="listbox"`. Cabeçalhos desabilitados continuam não selecionáveis.
- Handlers locais foram preferidos ao composable existente, que registra atalhos em `document`. Nenhum novo listener global, polling ou MutationObserver; consultas DOM são pontuais e restritas ao próprio menu, para foco e navegação.
- Enter/Space/setas abrem e focam a opção selecionada ou a primeira disponível. Enter/Space ativam no **keydown**, com `preventDefault` e `stopPropagation` para evitar ativação nativa duplicada. Seleção fecha pelo fluxo existente de `DropdownItem` e devolve o foco ao trigger.
- Setas percorrem as opções; Home/End vão à primeira/última. Escape fecha e restaura o foco. Tab/Shift+Tab fecham, devolvem a origem de foco ao trigger e **não cancelam a ação nativa de Tab**, permitindo sair mesmo com teleport.
- A busca continua aparecendo acima de `DROPDOWN_SEARCH_THRESHOLD` (atualmente 8). Ao abrir, o opt-in prioriza a opção selecionada; Home seguido de ArrowUp alcança a busca. Na busca, ArrowDown/ArrowUp alcançam primeiro/último resultado; Home/End/Space continuam edição nativa. Enter não submete um formulário ancestral. Consulta em branco restaura a lista e cabeçalhos; sem resultados o foco continua no input. Lista vazia sem busca recebe foco para permitir Escape/Tab.
- Sem opt-in: preservados os itens em `div`, clique anterior, cabeçalhos, limiar/autofoco da busca, slot/toggle, provider de teleport e cálculo existente de posição.

## Validação executada

Nenhum Git, DB, Rails, produção, rede, instalação, browser, build ou suíte completa executado. Testes Node limitados ao novo spec, TZ UTC, máximo de dois workers. Nenhum mock/stub de menu ou alteração de dependências/configuração.

Formatação executada nos dois arquivos de código:

```sh
node_modules/.bin/prettier --write app/javascript/dashboard/components-next/filter/inputs/FilterSelect.vue app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js
node_modules/.bin/prettier --write docs/audit/444-keyboard.md
node_modules/.bin/prettier --check app/javascript/dashboard/components-next/filter/inputs/FilterSelect.vue app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js docs/audit/444-keyboard.md
```

Resultado: exit 0; os três arquivos passaram no check de formatação.

Lint final:

```sh
node_modules/.bin/eslint app/javascript/dashboard/components-next/filter/inputs/FilterSelect.vue app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js
```

Resultado: exit 0; **0 erros, 7 warnings**: quatro resoluções de chaves `COMBOBOX` pelo lint i18n e três textos estáticos do fixture. Erros iniciais de ordem de declaração e nome do componente no fixture foram corrigidos.

O comando comum foi executado inicialmente:

```sh
TZ=UTC node_modules/.bin/vitest run app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js --maxWorkers=2 --minWorkers=1 --no-cache --no-coverage
```

Resultado inicial: 14 falhas/16 testes. Duas execuções diagnósticas do mesmo comando com `-t 'retains non-button'` confirmaram que `isOpen` mudava para true sem renderizar o menu, inclusive no comportamento padrão. Também foi corrigido uso indevido de `setProps` em componente filho no fixture.

Evidência local: `node_modules/vue` resolve Vue 3.5.12; os links de Vue dos pacotes `@vueuse/core`, `@vueuse/shared` e `@vueuse/components` resolvem Vue 3.5.13. Para executar as dependências reais sob o alias Vue do projeto, sem editar configuração, foi usado o runner existente com override em memória:

```sh
TZ=UTC node --input-type=module <<'JS'
import { startVitest } from 'vitest/node';
const context = await startVitest('test', ['app/javascript/dashboard/components-next/filter/inputs/specs/FilterSelect.emailCampaignKeyboard.spec.js'], { run: true, maxWorkers: 2, minWorkers: 1, cache: false, coverage: { enabled: false } }, { test: { server: { deps: { inline: [/@vueuse\//, /vuex/] } } } });
await context.close();
JS
```

Resultado final: **20/20 testes passaram**, 1 arquivo, exit 0. Cobertura: trigger padrão/customizado, sem teleport e com provider real de teleport, Enter/Space/setas/Home/End/Escape, seleção única, foco/ARIA, Tab/Shift+Tab não cancelados, busca longa/whitespace/sem resultados, lista vazia e comportamento padrão. Houve uma execução intermediária com 18/19 passando por escopo incorreto da variável `teleport` no novo caso de lista vazia; corrigido antes da execução final. O runner emitiu aviso de Browserslist desatualizado; nenhuma atualização executada.

## Limites e próximos gates do parent

jsdom não sintetiza cliques nativos por Enter/Space nem faz navegação nativa por Tab. Enter/Space testam handlers explícitos de produção; Tab testa fechamento, foco de origem e `defaultPrevented === false`, com destino subsequente representado manualmente no fixture. Isso **não comprova** ordem nativa de Tab no browser. Os testes também não comprovam layout, recorte, scroll visual, leitor de tela ou posição real do menu.

Parent: aplicar wiring acima, executar jornada real de teclado com busca/lista longa e teleport, conferir nome/seleção no leitor de tela e rodar seus gates de regressão. Esta entrega não conclui a PR, merge ou deploy.

## Integração do parent

Opt-in ativado apenas nos seletores usados pela gestão de campanhas. O spec tem nome `FilterSelect.emailCampaignKeyboard.spec.js` para integrar o seletor existente do CI de e-mail. O ajuste de dependências inline foi colocado no `vitest.config.ts`: os testes reais de VueUse/Vuex usam o mesmo alias Vue da aplicação, sem mockar o menu, instalar dependências ou alterar o runtime de produção. O comando normal de Vitest e toda a suíte serão repetidos com esse ajuste, sem depender do runner temporário.


## Fechamento integrado — 19/09/2026

As instruções de handoff e resultados parciais anteriores descrevem a implementação; o status atual consolidado está em [444-email-campaign-uiux.md](444-email-campaign-uiux.md). Teclado permanece opt-in, desativado por padrão no componente compartilhado. Foram preservados trigger, foco, nome acessível, escolha, busca e fechamento dos menus, incluindo testes com teleport.

Depois da revisão adversarial, o seletor de caixa mantém seu botão/ref padrão; a altura é ajustada exclusivamente por utilitários Tailwind locais. Não ficou o slot customizado intermediário que perdia a referência de posicionamento. O fechamento independente desse delta recebeu PASS.

Gates integrados finais locais: 434 testes focados/teclado sem falhas; navegador com 212 verificações aprovadas, 148 capturas e servidor encerrado. Os controles vizinhos do formulário mediram 40/40 px. O harness agora registra FloatingVue como na aplicação e testa a ajuda real por hover/conteúdo/ocultação, sem warnings de diretiva ausente. O CI da publicação final continua obrigatório; este registro não autoriza merge/deploy.

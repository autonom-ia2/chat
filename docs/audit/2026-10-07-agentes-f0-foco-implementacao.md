# Implementação F0/D9 — foco, SidePanel e AudienceSidePanel

Data: 2026-10-07
Escopo: correção única dos owners de foco compartilhado, após o RED registrado em
`docs/audit/2026-10-07-agentes-f0-red-foco.md`.

## Causas confirmadas antes da alteração

- O composable ainda estava preso a `CampaignJourney/useModalFocus.js`, misturando
  trap, Escape, foco inicial, gatilho e restauração. A API RED de D9 exige que ele
  apenas registre o trap de `Tab`/`Shift+Tab` quando ativado.
- `SidePanel.vue` focava sempre a raiz, não instalava o trap e restaurava o gatilho
  dentro de `close`, antes do `afterLeave`. Isso torna a transição observável e a
  restauração incompatíveis com o contrato de foco.
- `AudienceSidePanel.vue` mantinha backdrop, aside e lifecycle próprios. Isso
  duplicava o dono do Escape/foco/scroll e emitia `close` antes do painel terminar
  a saída, permitindo que o pai com `v-if` desmontasse a árvore antes da restauração.
- O consumidor legado preserva explicitamente a largura `37rem` e o alvo de toque
  de 44 px do botão fechar; a migração precisa transportá-los para o SidePanel
  compartilhado sem reduzir o contrato visual.

## Bloco de correção

1. Extrair a implementação única para `dashboard/composables/useModalFocus.js`,
   sem ponte para a API antiga.
2. Fazer o SidePanel possuir abertura, foco após `afterEnter`, trap, Escape,
   scroll lock e restauração única após `afterLeave`/desmontagem.
3. Adaptar AudienceSidePanel ao SidePanel real, preservando props, eventos de
   negócio, largura, alvo de toque e emit público de `close` somente depois da
   restauração.

## Validação reservada

Os specs RED existentes serão executados pelo coordenador em snapshot próprio.
Este bloco não executa testes pesados, build, banco, produção ou commit.

## Resultado do bloco

- `dashboard/composables/useModalFocus.js` agora é a única implementação e
  intercepta somente `Tab`/`Shift+Tab` entre `activate` e `deactivate`;
  `CampaignJourney/useModalFocus.js` foi removido após o grep de consumidores.
- `SidePanel.vue` escolhe `data-autofocus` após `afterEnter`, ativa/desativa o
  trap, trata Escape e clique fora, e restaura o gatilho uma única vez após
  `afterLeave` ou durante o unmount. O close slot permite ao adaptador preservar
  o botão de fechar e seus atributos sem duplicar listener.
- `AudienceSidePanel.vue` usa o SidePanel real, abre pela ref, preserva a
  largura `37rem`, o alvo de 44 px, os eventos `use`/`delete` e os seletores
  legados de teste. Seu `close` público só é emitido no `afterLeave`, depois da
  restauração feita pelo SidePanel.
- `git diff --check` passou nos arquivos deste bloco. Vitest, build, banco,
  navegador e produção permanecem pendentes para a execução coordenada.

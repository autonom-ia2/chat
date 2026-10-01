# Correção do menu de perfil em português

## Decisão

O `SidebarProfileMenu.vue` já usa as chaves i18n corretas. O idioma `pt` tinha os valores de `SIDEBAR_ITEMS` em inglês, enquanto `pt_BR` já trazia traduções. A correção ficou limitada ao catálogo `pt` e à dica de auto-offline do mesmo menu.

## Mudança

- Tradução dos rótulos de conta, suporte, perfil, atalhos, aparência, central de ajuda, console de Super Admin, changelog e encerramento de sessão.
- Inclusão de `SIDEBAR_ITEMS.INVITE_CONNECTION` no catálogo `pt` para evitar depender do fallback ao exibir o item de conexão.
- Tradução de `SIDEBAR.SET_AUTO_OFFLINE.INFO_SHORT`.

## Validação

- `ruby -rjson` validou os três catálogos (`en`, `pt` e `pt_BR`) e confirmou as 12 chaves do menu em `pt` diferentes dos valores em inglês.
- `jq empty app/javascript/dashboard/i18n/locale/pt/settings.json` passou.
- `git diff --check` passou.
- A suíte de locale/sidebar foi executada pelo worktree de integração do frontend; a execução local neste worktree ficou impedida pelo runtime disponível exigir pnpm 10 e pela configuração compartilhada apontar para `fake-indexeddb` ausente neste checkout.

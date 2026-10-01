# Correção de menus e configurações em português

## Decisão

O `SidebarProfileMenu.vue` já usa as chaves i18n corretas. O idioma `pt` tinha valores de `SIDEBAR_ITEMS`, configurações do perfil e MFA em inglês, enquanto `pt_BR` já trazia traduções para a maior parte desses fluxos. A causa era o catálogo, não o componente nem o carregador de locale. A correção ficou limitada aos catálogos de menus, configurações do perfil e MFA.

## Mudança

- Tradução dos rótulos de conta, suporte, perfil, atalhos, aparência, central de ajuda, console de Super Admin, changelog e encerramento de sessão.
- Tradução dos itens de sidebar encontrados no escopo: empresas, Chat ao vivo, atribuição de agentes, reconexão, artigos, ordenação, segurança, fluxo de conversa, notificações e dados. O nome do produto Captain e seus itens próprios foram preservados.
- Inclusão de `SIDEBAR_ITEMS.INVITE_CONNECTION` no catálogo `pt` para evitar depender do fallback ao exibir o item de conexão.
- Tradução de `SIDEBAR.SET_AUTO_OFFLINE.INFO_SHORT`.
- Tradução das seções de interface, tamanho de fonte, idioma, segurança, sessões, token de acesso, assinatura e alertas de áudio nas configurações de perfil em `pt`.
- Tradução do catálogo `pt/mfa.json`, preservando chaves, placeholders, códigos e nomes de produtos.
- Naturalização de capitalização e de `Status da conexão` em `pt_BR/settings.json`.

O escopo não inclui a revisão global de todos os catálogos da aplicação nem `pt/crm.json`/campanhas, que pertencem ao trabalho de campanha. Ainda há lacunas fora desta revisão, especialmente em inbox, integrações e conversas.

## Validação

- `ruby -rjson` validou os catálogos alterados, preservou as chaves de cada arquivo e confirmou que os placeholders de `pt/mfa.json` continuam alinhados ao catálogo em inglês.
- `jq empty` passou para os três catálogos alterados.
- `git diff --check` passou.
- A suíte direcionada final (`components-next/sidebar/specs` e `i18n/specs/localeLoader.spec.js`) passou neste worktree: 4 arquivos e 25 testes. Houve apenas avisos já existentes do Vue/intlify e do Browserslist; nenhuma dependência ou lockfile foi alterada.
- A tradução do MFA foi validada como catálogo; não foi feita autenticação funcional nem teste em produção.

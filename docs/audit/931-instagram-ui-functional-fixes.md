# #931 — ajustes funcionais de UI do Instagram

Base local: 149c6718f2; branch fix/931-instagram-audit-blockers. Implementação no escopo UI em worktree compartilhada; alterações dos demais responsáveis preservadas. Referências: tmp/instagram-931/brief.md e uiux.md. Nenhuma validação de produção ou integração real.

## Decisões e reprodução antes/depois

- Callback de limite: antes, LimitExceeded/code402 mostrava erro genérico, inclusive no assistido. Agora, code402 ou os tipos estáticos LimitExceeded/CustomExceptions::Inbox::LimitExceeded mostram ERROR_INBOX_LIMIT em en/pt_BR, orientando administrador a liberar capacidade ou ajustar plano. Descrição recebida não é exibida. Demais callbacks assistidos mantêm a orientação OAUTH_ERROR.
- Indisponibilidade: antes, ajuda orientava apenas preparar convite, sem recuperar a disponibilidade. Agora orienta restabelecer a integração (sessão/configuração) e retornar após confirmação. Sem abrir OAuth como escape.
- proxy_unavailable: antes caía em erro genérico de cada operação. Agora usa UNAVAILABLE com orientação operacional para suporte, sem detalhes de infraestrutura. Reconciliação de convite e regras de status existentes mantidas.
- Restrição Meta: antes, busca/status eram oferecidos e enviados apesar do gate backend. Agora busca, seleção e status também verificam disabled; convite/OAuth já verificavam. Os botões correspondentes concordam com os guards e preservam o aviso. Configuração continua permitida, conforme a exceção do controller backend.
- Falha OAuth legado: antes deixava loading preso. Agora alerta traduzido e finally liberam o botão para nova tentativa; guard impede duplicação enquanto ocupado.

Classes de layout, contraste e dimensões de toque preservadas. Sem novo design, assets, payload de autorização ou mudança na reautorização. Prop opcional oauthErrorMessage é interna à UI e recebe apenas tradução estática de limite; oauthError boolean continua compatível.

## Arquivos UI alterados

- app/javascript/dashboard/composables/useInstagramTester.js
- app/javascript/dashboard/composables/specs/useInstagramTester.spec.js (novo)
- app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Instagram.vue
- app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/TesterOnboarding.vue
- app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/TesterOnboarding.spec.js
- app/javascript/dashboard/i18n/locale/en/inboxMgmt.json
- app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json

## Validação efetivamente executada

`node tmp/instagram-931/ui-local-check.mjs`: 17 verificações sintéticas de lógica passaram, zero falhas; sintaxe de sete arquivos aprovada. Usa código atual com substitutos mínimos de reatividade e efeitos locais. Verifica guards, mapeamento de proxy/limite, loading/retry legado, descarte de OAuth tardio e paridade das chaves en/pt_BR. Não equivale a Vue/DOM, Vitest ou compilação Vue/i18n.

`git diff --check -- <sete arquivos UI>`: sem erros de whitespace.

Vitest, ESLint e `pnpm i18n:fork:check` completos não executados: node_modules ausente e instalação proibida pelo brief. Specs existentes preservados e ampliados com estados absent/pending/accepted, restrição desde mount, falhas, callbacks en/pt_BR, troca de conta e respostas/falhas tardias após disposal. Specs de reautorização/API preservados para a execução conjunta.

## Próximo bloco isolado do coordenador/QA

Executar Vitest dos arquivos TesterOnboarding.spec.js, useInstagramTester.spec.js, instagramClient.spec.js e Reauthorize.spec.js; ESLint dos arquivos UI JS/Vue alterados; pnpm i18n:fork:check. Revisar render real isolado nos estados de erro/restrição, incluindo en/pt_BR e claro/escuro. Sem presumir contraste medido a partir de classes preservadas.

QA deve preparar seleção/status antes de ativar disabled quando examinar CTA selecionado; não simular busca/status bem-sucedidos já sob restrição. Handoff detalhado: tmp/instagram-931/ui-progress.md. Nenhum arquivo tests/qa foi alterado pelo responsável UI.

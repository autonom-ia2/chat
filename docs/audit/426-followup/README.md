# Issue #426 — Follow-up com IA nos dois modos e dias permitidos

Implementação isolada em `codex/426-ai-reminders-weekdays`, a partir de `5742de5fc` (origin/main). Sem merge, deploy, leitura de secrets, alteração de cliente ou acesso ao runtime AWS.

## Comportamento entregue

- `auto_send` preserva a decisão da IA e o caminho de envio existente, incluindo escolha de template e validação da janela oficial.
- `ai_reminder` executa a IA, confere a citação da conversa e só então transforma o toque em lembrete interno. Motivo e sugestão ficam na descrição, exibida no popup. Não instancia o remetente nem consulta templates nesse modo.
- Decisões positivas e negativas ficam nos metadados do toque; o histórico do card distingue `reminded` de `sent`.
- Dias e horários são aplicados no planner, na execução (antes e depois da chamada da IA), nas tentativas e no adiamento por limite de marketing.
- Novos funis começam de segunda a sexta. Funis antigos sem `allowed_days` mantêm os sete dias; não há backfill silencioso.
- Modo é consultado na execução: um toque pendente acompanha a edição do funil. Lembretes já emitidos não são convertidos em mensagens.
- A cadência preserva a âncora vigente em main: última mensagem real (cliente/equipe/bot), excluindo o próprio follow-up. Essa correção é posterior à cópia local usada no primeiro diagnóstico.
- Se vários toques ficaram vencidos, o seguinte mantém ao menos o intervalo configurado entre eles a partir da execução, evitando disparos juntos.
- A UI mantém as instruções nos dois modos, impede remover o último dia e valida horas e intervalos. Falha ao salvar mantém o drawer aberto.

## Validação

Banco PostgreSQL exclusivo na porta 55426 e Redis exclusivo na 56426, com dados sintéticos. Dependências locais instaladas na worktree; pgvector 0.8.1 instalado no PostgreSQL 17 local para carregar o schema. Nenhum serviço compartilhado foi reiniciado.

Comandos, após inicializar rbenv e definir o banco local exclusivo:

```sh
bundle exec rspec spec/services/crm/follow_ups spec/services/crm/ai/follow_up_composer_spec.rb spec/requests/api/v1/accounts/crm/ai_settings_spec.rb
node node_modules/vitest/vitest.mjs run app/javascript/dashboard/routes/dashboard/crm/components/CrmAiSettingsPanel.spec.js app/javascript/dashboard/routes/dashboard/crm/components/CrmPipelineDrawer.spec.js
bundle exec rubocop <arquivos Ruby alterados e novos>
node node_modules/eslint/bin/eslint.js <arquivos Vue/JS alterados e novos>
git diff --check
```

- RSpec: 124 casos, zero falhas, 3 pendentes preexistentes em `messaging_window_spec.rb`. Incluído novo caso ativo comprovando que uma janela oficial expirada sem template não chega ao remetente.
- Vitest: 9 casos aprovados, incluindo propagação da falha de persistência ao drawer.
- RuboCop: 14 arquivos, zero infrações.
- ESLint: zero erros; avisos da configuração de descoberta de chaves CRM de i18n existentes no projeto.
- Browser QA: componente Vue real, Tailwind e cores do projeto, API local de fixture para isolar a interação. A API Rails foi testada separadamente pelos request specs. Troca de modos, persistência ao recarregar, instruções preservadas, alinhamento de horário/dias no desktop e ausência de overflow em 390 px. Não representa um E2E autenticado na AWS.
- Popup real inspecionado com fixture sintética de motivo/sugestão. Não houve envio de e-mail, WhatsApp, push ou chamada paga de IA. Qualidade do julgamento do modelo em produção não foi medida.

Capturas: [modo lembrete](ui-desktop-reminder.png), [modo envio](ui-desktop-send.png), [mobile](ui-mobile-reminder.png), [popup](ui-reminder-popup.png). Resultado do navegador: [JSON](ui-results.json).

## Revisão local

Revisados dispatch, seleção de modo, gate da IA, citação verificável, cancelamento por resposta/opt-out, avanço da cadência, alteração de modo em pendência, dias/horários, janela oficial, duplicidade de notificação e apresentação do motivo. Correções durante a revisão: bloquear fechamento do drawer em erro; revalidar horário após IA lenta; respeitar redução do limite de toques. Nenhum override correspondente do runner/planner/composer foi encontrado em enterprise; policies existentes permanecem intactas.

## Limitações para revisão

As regras do projeto restringem traduções a inglês. As novas chaves estão apenas em `locale/en/crm.json`; pt_BR usa fallback em inglês, portanto não reproduz integralmente os textos em português do mockup. Não foi alterada a política de tradução sem decisão do responsável.

A prévia usa fixture de API; a aceitação final no drawer completo e com login no ambiente alvo permanece para a etapa de publicação autorizada. Os testes não avaliam o modelo real e não substituem uma amostra operacional após ativação.

## Publicação e rollback — preparados, não executados

1. Revisar a PR, resolver a decisão de tradução, confirmar CI e identificar o ambiente AWS correto antes de pedir aprovação de merge/deploy.
2. Após aprovação, publicar via workflow manual existente, registrar imagem anterior e validar primeiro um funil controlado. Sem migração de schema.
3. Não fazer rollback cego para código antigo com cadências novas pendentes: o código antigo não respeita `allowed_days` e não passa lembretes pelo novo gate.
4. Em rollback autorizado, interromper o processamento programado durante a transição; inventariar e cancelar/reagendar os toques pendentes afetados antes de restaurar a imagem anterior. Preservar metadados e lembretes já emitidos para auditoria. Confirmar os modos e flags antes de retomar o processamento. Não basta desligar apenas a IA no código antigo, pois lembretes internos seguem outro ramo.

## Achado do CI e correção

O primeiro CI completo identificou duas expectativas antigas em `meta_sync_metadata_spec.rb`: a criação do funil agora inclui os dias úteis, mas os testes esperavam que `metadata.ai` tivesse somente `tone`. A verificação passou a comparar uma cópia dos metadados persistidos antes do PATCH com os metadados depois dele, preservando a garantia de não sobrescrever configurações irmãs. A suíte desse arquivo foi reexecutada localmente: 5 exemplos, zero falhas. O teste separado de criação continua exigindo explicitamente segunda a sexta em novos funis.

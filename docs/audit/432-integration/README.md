# Publicação conjunta — issue #432 / PR #433

## Escopo e origem

Integração isolada autorizada por Rodrigo em 2026-09-14, sem merge na main e sem deploy.

- Base: `5742de5fcda319c97c21b0fdf7d79b2dd793090d`.
- PR #427: `5ed888bc2409d95a36bba2c93ca49f735694522d` (follow-up IA e dias permitidos).
- PR #431: `8bdb366927d902fa00c12dec074a45cfaf2ffc66` (importação assíncrona).
- Integração de código: `e76e861c4`, dois merges locais sem conflitos. Branches originais preservadas.
- Nenhuma modificação adicional em código de produto ou workflows durante a integração.

## Evidências locais

Banco PostgreSQL e Redis exclusivos, RAILS_ENV=test; contatos example.test; ActiveJob em adapter test. Nenhuma mensagem, e-mail ou chamada paga de IA realizada.

- Schema combinado carregado; migration 20260914190000 revertida e reaplicada com sucesso em banco descartável vazio.
- RSpec: 142 exemplos, zero falhas, três quarentenas preexistentes (auto_send_validator, message_sender, messaging_window).
- Vitest: 18 testes aprovados, incluindo configurações/drawer do funil, status/polling/store/dialog de importação.
- CSV: 20.004 linhas, contagens exatas de importados, inválidos, duplicados e suprimidos.
- XLSX: 20.000 contatos sintéticos via Rails API, HTTP 202 antes de inserir; processamento separado; leitura durável após conclusão.
- Retry sem duplicação; falha tardia com rollback atômico; exclusão mútua; recuperação de trabalho interrompido; retenção; isolamento entre contas; bloqueio de envio/agendamento durante importação.
- Feature desativada impede worker/manutenção; manutenção libera lock antes de despachar worker.

Comandos e resultados resumidos: `validation.txt`. Scripts de reprodução permanecem no ambiente local .codex, provenientes da validação #430, com guard de banco ajustado para chat2you_432_test.

A primeira tentativa Vitest não coletou testes por restrição de acesso do Vite ao node_modules compartilhado; allowlist local corrigida. A primeira execução do script de importação estava com CRM_KANBAN_ENABLED ausente e corretamente não processou; repetição com ambas as flags sintéticas passou. Nenhuma dessas correções alterou código do produto. O dump gerado pela migration foi descartado por conter apenas normalização preexistente do schema.

## QA visual e i18n

Playwright/Chromium sobre componentes Vue reais e Tailwind do projeto, em harness local com API de configuração simulada; API Rails validada separadamente. Isso não equivale a QA autenticado em AWS.

- Follow-up: troca de modo, instruções preservadas, salvar/reabrir, dias persistidos, horas/dias alinhados no desktop, largura 390px sem overflow, pt_BR.
- Importação: estados queued/processing/completed/failed do componente real, desktop e 390px sem overflow, sem erros JavaScript.
- As mensagens novas da importação usam fallback inglês em pt_BR, conforme escopo en-only da PR #431. Não foi adicionada tradução nesta integração.
- Screenshots e ui-results.json nesta pasta. O layout do harness de importação é apenas suporte para inspecionar o componente de status, não a página completa autenticada.

## Publicação e pré-requisitos

Um merge desta PR na main dispara DOIS workflows existentes: Hub2You e Autonom.ia. É uma publicação conjunta por destino; não há promessa de uma única execução AWS total.

Inspeção estática dos workflows atuais confirmou:

1. Green executa db:chatwoot_prepare antes de subir o web.
2. Green recebe healthcheck ainda sem tráfego público.
3. Sidekiq blue para e Sidekiq green inicia antes da mudança do listener para green.
4. Configuração de filas inclui low, scheduled_jobs, housekeeping e active_storage_purge.

Antes da publicação, confirmar nos dois destinos o armazenamento ActiveStorage persistente e compartilhado entre web/worker/instâncias, e as filas efetivamente consumidas. ActiveStorage::PurgeJob usa default nesta configuração, embora active_storage_purge também esteja listada. A existência de config/storage.yml não comprova configuração runtime. Nenhum acesso a secrets, SSM, AWS ou banco de produção foi feito nesta etapa.

Importações usam a fila low, compartilhada com outros trabalhos; backlog pode atrasar filas de menor prioridade. Não foi realizado teste de saturação ou garantido SLA de execução. A recuperação de importação é periódica, não instantânea.

## Rollback combinado

Exige aprovação explícita. Antes de retornar código antigo:

- Suspender admissão de novos trabalhos afetados e inventariar importações/follow-ups pendentes.
- Drenar ou tratar importações queued/processing antes de workers antigos, que não conhecem os novos jobs.
- Cancelar/replanejar com decisão operacional os follow-ups novos dependentes de ai_reminder/dias permitidos; código antigo não preserva essas regras.
- Manter schema aditivo, arquivos e resultados. Não executar migration down em produção como rotina de rollback.
- Só trocar imagem/tráfego após esse tratamento; conferir web e workers na mesma versão compatível e provar os fluxos afetados.

Healthcheck e CI não comprovam resultado em produção. QA após deploy deve usar conta e dados de teste autorizados, sem disparos para clientes.

## Revisão e CI

Revisor independente integration_review, somente leitura: nenhum bloqueador de integração confirmado. Deltas disjuntos (39 e 25 arquivos), ambos os heads preservados e ordem migration/web/worker/tráfego compatível nos dois workflows.

Gates de publicação confirmados pelo revisor:

- P1: fallback de produção aceita disco local e os containers não montam volume compartilhado. IaC declara S3/permissões, mas é necessário confirmar ACTIVE_STORAGE_SERVICE=amazon efetivo e prova controlada de escrita/leitura entre web e worker antes de liberar a publicação.
- P1: rollback automático troca listener antes do worker anterior e não trata pendências das features. O runbook combinado acima deve anteceder qualquer rollback.
- P2 condicionado: prioridade estrita das filas pode atrasar follow-ups/recovery quando houver backlog contínuo; sem evidência de starvation atual.
- Hub2You declara e força EMAIL_CAMPAIGN_ENABLED=true; Autonom.ia mantém desativado por padrão. Não habilitar automaticamente no outro destino. Confirmar runtime e limitar E2E da importação ao destino habilitado.

CI final, link do run e estado de aprovação são registrados na PR #433 após conclusão, sem novo commit meramente para repetir o status do GitHub. Segurança e lint são informativos (continue-on-error), portanto um job verde não significa ausência de alertas preexistentes.

Diff-check apontou apenas duas linhas em branco no fim de arquivos documentais já herdados da #427 (runner-reproduction.txt e runner-results.txt); nenhum ajuste de produto resultou desta integração.

# Trilha local — Relacionamentos / Issue #757 — 2026-09-29

## Limites respeitados

Worktree `chat2you-757-relacionamentos`, branch `feat/757-relacionamentos`, base/HEAD
`8396d7255e097ba79507a22081701eb41ddb6ce5`. Sem commit, push, PR, merge, deploy,
workflow dispatch, requisição de produção, dados reais, agentes ou modelos pagos.
Sem edição de AGENTS/CLAUDE, auth/secrets/billing, banco/infra compartilhada ou workflows.
Nenhum acesso a outro worktree. O plano inicial sem rastreamento foi preservado.

## Decisões e evidências

1. Extensões por flags independentes, off; bits existentes preservados. Apresentação em Account.settings,
   valores nas entidades existentes. Nenhuma migration.
2. API específica evita mudar contratos antigos. Gravação de configuração/definição em transação;
   revisão do layout e updated_at da definição; atualização parcial de valor com comparação de previous.
3. Modal Dialog compartilhado, ChoiceSelect, botão no conteúdo do accordion; ContactPanel/AccordionItem
   não redesenhados. Editor novo usa caminho local para evitar o save sem await e a conversão de datas
   existentes no CustomAttribute genérico. Campos completos legados permanecem disponíveis.
4. Central encaminha criar/editar ao modal compartilhado apenas com extensão ligada; job_title não muda.
5. Empresa usa company_id e PermissionFilterService existente, antes da contagem/serialização.
   Foi detectada e corrigida a ausência de Account.attachments: consulta parte de Attachment com account_id.
6. Preview específico sem alterar Attachment.thumb_url. Conversão local em job low com limites,
   sem OCR/provedor externo, original preservado, arquivo derivado com reautorização no endpoint.
7. Navegação mantém nomes/URLs; home sem métricas; seleção de views continua nos Contatos.
8. pt_BR e inglês novos separados; outras traduções não foram alteradas. Guia e registry gerados por comando.
9. Revisão local do RequestExceptionHandler mostrou que Pundit usa HTTP 401; spec de gestão negada foi
   alinhado a esse contrato existente (flags desligadas usam 403). Não se removeu nenhuma asserção por falha.
10. Endpoints novos exigem AccountUser e policy existente, evitando que um token de bot sem perfil humano
    chegue à consulta de permissões de usuário. Não se alterou autenticação global.
11. Busca de contatos da mídia valida texto de até 200 caracteres sem coerção de arrays; spec de request
    acrescentado. RuboCop e sintaxe dos dois arquivos passaram; execução Rails permanece bloqueada.

## Validação e bloqueios

Comandos exatos, resultados e matriz restante estão em
[qa-acceptance.md](../relationships/qa-acceptance.md).

Baseline JS: 16/16. Rodada consolidada final: 72/72 em 10 arquivos.
Corrida de save antigo fechando modal reaberto corrigida e testada; a rodada focal do modal passou 5/5.
Ruby sem Rails: 10/11; PNG falha por libvips nativa ausente. PDF/vídeo reais sintéticos passaram.
Ruby Rails: bloqueio de sandbox no PostgreSQL isolado 127.0.0.1:55757; zero exemplos executados.
Não houve tentativa de usar servidores existentes ou de escapar do sandbox.
RuboCop: 20 arquivos sem infrações. Sintaxe Ruby: 22 arquivos sem falhas.
ESLint passou a incluir explicitamente os Vue após detectar que a chamada de diretórios cobria
somente JS; erros de props/ordenação/incrementos/whitespace foram corrigidos, sem relaxar regras. Build completo e reexecução final após lint passaram (exit 0); Guia/Central passaram com avisos
legados. Playwright local não encontrado. `.codex/relationships/build.log` não gravável no perfil
atual; saída das ferramentas usada como evidência, sem logs públicos.

Specs foram escritos antes/ao longo da implementação. Não houve ciclo vermelho-verde completo
para cada alteração: indisponibilidade de Rails e testes de componente adicionados após o código
impedem afirmar TDD integral. Falhas iniciais de carregamento/mocks foram corrigidas preservando
asserções; a falha real de PNG permanece. Testes com HTTP simulado não são evidência de backend/E2E.

## Handoff

Não pronto para release. Falta integração, E2E/visuais/performance, verificação de runtime e revisão
independente pelo supervisor. Nenhum Project remoto foi atualizado por proibição de ferramentas remotas.
Campos pendentes e plano de publicação/rollback estão em
[rollout-rollback.md](../relationships/rollout-rollback.md).

## Inventário de arquivos

A lista abaixo é local e não representa commits ou staging.

- `README.md`
- `app/controllers/api/v1/accounts/relationships/configurations_controller.rb`
- `app/controllers/api/v1/accounts/relationships/values_controller.rb`
- `app/javascript/dashboard/components-next/Companies/CompaniesHeader/CompanyHeader.vue`
- `app/javascript/dashboard/components-next/Contacts/Pages/ContactDetails.vue`
- `app/javascript/dashboard/components-next/Relationships/CompanyMedia.vue`
- `app/javascript/dashboard/components-next/Relationships/ContactViewSelect.vue`
- `app/javascript/dashboard/components-next/Relationships/FieldConfigurator.vue`
- `app/javascript/dashboard/components-next/Relationships/FieldEditor.vue`
- `app/javascript/dashboard/components-next/Relationships/MediaThumbnail.vue`
- `app/javascript/dashboard/components-next/Relationships/RelationshipBreadcrumb.vue`
- `app/javascript/dashboard/components-next/Relationships/RelationshipFields.vue`
- `app/javascript/dashboard/components-next/Relationships/presentation.js`
- `app/javascript/dashboard/components-next/Relationships/specs/CompanyMedia.spec.js`
- `app/javascript/dashboard/components-next/Relationships/specs/FieldConfigurator.spec.js`
- `app/javascript/dashboard/components-next/Relationships/specs/FieldEditor.spec.js`
- `app/javascript/dashboard/components-next/Relationships/specs/accountIsolation.spec.js`
- `app/javascript/dashboard/components-next/Relationships/specs/presentation.spec.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/composables/useRelationships.js`
- `app/javascript/dashboard/featureFlags.js`
- `app/javascript/dashboard/helper/guideRouteRegistry.js`
- `app/javascript/dashboard/i18n/locale/en/index.js`
- `app/javascript/dashboard/i18n/locale/en/relationships.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/index.js`
- `app/javascript/dashboard/i18n/locale/pt_BR/relationships.json`
- `app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.spec.js`
- `app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.vue`
- `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue`
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/routes/dashboard/relationships/CompanyMediaView.vue`
- `app/javascript/dashboard/routes/dashboard/relationships/RelationshipsHome.vue`
- `app/javascript/dashboard/routes/dashboard/relationships/routes.js`
- `app/javascript/dashboard/routes/dashboard/settings/attributes/Index.vue`
- `app/models/attachment.rb`
- `app/services/relationships/configuration.rb`
- `app/services/relationships/definition_writer.rb`
- `app/services/relationships/presentation.rb`
- `app/services/relationships/value_patch.rb`
- `app/services/relationships/value_validator.rb`
- `config/features.yml`
- `config/routes.rb`
- `docs/audit/2026-09-29-relationships-757.md`
- `docs/central-de-ajuda/mapa-de-artigos.json`
- `docs/companies_custom_attributes.md`
- `docs/relationships/attributes-and-visibility.md`
- `docs/relationships/company-media.md`
- `docs/relationships/qa-acceptance.md`
- `docs/relationships/rollout-rollback.md`
- `enterprise/app/controllers/api/v1/accounts/companies/media_controller.rb`
- `enterprise/app/jobs/relationships/company_preview_job.rb`
- `enterprise/app/services/relationships/company_media_query.rb`
- `enterprise/app/services/relationships/preview_renderer.rb`
- `lib/central_de_ajuda/09/09.11-relacionamentos-e-campos-compartilhados.md`
- `lib/central_de_ajuda/09/09.12-midias-das-empresas.md`
- `lib/operator_guide/guia-produto.md`
- `lib/operator_guide/porques.md`
- `spec/enterprise/jobs/relationships/company_preview_job_spec.rb`
- `spec/enterprise/requests/relationships/company_media_spec.rb`
- `spec/enterprise/services/relationships/company_media_query_spec.rb`
- `spec/relationships_unit/relationships/preview_renderer_spec.rb`
- `spec/relationships_unit/relationships/value_validator_spec.rb`
- `spec/requests/relationships/configuration_spec.rb`
- `spec/requests/relationships/values_spec.rb`
- `spec/services/relationships/configuration_spec.rb`
- `spec/services/relationships/value_patch_spec.rb`
- `tests/playwright/relationships.config.ts`
- `tests/playwright/tests/relationships/fields.spec.ts`


## Retomada autorizada — 29/09/2026

A revisão inicial e supervisor-feedback foram lidos antes das correções. A instrução mais
recente sem regex substituiu expressamente a sugestão anterior de subprocesso Node.
Os contratos, decisões, comandos, resultados e pendências desta retomada estão em
`docs/relationships/continuation-result.md`. Fontes: código e specs locais, AGENTS.md,
docs/relationships, revisão/feedback locais. Nenhum dado de produção foi consultado.

Foram preservadas as alterações prévias e o HEAD/base 8396d7255e097ba79507a22081701eb41ddb6ce5.
Mudanças nos controllers legados foram limitadas aos locks de leitura/merge/escrita de
Account settings e atributos de Contato/Empresa. Nenhuma alteração em auth/secrets/infra
compartilhada; apenas a dependência ffmpeg autorizada no Dockerfile runtime.

Evidência local final: JS 74/74 em 15 arquivos; Ruby unit 12/12; RuboCop 25 arquivos sem
infrações; ESLint sem erros; AST 73 fontes/testes/scripts sem regex nova; Guia/Central em dia.
Integrações PostgreSQL, E2E, imagem Linux, performance e revisão independente permanecem
gates do supervisor; não declarar ready. Escrita em `.codex/relationships` foi negada pelo
sandbox; logs ficaram em `/private/tmp/relationships-*`, sem tentar contornar permissões.

Build final `pnpm exec vite build --mode test --logLevel warn`: exit 0. Prettier passou
e `git diff --check` permaneceu limpo após a documentação final. Artefatos de build estão
no diretório ignorado escolhido pelo Vite; não houve publicação.

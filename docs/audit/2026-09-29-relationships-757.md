# Trilha — Relacionamentos / Issue #757 — 2026-09-29

> Registro cronológico: os primeiros blocos descrevem rodadas anteriores de agentes.
> O status consolidado está em `docs/relationships/qa-acceptance.md` e na PR #760.

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

## Consolidação pelo supervisor

A PR #760 foi aberta como rascunho para CI/revisão, sem merge/deploy. Commits de aplicação
permanecem na branch `feat/757-relacionamentos`; main e ambientes reais não foram alterados.
A base é8396d7255e e o candidato de código desta rodada écad28d3772.

Reexecução local:6.771 testes frontend e385 exemplos integrados PostgreSQL, todos aprovados;
16 testes nativos e14 fluxos de navegador aprovados. Performance, visuais, limitações
e comandos reproduzíveis constam em qa-acceptance.md. Revisão independente final não
apontou P0/P1/P2 demonstrável; o aceite continua condicionado ao CI no SHA atual.

As falhas de CI anteriores foram investigadas, não suprimidas: parser transitivo e vendor
no gate AST, disco do runner descartável, lint estrito e bootstrap do processo de imagem.
Foi preservada a restrição de zero regex nova. A chave automática deixou de ser exposta
no modal; sua geração e imutabilidade permanecem no contrato/testes.

O hook de commit chegou a chamar o Ruby2.6 do sistema; a execução não foi contada como
validação Ruby. Os specs foram reexecutados com Ruby3.4.4 explícito, sem alterar instalação
global. Os avisos e rodadas históricas permanecem registrados, sem inventar aprovação.

O conector do Project retornou404; os sete campos pendentes estão em rollout-rollback.md.
Nenhuma autorização anterior de deploy da PR#756 foi reutilizada para esta entrega.

## Fechamento dos gates Linux e do mapa de recursos

O gate de e-mail encontrou somente uma expectativa antiga do mapa de flags, que ainda
não incluía os três novos bits. A expectativa continua uma igualdade exata; preserva
todos os bits anteriores e agora fixa os novos bits e testa sua independência/opt-in.

O run36584352561 da imagem exata confirmou `Vips::Error: out of memory` no processo filho
com512MiB. Em vez de ampliar memória ou afrouxar o teste, o preview das três imagens
foi levado ao FFmpeg já presente para vídeos, com assinatura e demuxer fixos. Os limites
de memória/CPU/tempo/entrada/saída foram mantidos.18 testes nativos passaram e a revisão
estática independente do delta não encontrou P0/P1/P2; o próximo CI ainda precisa
confirmar a imagem exata, sem qualquer publicação.

A seleção ampliada local passou458 casos em459 exemplos, com uma quarentena antiga
explicitamente preservada. Report: expanded-final-rspec.json. Nenhum teste novo em skip.

## Retomada final — lint cumulativo / sem alteração de produção

PR #760, base8396d7255e, candidato anterior6718569456. O CI de regressão do recurso
passou; o gate de Email detectou6infrações cumulativas de RuboCop. Corrigido o extractor
com classe compacta e helper de item, preservando ordem, lock e coerções; diagnóstico de
runtime usa `$stderr`. Não houve mudança de limites ou afrouxamento de gates.

Validações: `resume-all-rubocop.log` =44arquivos, zero infrações;
`resume-backend.json` =87exemplos/zero falhas;
`resume-expanded-rspec.json` =471exemplos/zero falhas/1quarentena preexistente.
AST sem regex nova passou. A revisão `lint-delta-review.md` não encontrou P0/P1/P2 e
comparou71cenários diferenciais sem divergência. Arquivos de evidência ficam no diretório
local ignorado `.codex/relationships/`, sem dados reais ou credenciais no repositório.

Project Autonom.ia Dev foi consultado novamente e retornou404; campos exatos permanecem
em rollout-rollback.md e na PR. Nenhum merge, deploy, edição de conta real ou gatilho de
produção foi executado. A execução Linux no HEAD final continua condição de liberação.

Rodada final de navegador `resume-final-browser.log`:14/14 aprovados em2,6minutos,
com backend real, autenticação normal e limites de timeout mantidos. Nenhuma limpeza
ou mudança de sessões/política de autenticação foi executada nesta retomada. O frontend
não mudou desde a versão já revisada. A confirmação final do CI fica registrada na PR
para conservar o SHA exato da versão testada.

## Project — contingência concluída

Após a falha404do conector dedicado, o GitHub CLI já autorizado conseguiu ler o Project3
Autonom.ia Dev. A Issue757e a PR760não estavam associadas; foram adicionadas e receberam
Projeto=Hub2You, Status=Em review, Tipo=Feature, Prioridade=P2, Risco=Médio, Ambiente=Local
e a próxima ação de finalizar os checks e obter aprovação antes de publicar.
Uma consulta posterior verificou7/7campos em cada item. Nenhum escopo OAuth, token ou
configuração de acesso foi alterado. Evidências locais: `project-updated-items.json`
e `project-verified.json`. A pendência administrativa está resolvida; autorização de
merge/deploy continua exclusivamente com Rodrigo.

## Publicação aprovada — integração da atualização GPT-6

Rodrigo autorizou merge/deploy com as três extensões ligadas e testes posteriores.
Antes da publicação, a conferência independente por Git/CLI detectou main a97e4a9e5b,
com a release #761/#759 em produção (14a8d040d3). A metadata anterior da PR ainda
mostrava a base antiga. Atualização integrada na branch sem conflitos; único arquivo
sobreposto config/routes.rb acrescenta ai_requests e mantém as rotas de Relacionamentos.

A suíte conjunta detectou contaminação por fixtures de testes de concorrência que
não usam transações: blobs sample.pdf/preview.jpg e configuração MAXIMUM_FILE_UPLOAD_SIZE
sobreviviam aos exemplos e alteravam contagens absolutas em specs de arquivos/ConfigLoader.
A correção é restrita aos cinco grupos de teste envolvidos: remover os registros auxiliares
criados por esses próprios exemplos (blobs já desvinculados e configurações) ao finalizar.
Não foi modificada nenhuma regra de modelo, comportamento de produção ou asserção legada.
Nova suíte em banco dedicado limpo deve confirmar o fechamento; não atribuir as falhas
à migração de modelo sem evidência.

### Fechamento da bateria integrada após isolamento de fixtures

Banco dedicado novo `relationships_757_release2` (somente loopback): 5.624 exemplos,
zero falhas e sete quarentenas já existentes. A lista reúne o trem de release e os
contratos adicionais de Relacionamentos e da atualização GPT-6. Frontend da árvore
integrada: 6.782 testes aprovados. Nenhuma alteração de lógica GPT-6 foi necessária.
A correção de isolamento foi aprovada pelo RuboCop nos seis arquivos de teste; gate AST
sem regex aprovado. Guia build/check e Central check sem delta gerado.

PR operacional #766 revisada e testada para ativação/validação via OIDC existente,
somente .github e docs, sem deploy de aplicação ou mudança de IAM. Smoke local real
nas APIs: nove verificações e rollback de todos os registros sintéticos; sete contratos
Python aprovados. Conferência Hub2You via SSM no SHA14a8d040d3 confirmou web/worker,
alvo saudável e rollback preservado. Preflight Autonom.ia será obtido pelo mesmo fluxo.


## Pós-merge #768 — findings e hotfix #770/#771

O release #768 foi mesclado no SHA
`585712e44ae2f083a86f2ede4bc8608cf954e199`. Hub2You concluiu o blue/green.
Autonom.ia permaneceu no binário anterior porque o build falhou antes da criação do green
e antes de qualquer troca de tráfego: o registry público da AWS respondeu HTTP 429
(`Data limit exceeded`) para as imagens-base Ruby/Node. Um retry controlado reproduziu
a mesma causa e o cleanup do workflow concluiu; não houve rollback de tráfego porque não
houve shift.

A revisão automática do PR #768 deixou três threads: um P1 de governança i18n e dois P2
funcionais. A inspeção do código confirmou os dois P2:

1. resposta JSON `unavailable` do preview era classificada pelo cliente como retryable;
2. um preview `pending` podia permanecer sem job útil quando a flag era desligada entre
   enqueue e execução, atrasando nova demanda até o TTL.

A Issue #770 e o PR #771 tratam os P2 em branch isolada
`fix/770-relationships-post-merge-findings`. O cliente agora distingue
`application/json` com status `unavailable` de falha transitória. O job limpa somente
o metadata `pending` da mesma solicitação/blob quando perde elegibilidade por flag e
permite novo enqueue imediato após reativação. Foram adicionados testes direcionados.

O P1 de tradução não foi mascarado: `pt_BR/relationships.json` foi introduzido
manualmente, enquanto AGENTS.md determina que traduções não inglesas venham do Crowdin.
O fork possui `crowdin.yml`, mas não foi comprovado nesta retomada um mecanismo
autorizado capaz de sincronizar esse novo catálogo. Remover a tradução agora introduziria
regressão visível para pt-BR. A ativação permanece bloqueada até essa decisão ficar
registrada corretamente.

O reviewer Codex do PR #771 não executou por limite de uso da conta. Isso não foi tratado
como aprovação: o delta foi revisado manualmente e continua sujeito aos workflows de CI,
incluindo regressão de Relacionamentos, imagem Linux, Email protection e Guia.

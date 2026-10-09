# B3/BE-05 — preparação do RED

**Data:** 2026-10-07
**Branch:** `docs/agentes-ia-prd`
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`
**Escopo:** somente specs RED de BE-05; nenhuma implementação de produto nesta etapa.

## Fontes e traçado conferido

- `docs/agentes-ia-redesign/design/B3.md:67-206,227-269`;
- `docs/agentes-ia-redesign/revisoes/B3-desenho-normal-integracao.md` e
  `docs/agentes-ia-redesign/revisoes/B3-desenho-final.md`;
- `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:1-168`;
- `app/models/autonomia/agents/agent.rb:220-342`;
- `app/models/autonomia/agents/build_thread.rb:142-251`;
- `app/services/autonomia/agents/builder.rb:666-698,1005-1028,1334-1413,1543-1568`;
- `app/jobs/autonomia/agents/builder/submit_job.rb:11-57`.

O caminho real do writer é `SubmitJob#perform` → `Builder#run!` → `Builder#apply_to_agent` →
`Agent#apply_builder_config!`. O job chama o cliente do Builder somente quando o token ainda está ativo;
as specs usam resultado estruturado local e não provedor pago. O modelo atual ainda não tem o leitor nested
de BE-05, a guarda `manual_mode` e a autoridade D22 no writer, portanto o RED cobre a lacuna sem editar
esses arquivos.

## Casos que serão provados

1. Leitor nested: `autonomia_manage` recebe a thread real e as mensagens; viewer recebe 401 antes da
   leitura; outra conta, arquivado, agente de sistema, agente inexistente, sem thread e thread de outro
   agente não vazam conteúdo.
2. Última sessão: duas threads do mesmo agente retornam a de maior `id`; o GET zera somente
   `state.force_close`, preserva mensagens, materiais, token/status e fica idempotente; não cria thread,
   não chama `begin_build!` e não enfileira job.
3. Modos: manual devolve 422 `manual_mode` sem reset, append ou enqueue; Lia preserva 422
   `instrucao_mantida`.
4. Writer: criação sem instrução, inclusive E1/E2 com agente já vinculado, aceita schema completo; com
   `instruction.present?`, somente os cinco campos D22 mudam e `name`, voz, fallback, tone, actuation,
   canais e demais configuração permanecem iguais.
5. Corridas: um Builder que fotografou o rascunho não pode aplicar schema completo depois que o agente é
   recarregado com instrução; troca para manual depois do enqueue recusa dentro do lock e não sobrescreve a
   instrução escrita à mão.

## Limites

Os dois arquivos de spec desta ownership são novos e permanecem RED até implementação posterior pelo root.
Não foram executados RSpec, banco, build, navegador, jobs, serviços, commit, push, merge, fila, deploy ou
produção. O desenho B3 continua DRAFT; depois que os specs forem salvos, a escrita será pausada para o
snapshot coordenado pelo root.

Conferência root antes da primeira execução: fixture let(:thread) é lazy; o primeiro GET deve instanciá-la antes da request, caso contrário um reader correto receberia 404. Acrescentada instanciação explícita, sem global let! para preservar o caso de ausência. Na corrida de voz, agente direto sem config não grava defaultvoice: criada voz feminina explicitamente para provar preservação real, sem exigir default inventado. Última sessão agora toca updated_at da antiga depois da nova, provando id autoritativo e não somente ordem feliz. Nenhum produto alterado antes do RED.

RED20 executado no snapshot `20261007-181515-532a5b7b-e76d0d757d-02911268`, SHA-256 `e76d0d757d3e9028a2a7a01f4d28ad01437269411bfaea8682405cb46e37dbdc`, job `m2-df3303b6c9654ef28008600a2714d701`: 14 exemplos, nove falhas, zero pendências/erros externos, 5,365s. JSON M2 `/tmp/chat2you-agentes-b3-red20.json`, SHA-256 `276270c4d695091affd41a97cace958b0ef45d070da71693a4fce9d08c86379d`. Oito falhas comprovam leitor/guard/writer ausentes. Uma falha não comprova D22: a fixture declara `response_window: curta`, fora do enum real (`always`, `business_hours`, `outside_business_hours`), e é recusada antes da geração. Causa registrada antes da correção: valor humano inventado no dado sintético. Trocar somente a fixture/expectativa por `outside_business_hours` e repetir RED antes de alterar produto. Não abrir compatibilidade para valor inválido no model.

RED21 executado após corrigir o enum da fixture, sem produto BE05: job `m2-87ec816ccc01414cbf5ff5b159eb20b0`, JSON SHA-256 `562b41620a09015fe1003bf0e4ec4987a15bd16d9e83d607f9921f53b116f2c2`. Seleção conjunta 45 exemplos/14 falhas/zero pendências/erros externos/14,137s. BE05: 14 exemplos, nove falhas reais (seis reader/porta manual e três writer D22/manual), duas criações completas e três recusas/guard legado passam. B2: quatro RED numéricos e um shape inbox_id falham exatamente como a revisão; as três fixtures de Copiloto corrigidas executam 16 exemplos sem falha. Nenhuma falha de preparação restante nesta seleção. Este RED não é GREEN do produto ou revisão final.

Início do produto BE05 após RED21 limpo de fixtures: reader sob lock Agent→BuildThread escolhe id DESC na conta e zera somente force_close true. Guarda comum do model recusa manual/Lia na porta e no runtime; writer revalida após reload dentro do lock e calcula D22 com instrução atual. Criação E1/E2 mantém schema completo. Job traduz ManualMode para erro estável sem modelo/escrita, não genérico. Nenhuma migration prevista; rotas/strongparams demandam regeneração oficial do Guia depois da implementação.

GREEN inicial Ruby BE05 no snapshot22/job `m2-cf82527fb63945769c6ae38c0f6f5013`: 14 casos passaram/zero falha ou pendência; seleção completa222ainda tem oito falhas B2, sem afirmar integração/revisão/CI/aceite. Cliente/store de retomada continuam sem implementação, aguardando RED frontend após preparar dependências isoladas.

## Lint24 — causa registrada antes da correção

O lint24 do conjunto de specs BE-05 reportou 11 ofensas. A ofensa sob esta correção é
determinística em `spec/requests/api/v1/accounts/autonomia/agents/build_thread_resume_spec.rb`: o exemplo
com muitas asserções declarou a metadata como `aggregate_failures: true`, enquanto o padrão RSpec do
repositório usa a metadata simbólica `:aggregate_failures`. Isso é estilo da spec e não muda o contrato,
fixture, escopo ou execução do produto. O bloco autorizado corrige somente essa declaração; as demais
ofensas permanecem fora desta ownership e não são declaradas resolvidas aqui.

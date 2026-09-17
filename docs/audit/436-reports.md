# Auditoria #436 — reports/metrics/API

Data: 2026-09-16. Worktree: `436-email-protection`. Alterações restritas aos serviços de
reports/queries/presentation, ReportsController, jbuilders de reports, specs novas com
sufixo `_436_spec.rb` e aos dois documentos autorizados. Arquivos dos demais responsáveis
foram apenas lidos. Sem commit, push, PR, merge ou operação em outra worktree.

## Evidência de partida

Inspecionados Builder/ReportsController/jbuilders reais, EmailCampaign/Recipient/Event,
importador, import/issues, supressões, BounceClassifier, HygieneConfig, PreflightDecision,
AddressPreflight, job de preflight, cliente API e componentes atuais da UI. Leitura do
schema confirmou `raw_address`, não `raw_email`, no modelo de problemas de importação.
Busca em `enterprise/` não encontrou override destes relatórios.

Defeitos encontrados no código anterior: CSV limitado silenciosamente a 10.000; filtros
só por texto; taxas de bounce/complaint divididas por entregues; zeros em base vazia;
contadores persistidos com eventos duplicados; dropdown reduzido pela campanha selecionada.
O limite do timeline por created_at já existia e foi preservado.

## Decisões implementadas

- RecipientQuery único em tela/CSV; CampaignQuery reutilizável, incluindo status attention
  da UI, com options independente de campaign_id.
- Rejeição 422 de filtros malformados e de datas não suportadas; erros antes do stream.
- KPI distinto por destinatário, atividade bruta separada, sent_at como base de aceitação,
  current_status_counts separado, no_data em base zero.
- Três consultas agrupadas de métricas por escopo, sem consulta por campanha/métrica.
- BounceClassifier real compartilhado em apresentação, métricas e seleção; último evento
  por occurred_at/id. Provider suppression nunca comprova mailbox inválido. Correção final: Suppressed global conta como permanente; os quatro PREVENTED ficam separados.
- Taxas locais SES separadas de direct_inbox; sem serviço duplicado de reputação.
- Opt-out fora de atenção e proteção com prioridade sobre vereditos de preflight.
- Higiene reconciliada sobre não enviados; histórico enviado e issues de CSV separados.
- CSV com Enumerator, lotes <=500, horizonte inicial de ID, BOM e neutralização de fórmulas.
- Leitura/export de issues reais com whitelist; import_summary atual sem metadata arbitrária.

## Verificações realizadas na primeira entrega

1. `ruby -c` em 24 arquivos Ruby/Jbuilder do escopo: saída `Syntax OK`, exit 0.
   A primeira passagem usou Ruby do sistema 2.6.10; a passagem posterior e final usa
   `eval "$(rbenv init -)"`, Ruby **3.4.4** exigido pelo projeto. Sem inicialização Rails.
2. Script Ruby puro por stdin, carregando somente o exportador e `csv` da biblioteca padrão:
   10.001 registros sintéticos em scope de memória, 21 lotes, maior lote 500; não inclui
   registro 10.002 adicionado depois de construir o exportador. Verificou BOM, aspas/vírgulas,
   neutralização após whitespace/controle (incluindo NUL) e preservação de email normal.
   Resultado final: `PASS`, exit 0, ~0,13 s. Uma tentativa inicial do **harness** falhou por
   chamar `last` em CSV::Table; corrigida para índice explícito e executada novamente.
   Não houve falha identificada no exportador nesse ensaio. Esse teste não valida SQL/Rack.
3. `git diff --check --` nos caminhos autorizados: sem saída, exit 0.
4. Verificação estática de linhas Ruby/Jbuilder acima de 150 caracteres: nenhuma.
5. Revisão própria dos arquivos novos e diff existente: escopos por conta, subqueries,
   precedência de proteção, ausência de provider payload, bases de métricas, classificação
   compartilhada, ordenação, streaming e seam do serviço B conferidos por leitura.

Comando da validação sintática final (executado via lista equivalente em Python/subprocess):

```sh
eval "$(rbenv init -)"
for file in app/services/email_campaigns/reports/*.rb app/services/email_campaigns/presentation/*.rb app/services/email_campaigns/recipient_query.rb app/services/email_campaigns/campaign_query.rb app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb app/views/api/v1/accounts/email_campaigns/reports/*.jbuilder spec/services/email_campaigns/reports/*436_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb; do
  ruby -c "$file" || exit 1
done
```

**Não executados na primeira entrega:** Rails boot, rake, RSpec, migrações, conexão com banco, lint via Bundler,
instalação de dependências, API externa, SMTP, AWS, SSH ou produção. Nenhum dado de cliente,
secret ou conteúdo de ambiente foi lido/registrado. Exemplos usam example.org.

## Pendências para o integrador

- Adicionar GET `reports/:id/import_issues` e GET `reports/:id/import_issues/export`.
- Integrar modelos/migrações de higiene do responsável A e preparar banco isolado.
- Inserir helpers no controller/jbuilder de campanhas conforme ownership principal.
- Integração inicial de `@protection` concluída nesta finalização via adapter read-only; marcador de geração e POSTs ainda exigem o parent (ver seção final).
- Alinhar UI a counts.total de não enviados + historical_sent separado, classificação de
  issues e motivos reais (provider_suppression, permanent_failure etc.).
- Executar specs documentadas em `docs/email-campaigns/reports.md`, confirmar comportamento
  PostgreSQL/ActiveRecord e medir queries. Specs de novas actions dependem das novas rotas.
- Confirmar streaming via middleware/proxy real. O horizonte de IDs não é snapshot
  transacional: alterações/deleções concorrentes podem alterar resultados entre lotes.
- Revisão independente e validação integrada pendentes. Não há declaração de PR pronta.

O fluxo Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback
permanece a cargo do responsável principal; as proibições explícitas deste recorte impedem
publicar ou operar Git remotamente nesta execução. Merge/deploy continuam exigindo Rodrigo.
Rollback proposto para integração: reverter somente o commit de relatórios após aprovação;
este recorte não tem migração nem escrita de dados para desfazer. Migrações de outros
responsáveis precisam do plano próprio deles.


## Integração do armazenamento corrigido — 2026-09-16

Aplicadas as skills systematic-debugging e verification-before-completion. As novas specs
foram escritas antes das respectivas correções, mas **não houve ciclo red/green Rails**:
a instrução explícita do responsável proíbe boot/RSpec/DB neste recorte. A skill de TDD
não substitui essa restrição. Nenhum resultado de spec Rails é declarado.

### Evidência e decisões

- Lidos novamente, sem edição: EmailSuppression, EmailSuppressionState, SuppressionRegistry,
  HygieneConfig, RecipientPreflightJob, PreflightLease, PreflightDecision, AddressPreflight,
  DomainValidator, RecipientImporter e modelos de importação. O código atual tem PreflightLease;
  não foi encontrada classe PreflightRun. Leitura dos contratos C e do cálculo agrupado do
  ActiveRecord 7.2.3.1 local também foi usada; nenhuma aplicação Rails foi inicializada.
- Removidas as chamadas inexistentes a EmailSuppression.blocking. RecipientState agora
  une positivos legados e EmailSuppressionState.blocking em SQL, por account_id. O filtro
  de motivo dá precedência à presença legada, igual à API batch: não perde unsubscribe
  legado ao expirar uma quarentena. Estados fortes ativos não expiram pelo relógio,
  conforme scope real. Nenhum Set completo de emails foi materializado.
- Recipients usa blocking_reasons_for fresco por lote, com retorno imediato no lote vazio.
  Motivos legados arbitrários ficam legacy_suppression. Conta é carregada uma vez pela
  campanha, sem associação belongs_to por destinatário.
- Ready agora exige checked_at e validade futura, além de valid/pending/não enviado.
  Falta de TTL em dns_disabled/typo/formato preserva unknown/review/invalid. Reports não
  agenda rechecagem, não invalida checagens e não descarta unknown.
- invalid_recipient é review. Spec usa importador real com email válido e nome de 256
  caracteres, confirmando o contrato pretendido sem executar importação nesta sessão.
- Métricas foram refatoradas em bases, taxas e cobertura para atender aos cops de tamanho;
  permanecem COUNT DISTINCT, eventos tardios, denominadores vazios null e bases SES/direct
  separadas. Taxas já saíam planas e aninhadas; ambas foram preservadas.
- Revisão própria do export: autorização da action e conta precedem a construção do
  Enumerator; maximum(:id) precede headers; não usa find_each com ordem ignorada. Escopo
  filtrado continua usado em cada lote. Sem teto de 10 mil, sem N+1 por destinatário.
- Datas de atributos permanecem tipadas até a serialização Jbuilder; a leitura do código
  instalado do ActiveRecord confirmou uso de column_types nos buckets de group/count.
  Foram acrescentadas specs HTTP para timestamps/bucket ISO e taxas planas.
- Filtros escalares, nil, página negativa e 422 de since/until revisados. As datas não
  foram transformadas em uma falsa janela temporal. Ajustes exatos do adapter C estão
  em docs/email-campaigns/reports.md, incluindo status protected e códigos de motivo.

### Validações desta integração

Todos os comandos Ruby usaram explicitamente:

```sh
PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:$PATH
```

1. RuboCop inicial: **24 arquivos, 32 ocorrências**, exit 1. Feitas refatorações e correções
   locais; sem desativação global de cops. Exceções pontuais: caminho das specs imposto pelo
   recorte (RSpec/SpecFilePathFormat somente na declaração) e insert_all! da fixture de
   10.001 linhas (Rails/SkipsModelValidations somente na inserção, com justificativa).
2. RuboCop final: **24 arquivos, zero ocorrências**, exit 0, ~0,92 s. Somente os mesmos
   24 arquivos; RUBOCOP_CACHE_ROOT em /private/tmp/436-reports-rubocop. Comando:

```sh
PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:$PATH RUBOCOP_CACHE_ROOT=/private/tmp/436-reports-rubocop bundle exec rubocop --format simple app/services/email_campaigns/reports/*.rb app/services/email_campaigns/presentation/*.rb app/services/email_campaigns/recipient_query.rb app/services/email_campaigns/campaign_query.rb app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb app/views/api/v1/accounts/email_campaigns/reports/*.jbuilder spec/services/email_campaigns/reports/*436_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb
```

3. `ruby -c`, invocado por subprocess Python em cada arquivo da mesma lista: **24 Syntax OK**,
   exit 0, ~0,15 s. Ruby 3.4.4 +PRISM confirmado. Zero linhas acima de 150 caracteres.
4. Script Ruby puro por stdin, carregando somente csv, time e reports/csv_export.rb:
   **19 verificações passaram**, exit 0, ~0,15 s. Scope sintético em memória com 10.001 linhas,
   21 lotes, maior lote 500. Verificou BOM, quantidade completa, ordenação/horizonte de ID,
   exclusão do registro 10.002 inserido após construir o exportador, aspas/vírgulas, email
   preservado, timestamp ISO, oito prefixos de fórmula (incluindo NUL/tab/CR), valores nil/
   numéricos e export vazio sem chamar presenter. Não valida PostgreSQL nem Rack.
5. `git diff --check --` limitado aos caminhos autorizados: exit 0, sem saída. Como vários
   arquivos ainda não são rastreados, a verificação estática da lista também inclui esses
   arquivos; nenhuma alegação de diff Git completo para arquivos não rastreados.

### Specs novas/ajustadas, pendentes de execução pelo principal

- União dos armazenamentos, prioridade dos legados, opt-out após expiração, estados
  inativos/fortes, isolamento de outra conta e ausência de TTL em unknown.
- Motivo legado desconhecido limitado, consulta fresca por lote e nenhuma consulta com
  lote vazio; orçamento de quatro SELECTs de apresentação após carregar account.
- Ready com checked_at, reconciliação de no-TTL sem agendar trabalho e importação com nome
  longo mantendo email válido como review.
- Filtros nil/negativos/objetos, rejeição HTTP de datas não suportadas, timestamps e taxas
  planas serializados pelo Jbuilder. Mantidas specs de 10.001 linhas, métricas e tenant.

**Não executados nesta integração:** Rails/rake/RSpec, banco/migrações, AWS/SSH/SMTP,
produção, credenciais, API paga, instalação de pacotes ou escrita Git. Nenhum commit.
O principal deve executar as specs no banco sintético novo após estabilizar a migração,
ligar rotas/adapters/reputação real, atualizar Project e conduzir revisão independente.


## Finalização PR2 e contrato público — 2026-09-16

Esta seção e `docs/email-campaigns/reports.md` substituem os seams/pendências de contrato
anteriores. PR0 informado pelo parent: `406ef3a7de`; nenhum commit, branch, PR ou Git write
foi criado aqui. PR1 continua sob integração do parent, fora desta entrega.

### Escopo executado e fronteiras

Ownership: somente ReportsController, Reports/queries/presentation, Jbuilders de reports,
suas specs, novo adapter Presentation::Protection e estes dois documentos. Não houve escrita
em campaigns_controller.rb, routes.rb, modelo/Jbuilder de campanha, UI, maintenance, migrations,
policies, classificador ou worktree irmã. `AGENTS.md`, `436-ui.md`, componentes/specs EmailProtection,
fontes locais de higiene/políticas e fontes reais de reputação foram lidos. Busca em enterprise
não encontrou override correspondente. `../436-email-reputation` foi exclusivamente leitura.

Fontes PR1 conferidas: modelos EmailReputationState/EmailProviderState, migrações de geração,
Evaluator/Observation/Policy/Payload/Snapshot/LegacyDecision/ProviderGate/ProviderConfig,
Metrics, Guardrail e o fluxo real de pause/resume/reevaluate. Não foram supostos campos de
provider nem equivalência entre Payload.resume_allowed e liberação segura.

### Decisões finais

- Reports index sempre retorna protection, preflight da seleção autorizada (ou null) e
  meta; summary/campaigns continuam filtrados. campaign_options usa todo o policy scope
  da conta, independente de campaign_id/status/q. Seleção de outra conta não vaza dados.
- Adapter estreito em Protection, ProtectionMetrics e ProtectionProvider: somente dados
  persistidos, allowlists de saída, razões/status públicos, taxas percentuais, trigger
  separado da avaliação atual, e leitura pontual do provider. Não chama coleção, avaliador,
  monitor, DNS, rede ou qualquer write. Não cria estado ausente. Domínios vazios porque
  o PR1 não tem evidência persistida por domínio; sem pontuação inventada.
- sticky pause permanece paused com release_eligible=true ou false. Liberação exige prova
  de publicação na geração atual, versão de feedback atual, avaliação dentro da janela,
  policy persistida compatível e aprovação da policy real. Override não substitui prova.
  ProviderGate controla bloqueio; off/unknown permitido fica unknown, nunca healthy.
  Direct inbox ignora apenas o gate SES e mantém proteção da conta.
- Capabilities usam a política administrativa da campanha/membership da conta, incluindo
  negação por policy. SuperAdmin continua distinto de administrador; não há override visual.
  Resume também exige campanha pausada, higiene completa reconciliada com ready>0 e sem
  invalid/review/unknown/unchecked/import ativo. Higiene ausente ou falha nega retomada.
- Protection é criado uma vez por index, fora do loop de campanhas; mesma instância pode
  reutilizar estado/provider/membership em uma request. Não reutilizar após POST.
- Bounce KPI usa histórico distinto por destinatário/classe, lista/filtro usa último evento
  e status atual. NoEmail é permanente genérico; global Suppressed é permanente com razão
  provider_suppression. PREVENTED contém exatamente OnAccountSuppressionList,
  OnTenantSuppressionList, EmailValidationSuppressed e UnsubscribedRecipient, reutilizando
  a constante do PR1. Esses quatro não inflam permanent/temporary/unknown no KPI. Não se
  adicionou classificador divergente nem se editou o classificador atualizado do PR0.
- Aliases permanent_bounced/temporary_bounced/unknown_bounced mantêm os nomes antigos
  *_bounces. Eventos duplicados, tardios, estados atuais, activity bruta, bases SES/direct
  e null em denominador vazio continuam separados. Classes históricas podem se sobrepor.
- Eventos delivered sintéticos de direct inbox preservados para compatibilidade; nova
  delivery_evidence e basis explícita separam aceitação de confirmação. Nenhum servidor
  aceitando a mensagem é apresentado como prova de chegada à caixa do destinatário.
- Preservados arrays opened/clicked do detalhe, taxas planas/aninhadas, filtros combinados,
  enum/status bruto de destinatários, paginação, CSV sem teto silencioso, horizonte por ID,
  lotes de 500, BOM, neutralização de fórmulas e autorização antes de headers.
- Hygiene.status protected ajustado para blocked, alias já reconhecido pela UI; can_recheck
  agora consulta EmailCampaignPolicy em vez de copiar somente a regra de membership.

### Dependência bloqueante de integração: marcador da avaliação publicada

O PR1 lido persiste observation_generation, feedback_version e evaluated_feedback_version,
mas **não** a geração que publicou current_metrics. Implementado fail-closed no adapter:
sem current_metrics.evaluation_generation, release_eligible/resume são false. Isso é uma
exigência nova de integração explicitamente documentada, não um campo alegadamente existente.

O parent precisa adicionar, dentro de Evaluator#refresh! após CAS da Observation:

```ruby
current_metrics: metrics.merge(decision).merge(evaluation_generation: observation.generation).stringify_keys
```

Sem migração nova; não preencher marcador em avaliações antigas. O parent deve testar
publicação de marcador/generation superseded/feedback concorrente junto com o PR1.
Este recorte não alterou fonte PR1 e não declarou a integração concluída.

`docs/email-campaigns/reports.md` contém wiring exato para campanha/Jbuilder, reload depois
dos POSTs, retorno `{payload: campaign DTO}` em reevaluate/recheck/resume, normalização de
pause_reason JSON, aliases de motivo da UI e retomada deliberada exigindo **ambos**
release_eligible e capabilities.resume. O frontend atual ainda veta qualquer estado paused:
o parent deve ajustar esse caso sem ocultar a pausa nem remover o veto do provider.
Autorização/checagens no POST continuam obrigatórias; DTO não autoriza escrita.

### Specs adicionadas/atualizadas, ainda NÃO executadas

- Contrato exato/allowlist, null no-data, pausa manual separada, unidades percentuais,
  trigger imutável versus métricas atuais, sticky pause elegível/inelegível, coorte vazia,
  flag permissiva com métricas ruins, generation ausente/antiga/tipo inválido, feedback
  posterior, policy alterada, avaliação vencida e override sem prova.
- Provider ligado/desligado/ausente/unknown allow/unknown block/healthy recente/stale/latch,
  bloqueio manual mesmo off, direct inbox com proteção da conta, isolamento entre contas,
  negação de policy, administrador versus SuperAdmin, higiene ausente/inconsistente/falha,
  import ativo, consulta limitada e ausência de mutação durante apresentação.
- Report index com proteção única, dropdown independente de status/campanha/busca, preflight
  selecionado com resultados vazios, isolamento de seleção e preservação do detail legado.
- NoEmail e Suppressed reais, todos os PREVENTED, bounce permanente anterior à prevenção,
  deduplicação por classe/subtipo, aliases numéricos e delivered sintético de direct inbox.
  As expectativas antigas incorretas de Suppressed/unknown/options foram corrigidas;
  nenhuma spec foi removida, desativada ou convertida em pendente.

### Validação permitida nesta execução

Somente sintaxe/RuboCop e revisão estática. Ruby via `eval "$(rbenv init -)"`:
**3.4.4**, arm64-darwin27. Nenhum arquivo da aplicação foi executado pelo ruby -c.
Primeiro RuboCop: 28 arquivos, 34 ocorrências; refatorações locais e correções de layout,
sem desativar cops. O cache inicial em /tmp provocou aviso de symlink, corrigido para
/private/tmp. As passagens intermediárias e autocorreções foram apenas no ownership.
Resultado final e comandos registrados abaixo após sua execução.

**Não executados:** Rails boot, rake, RSpec, banco, migrations, AWS, SSH, SMTP, rede,
instalação, leitura de .env/credentials/secrets, env de execução real, alterações Git,
merge/deploy ou produção. Specs só poderão ser declaradas aprovadas depois que o parent
rodar a suíte real no banco sintético isolado, com PR1/marcador/rotas integrados. A contagem
de consultas SQL e o comportamento PostgreSQL/Rack ainda precisam dessa execução.

### Manifesto completo do recorte PR2

Os caminhos abaixo compõem a entrega de reports, incluindo arquivos previamente preparados
que foram relidos/verificados e preservados. Arquivos de PR0/PR1/UI fora desta lista não
fazem parte do ownership. Nenhum arquivo novo fora deste manifesto foi criado na workspace.

- `app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb`
- `app/services/email_campaigns/campaign_query.rb`
- `app/services/email_campaigns/presentation/hygiene.rb`
- `app/services/email_campaigns/presentation/import_summary.rb`
- `app/services/email_campaigns/presentation/protection.rb`
- `app/services/email_campaigns/presentation/protection_metrics.rb`
- `app/services/email_campaigns/presentation/protection_provider.rb`
- `app/services/email_campaigns/presentation/recipients.rb`
- `app/services/email_campaigns/recipient_query.rb`
- `app/services/email_campaigns/reports/bounce_outcomes.rb`
- `app/services/email_campaigns/reports/builder.rb`
- `app/services/email_campaigns/reports/csv_export.rb`
- `app/services/email_campaigns/reports/import_issues_query.rb`
- `app/services/email_campaigns/reports/metrics.rb`
- `app/services/email_campaigns/reports/parameters.rb`
- `app/services/email_campaigns/reports/recipient_state.rb`
- `app/views/api/v1/accounts/email_campaigns/reports/clicks.json.jbuilder`
- `app/views/api/v1/accounts/email_campaigns/reports/import_issues.json.jbuilder`
- `app/views/api/v1/accounts/email_campaigns/reports/index.json.jbuilder`
- `app/views/api/v1/accounts/email_campaigns/reports/recipients.json.jbuilder`
- `app/views/api/v1/accounts/email_campaigns/reports/show.json.jbuilder`
- `app/views/api/v1/accounts/email_campaigns/reports/timeline.json.jbuilder`
- `docs/audit/436-reports.md`
- `docs/email-campaigns/reports.md`
- `spec/controllers/email_campaigns/reports_436_spec.rb`
- `spec/services/email_campaigns/presentation/protection_spec.rb`
- `spec/services/email_campaigns/reports/export_and_issues_436_spec.rb`
- `spec/services/email_campaigns/reports/metrics_436_spec.rb`
- `spec/services/email_campaigns/reports/presentation_436_spec.rb`
- `spec/services/email_campaigns/reports/recipient_query_436_spec.rb`

Novos nesta finalização: protection.rb, protection_metrics.rb, protection_provider.rb e
presentation/protection_spec.rb. Nesta rodada também foram editados ReportsController,
CampaignQuery, Hygiene, Reports::Builder/BounceOutcomes/Metrics, index.json.jbuilder, as
specs reports de metrics/presentation/recipient_query, a spec do controller e os dois docs.
Os demais caminhos listados foram preservados e incluídos na validação estática.

Issue #436 → branch/worktree existente → PR2/Project update/review permanecem com o parent.
Nenhuma revisão independente foi executada aqui; não foram usados subagentes.
Approval → merge → deploy continuam separados e dependem do Rodrigo. Rollback: reverter
somente a integração PR2 após aprovação; o recorte é de leitura e não introduz migração
nem mutação de dados para desfazer. PR1 e suas migrações têm plano próprio.

### Resultado final das verificações estáticas desta finalização

- `ruby -c`: **28/28 arquivos, Syntax OK**, exit 0, após todas as alterações Ruby/Jbuilder.
- RuboCop final, sem autocorreção: **28 arquivos, zero ocorrência**, exit 0.
- `git diff --check -- <ownership>`: sem diagnóstico. Como Git não inclui arquivos novos
  não rastreados no diff, verificação adicional por Python cobriu **30 arquivos** do manifesto
  (incluindo os dois docs e untracked): zero linhas com whitespace ao final, exit 0.
- Revisão própria por leitura concluída; **nenhum RSpec executado**, nenhum resultado de
  integração/SQL/HTTP inferido de lint ou sintaxe.

Comando final de lint executado:

```sh
eval "$(rbenv init -)"
RUBOCOP_CACHE_ROOT=/private/tmp/436-reports-rubocop bundle exec rubocop app/services/email_campaigns/presentation app/services/email_campaigns/reports app/services/email_campaigns/campaign_query.rb app/services/email_campaigns/recipient_query.rb app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb app/views/api/v1/accounts/email_campaigns/reports spec/services/email_campaigns/reports spec/services/email_campaigns/presentation/protection_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb --format simple
```

Sintaxe: lista ordenada dos mesmos 28 caminhos Ruby/Jbuilder do manifesto, cada um passado
separadamente a `subprocess.run(['ruby', '-c', path])` após init do rbenv; falha interromperia
a verificação com seu código de saída. Nenhum require, boot ou execução de aplicação.

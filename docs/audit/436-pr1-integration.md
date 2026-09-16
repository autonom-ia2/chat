# #436 — integração PR1 reputação sobre PR0 higiene

Data: 2026-09-16. Escopo local delegado, sem commit. PR0 de referência: `406ef3a7de` (`feat(email-campaigns): protect future sends with audited list hygiene`). PR1 consultado no worktree `436-email-reputation`, além dos arquivos aplicados pelo parent e dos lados explícitos dos conflitos. Leitura de `AGENTS.md`, `docs/email-campaigns/hygiene.md`, `docs/email-campaigns/reputation.md`, manifesto PR1 e `tmp/email436/pr1-conflicts.txt`.

## Decisões dos quatro conflitos

| Arquivo | PR0 mantido | PR1 mantido / decisão integrada |
| --- | --- | --- |
| `.env.example` | Bloco completo de higiene, shadow, DNS=false e defaults de quarentena | Bloco completo de reputação, shadow, monitor=false, limites e bloqueio de emergência=false. Nenhum env real alterado ou flag habilitada. |
| `app/models/email_campaign.rb` | Preflight em sendable/resume, import-active fence, finalização protegida por pendentes/import/claims sem recibo; limpeza do motivo de higiene só na transição apropriada | Histórico de entrega, motivo estruturado e retomada via publicação de Guardrail. Coleta de reputação ocorre fora dos locks; publicação account → state → campaign engloba transição. Higiene/import são checados antes e novamente dentro da publicação; falha final lança `EmailReputationBlocked`, revertendo também eventual release da conta. Não retorna sucesso nem enfileira quando higiene falha. Pausa manual recarrega sob lock para não sobrescrever cancelamento concorrente. |
| `app/services/email_campaigns/delivery_engine.rb` | Supressão fresca, preflight, import fence, proteção de estado no rescue, retry apenas de erro SES começando com HTTP 429 explícito | Advisory lock de sessão, proteção por conta/provedor no início/loop/claim e renderização antes do claim final. `DeliveryClaim` concentra a decisão; `Admission.claim!` delega. Só o processo que efetivamente obteve o claim pode tratar falha de envio. 5xx contendo nome de exceção de throttling não vira retry. 429 posterior a cancelamento vira suppressed, não pending. |
| `app/services/email_campaigns/direct_inbox/recipient_sender.rb` | Ignora Set antigo, consulta união de supressões novamente, preflight e registro de entrega sob recipient lock, preservando opt-out | Mesmo claim central e orçamento da conta após renderização. Sem breaker global SES para campanhas direct_inbox. Falha antes do claim não altera destinatário de outro processo; aceite atualiza recibo sem sobrescrever status de opt-out. |

## Fluxo e limites

`DeliveryClaim.prepare` verifica sem reservar destinatário ou gastar override. Os motores renderizam conteúdo, tracking e unsubscribe headers fora dos locks. `DeliveryClaim.claim` repete a elegibilidade, lê dados frescos sem query cache e faz a única transição condicional pending → sent. `Admission.with_delivery_locks` mantém account → state → campaign → recipient; somente consultas locais/escritas curtas, sem métricas agregadas, DNS, HTTP ou SMTP.

A checagem exige destinatário da campanha, status esperado e ausência de recibo anterior; consulta supressão corrente (incluindo quarentena), campanha sending, ausência de import ativo, proteção de conta/provedor e preflight. Override só é consumido na transição final bem-sucedida. Não elimina supressão, higiene ou breaker SES. A assinatura opcional com Set antigo permanece nos dois motores, mas o Set não decide elegibilidade.

`DeliveryClaim.dispatch_allowed?` permanece para compatibilidade com o fluxo antigo e specs PR0: somente a instância dona pode liberar um claim ainda não entregue ao transporte. A autorização é de uso único; uma chamada posterior não libera um envio possivelmente em voo. Nos motores integrados não existe claim antes da renderização. Falhas de render deixam pending sem afetar claims concorrentes. Timeouts/5xx não voltam a pending; falha ao persistir aceite conserva o claim. Aceite confirmado atualiza apenas os campos de recibo, sem apagar opt-out concorrente. Um bloqueio publicado depois da autorização final não pode recolher o envio já admitido.

DirectInbox mantém um destinatário por tick, horário comercial, intervalo aleatório existente, teto diário e auto-pausa. O tick também usa o advisory lock de sessão da campanha; auto-pausa recarrega sob campaign lock e não sobrescreve campanha terminal/manual já pausada. Não foi alterada a configuração desses limites.

Histórico, trigger snapshots, latches de provider, política, coleta/monitor e migrações não foram reescritos nesta entrega. Nenhum overlay Enterprise correspondente apareceu nas buscas locais. Nenhum spec antigo foi removido, pulado ou enfraquecido.

## Regressões adicionadas, pendentes de execução Rails pelo parent

- `spec/services/email_campaigns/delivery_integration_spec.rb`: override com destino não validado; expiração de preflight durante render; bloqueio tenant/provider entre envios; import queued/processing e iniciado durante render; reimportação preservando recibo/histórico/bloqueio; claims concorrentes durante render nos dois motores; opt-out em falha e aceite; 503 com texto de throttling; liberação de claim próprio sem dispatch; impossibilidade de reutilizar autorização já entregue ao transporte; 429 após cancelamento; DirectInbox com higiene/quarentena/tenant e exclusão do breaker SES.
- `spec/services/email_campaigns/resume_integration_spec.rb`: erro público em higiene/import; mudança de higiene durante coleta reverte release e conserva incidente/flag/auditoria; sucesso limpa ambos motivos; provider sticky impede retomada mesmo com monitor off.
- `spec/services/email_campaigns/delivery_integration_concurrency_spec.rb`: duas sessões PostgreSQL, cancelamento antes do claim, exclusão de worker duplicado, transporte sem transação aberta, cancelamento durante request já admitido e preservação de aceite. Não usa fixtures transacionais; cleanup limitado aos registros sintéticos do exemplo e sem remoção de auditorias de reputação.

## Validação executada

Sempre inicializado rbenv antes de comandos Ruby/Bundler: `eval "$(rbenv init -)"`.

1. `ruby -c` nos seis arquivos Ruby de implementação e três specs novos: **9 Syntax OK**.
2. `bundle exec rubocop --cache false` exclusivamente nesses nove arquivos: **9 files inspected, no offenses detected** na execução final. Rodadas anteriores apontaram alinhamento/complexidade; correções limitadas ao escopo. A sequência explícita de guardas de autorização usa uma exceção localizada de complexidade para manter a decisão legível em um único ponto.
3. Processos Ruby separados, sem Rails e com `MT_NO_PLUGINS=1`:
   - `ruby spec/pure/email_campaigns/hygiene_test.rb`: **13 runs, 120 assertions**, zero failures/errors/skips.
   - `ruby spec/pure/email_campaigns/preflight_batch_test.rb`: **4 runs, 50506 assertions**, zero failures/errors/skips.
   - `ruby spec/services/email_campaigns/reputation/policy_test.rb`: **6 runs, 32 assertions**, zero failures/errors/skips.
   - `ruby spec/services/email_campaigns/reputation/provider_config_test.rb`: **2 runs, 18 assertions**, zero failures/errors/skips.
   - Total: **25 testes puros / 50676 assertions**, sem falhas. O teste de transporte usa `Socket.pair` UNIX e resolvers/sockets simulados, sem DNS/rede externa.
4. `git diff --check`: sem erros. Busca de marcadores nos quatro arquivos de conflito e serviços: nenhum marcador restante.

Não executados: Rails, RSpec, banco/migrações, AWS, SSH, SMTP, consultas externas, installs, Git writes, merge ou deploy. Os resultados anteriores de 110 higiene/SES e 89 reputação pertencem às árvores separadas informadas pelo parent; não comprovam esta integração. Os specs novos e os 200+ integrados precisam da execução isolada do parent. Esta entrega não declara PR pronto.

## Pendências concretas fora da propriedade desta entrega

1. **Ordem de locks SNS/EmailEvent:** `app/services/email_campaigns/sns/event_processor.rb:13` mantém recipient lock enquanto cria bounce/complaint. `app/models/email_event.rb:37,49` chama `EvaluationQueue.invalidate`, que adquire state lock dentro da mesma transação. É recipient → state, inverso de state → campaign → recipient na admissão/publicação. Há risco de deadlock, inclusive durante resumir/publicar enquanto feedback segue para atualização do recipient. Parent deve integrar a ordem compartilhada no caminho SNS/feedback e adicionar regressão concorrente; não basta mover invalidation para after_commit, pois perderia a proteção contra observação ultrapassada. Esses arquivos não foram editados por este agente.
2. **Transição inicial do TickJob:** `app/jobs/email_campaigns/direct_inbox/tick_job.rb:11-14` lê scheduled e depois faz `mark_sending!` sem lock/transição condicional. Um cancelamento ou pausa entre leitura e update pode ser sobrescrito antes de entrar no engine protegido. O engine não consegue inferir o estado apagado pelo job. Parent deve mover essa transição para um bloco curto/condicional que recarregue o estado e respeite import ativo. O job não faz parte da propriedade desta entrega.
3. **Schema/triggers:** inteiramente a cargo do outro worker e do parent. Não houve edição em `db/migrate`, schema, `lib/tasks`, `lib/email_campaigns` ou specs de schema por este agente.

Aguardam-se os resultados Rails do parent para qualquer ajuste adicional nos arquivos deste escopo. Sem mudanças de configuração operacional, aprovação de merge ou habilitação de envio.

## Correção após a primeira execução integrada — 2026-09-16

Evidência lida: `tmp/email436/integrated-rspec-first.log`, execução do parent com PostgreSQL local novo após schema-load e migrações: **247 exemplos, duas falhas**. Esta seção substitui as descrições anteriores dos caminhos corrigidos. Não houve execução Rails/RSpec/DB por este agente.

### Causas e decisões

1. **DirectInbox `:sent` esperado / `:skipped` observado:** `PreflightDecision#pause!` faz UPDATE condicional sem atualizar a instância da campanha. A campanha persistida estava pausada, mas a instância ainda tinha `sending` como valor original. O `campaign.update!(status: :sending)` do spec podia não incluir `status` no SQL por não haver mudança segundo o dirty tracking. Não era falha da validade do endereço nem aplicação indevida do breaker SES. `DeliveryClaim` agora recarrega a instância limpa depois de publicar a pausa; `Admission#park!` também sincroniza seu UPDATE condicional. O spec original usa **resume! real**, com publicação e preflight reais, após validar o destinatário. Uma regressão separada cobre a atribuição explícita à mesma instância. Validar o destinatário sozinho continua sem retomar a campanha; supressão, quarentena e proteção do tenant continuam obrigatórias. O breaker global SES continua excluído do modo direto.
2. **Deadlock cancelamento/admissão:** o log mostra `refresh_counters!` esperando `FOR KEY SHARE` em `accounts` enquanto a outra sessão segurava a conta e esperava a campanha. A ordem antiga era campaign → account, oposta à admissão. O teste também adquiria `campaign.with_lock` antes de chamar `cancel!`, forçando essa inversão. O teste agora observa a chamada real a `update!` dentro de `cancel!`; inicia a segunda sessão, verifica PIDs distintos e espera `pg_blocking_pids` confirmar a disputa antes de prosseguir. Não toma previamente um lock de filho e não desabilita nenhum lock.

`Admission#with_campaign_locks` centraliza account → state existente → campaign; `with_delivery_locks` acrescenta recipient. `EmailCampaign#with_delivery_lock` expõe esse bloco para chamadores que ainda precisam ser integrados pelo parent. Nenhum callback genérico de save foi adicionado.

Aplicado dentro da propriedade desta entrega:

- `pause!`, `claim_for_sending!`, `mark_sending!`, `cancel!`, `finalize!` e a escrita de contadores entram no protocolo compartilhado. `mark_sending!` recarrega e só promove scheduled sem import ativo, preservando cancelamento/pausa terminal concorrente. Novo `schedule!(scheduled_at:)` verifica sendable sob o mesmo protocolo, para substituir o bloco antigo do controller.
- `resume!` conserva coleta de reputação fora dos locks e campanha dentro da publicação account → state; erro final de higiene continua revertendo release/flag/auditoria na mesma transação.
- Cancelamento publica `canceled` primeiro, bloqueando qualquer nova admissão. A supressão dos pendentes ocorre em lotes de **100**, cada qual com seu próprio bloco ordenado, seguido da atualização de contadores. Recibos, entregues, opt-outs e claims já admitidos não são suprimidos pela limpeza. Repetir `cancel!` em canceled conclui uma limpeza interrompida. Falha de limpeza/contadores propaga erro, mas não desfaz a barreira já publicada. Há regressões explícitas para essa preservação. `cancel!` retorna `false` se houver import ativo sob lock; retorna `true` para sent/failed já terminais. O controller precisa usar esse resultado sem lock externo, conforme abaixo.
- `refresh_counters!` calcula agregações antes do lock da conta e persiste somente o hash de contadores dentro do bloco curto. `finalize!` muda o estado antes dessa contabilidade. Os contadores continuam sendo um retrato de leitura; não decidem a autorização de envio.
- SES: transição scheduled e tratamento de falha usam o protocolo compartilhado. SES e DirectInbox: persistência do recibo e falha pós-claim seguem account → state → campaign → recipient. DirectInbox registra delivered em bloco ordenado separado da gravação de recibo, preservando o recibo se o evento falhar; mantém opt-out concorrente.
- Render, tracking, headers, coleta agregada, HTTP/SMTP e sleeps ficam fora desses blocos quando invocados sem transação externa. Só a instância que obteve o claim pode tratar falha; aceite ambíguo não volta a pending. Nenhuma proteção de validade foi stubada nem caso convertido para pending/skip.

### Chamadores fora do escopo — integração obrigatória pelo parent

**Não basta envolver um método interno quando o request/job já mantém lock de filho. Esses caminhos ainda não estão corrigidos por esta entrega e impedem declarar a integração concluída.** Leituras refletem o estado local visto nesta rodada; arquivos de outro agente não foram editados.

| Local | Ajuste concreto necessário |
| --- | --- |
| `CampaignsController#cancel` (`campaigns_controller.rb`, bloco `@campaign.with_lock`) | Remover o lock externo e usar diretamente o resultado de `cancel!` para o 422 `import_in_progress`. A checagem de import agora ocorre no modelo sob lock. Envolver o método inteiro em `with_delivery_lock` ainda manteria o lock da conta durante todos os lotes e agregações, anulando o limite de duração. |
| `CampaignsController#schedule` | Substituir o bloco campaign-only por `schedule!(scheduled_at: params[:scheduled_at])`, preservando as respostas existentes para data ausente e campanha não sendable. `send_now` já usa `claim_for_sending!`, agora ordenado. |
| `Scheduler#start` | Entrar em `campaign.with_delivery_lock` **antes** das checagens e de `mark_sending!`; manter enqueue fora. Revisar também o rescue que escreve failed para não sobrescrever estado terminal/manual concorrente. Não deixar campaign-only por fora do novo método. |
| `DirectInbox::TickJob#perform` — propriedade do outro agente | O bloco observado ainda era `campaign.with_lock`. Trocar a entrada para `campaign.with_delivery_lock`, preservando a releitura e checagens de modo, import, horário e status. Não tomar lock de campanha primeiro. |
| `RecipientImporter#import_rows` e `RecipientImportJob` | `refresh_counters!` estava dentro da transação que já inseriu recipients/issues, por sua vez chamada sob `import.with_lock`. Não adquirir conta nesse ponto: publicar/atualizar contadores depois do commit e liberação do import/filhos, conservando o contrato de conclusão e a exclusão do import. Mover apenas para fora da transação interna não basta se o job ainda mantém a externa. |
| `PreflightLease#acquire/#claim/#advance` | Os três blocos ainda eram campaign-only; ordenar antes de escrever campanha ou recipients. `advance` agrega classificações e `acquire(recheck: true)` faz reset em massa: separar coleta/escritas em lotes do lock da conta, usando a lease/token para não publicar resultado ultrapassado. Não envolver DNS nem toda a varredura em lock de conta. |
| `CampaignsController#destroy`, `RecipientsController#create/#destroy` | Entradas campaign-only ainda presentes; ordenar antes de qualquer escrita de filhos ou campanha. Para destruição/import em massa, preservar retenção e fence de import sem manter conta bloqueada durante trabalho longo. |

`SNS`, `EmailEvent`, `TickJob` e seus specs concorrentes continuam de propriedade do outro agente. Na leitura atual, SNS já chama refresh de contadores depois de sair de `with_recipient_feedback_locks`, o que atende à separação exigida; isso é leitura estática, não validação de execução. Métodos de geração de IA e CRUD não relacionados não receberam callback global de locking; parent deve revisar qualquer nova transação externa nesses caminhos antes de colocá-los sob a mesma publicação.

### Revisão de callbacks, dirty tracking e falhas

- As mudanças de atributos ficam **dentro** de `with_lock`; nenhum `before_save/around_save` chama reload ou lock!. `with_lock` rejeita objetos com mudanças não persistidas, em vez de apagar conteúdo silenciosamente. Regressão conserva `campaign.changes` e `body_mjml` se essa rejeição ocorrer.
- Reload após pausa por SQL ocorre somente na instância limpa já protegida. Nenhuma decisão nova depende de `saved_change_to_*` ou `previous_changes` depois desse reload. A gravação normal continua usando os callbacks de validação existentes; a sanitização de MJML não é forçada nas transições de status.
- Recibo pós-envio atualiza apenas campos de recibo; nunca restaura status sobre opt-out. Falha de gravação conserva claim e impede segunda chamada ao transporte. Falha de contadores ou limpeza de cancelamento não reabre envio. Resume com falha de higiene continua atômico com a publicação de reputação.

Regressões nos mesmos três arquivos novos: caso DirectInbox original com retomada real; classificação persistida após pausa; aceite sem recibo; opt-out no aceite direto; disputa real cancelamento/claim; ordem SQL de pausa/cancel/send-now/schedule/mark-sending/finalize; dados não salvos; falha de contador; limpeza interrompida e retomada; fence de import no cancelamento; agregação de contadores antes do lock da conta. Nenhum spec anterior foi removido ou enfraquecido.

### Validação desta rodada

Comandos Ruby inicializados com `eval "$(rbenv init -)"`. Escopo: modelo de campanha, Admission, DeliveryClaim, dois engines, RecipientSender e os três specs de integração (nove arquivos Ruby).

- `ruby -c` nos nove arquivos: **9 Syntax OK**.
- `bundle exec rubocop --cache false` nesses nove arquivos: **9 files inspected, no offenses detected**. Correções automáticas limitadas a alinhamento nos dois specs; uso de `described_class` corrigido manualmente.
- Processos independentes com `MT_NO_PLUGINS=1`: higiene **13 / 120 assertions**, preflight batch **4 / 50506**, policy **6 / 32**, provider config **2 / 18**. Total **25 testes / 50676 assertions**, sem failures/errors/skips. Sem Rails; teste de transporte usa apenas `Socket.pair` UNIX e substitutos locais, sem tráfego de rede.
- Revisão estática de locks/callbacks/overlays e preservação de escopo. Não executado `git diff --check` nesta rodada, pois o parent proibiu todo uso de Git.

**Pronto para reteste pelo parent, não para merge/deploy.** Os 247 exemplos do log continuam sendo a última evidência Rails, com duas falhas; lint e testes puros não provam que o RSpec corrigido passou. Reexecutar os três specs de integração e o conjunto anterior de higiene/reputação após integrar os chamadores externos acima. Não executados Git, DB, Rails, RSpec, rede, SSH, AWS, SMTP, env real ou installs.

# #436 — feedback SNS e transição do tick DirectInbox

Data: 2026-09-16. Entrega local restrita aos dois bloqueios de `436-pr1-integration.md`. Sem Git writes, Rails/RSpec, banco, AWS/SSH/SMTP/rede, instalação ou leitura/alteração de env real. Sem declaração de PR pronto. Execução dos specs fica com o parent, exclusivamente no banco isolado.

## Manifesto exato desta entrega

| Arquivo | Alteração deste trabalho |
| --- | --- |
| `app/services/email_campaigns/sns/event_processor.rb` | Substitui o recipient lock inicial pelo protocolo `EmailEvent.with_recipient_feedback_locks`. |
| `app/models/email_event.rb` | Acrescenta o protocolo explícito para gravação composta e documenta o contrato do callback. Preserva os callbacks de invalidação/enqueue já presentes na árvore inicial. |
| `app/jobs/email_campaigns/direct_inbox/tick_job.rb` | Faz a checagem e promoção sob `with_delivery_lock`, retorna quando inelegível e chama o engine depois do commit. |
| `spec/services/email_campaigns/feedback_integration_concurrency_spec.rb` | Novo: concorrência de feedback/admissão/publicação/replay, criação inicial de estado, callback direto e eventos sem reputação. |
| `spec/jobs/email_campaigns/direct_inbox/tick_transition_spec.rb` | Novo: cancel/pause/import concorrentes, horário agendado, estados inelegíveis e continuidade de sending. |
| `docs/audit/436-feedback-integration.md` | Este manifesto, decisões, validação e handoff. |

Nenhuma edição desta entrega em delivery, admission, controller, registry, classifier, política, migrações ou schema. Esses arquivos foram lidos. A árvore compartilhada mudou durante o trabalho: o parent acrescentou `Admission#with_campaign_locks` / `EmailCampaign#with_delivery_lock` e passou transições/contadores a usar o protocolo. O TickJob final usa essa API presente, em vez de envolver `mark_sending!` em um campaign lock que inverteria a ordem recém-integrada. O spec de Delivery verifica que o event/recipient é liberado antes da atualização de contadores adquirir a conta. Não reverter essas alterações do parent ao integrar o manifesto.

## Protocolo exato de feedback

- **SNS Bounce/Complaint:** transação curta com `Account FOR UPDATE` → criação/localização de `EmailReputationState` e seu `FOR UPDATE` para SES → `EmailCampaign FOR UPDATE` → `EmailCampaignRecipient FOR UPDATE`. O estado é criado antes do recipient lock, inclusive sua checagem de FK de conta. Leituras nesse bloco ficam sem query cache.
- O dedup por recipient/tipo acontece depois desses locks, antes de salvar evento, invalidar geração ou registrar ocorrência. Payload original, classificação oficial, supressão permanente/opt-out, precedência de status, recibo e preflight mantêm o comportamento existente. Escritas do registry ocorrem com a conta já travada, inclusive FKs de supressão nova. Não há try-lock, descarte silencioso ou liberação automática de histórico.
- A invalidação de todo Bounce/Complaint SES, inclusive classificação de prevenção, continua em **before_save**, na mesma transação do evento. Correções de payload/tipo continuam cobertas pelo predicado existente. O pós-commit apenas solicita avaliação; não é a única proteção contra uma observação antiga. Contadores são atualizados após sair dos locks do processamento.
- **SNS Delivery:** mantém apenas recipient lock na escrita do evento/status; não precisa de estado/registry. O lock é liberado antes de atualizar contadores. Não cria estado de reputação por causa de Delivery.
- **EmailEvent avulso:** mantém o callback original antes da escrita e antes da FK do evento para recipient. Não introduz `Account.with_lock` genérico no callback. Um escritor composto de Bounce/Complaint que também precisa travar campaign/recipient deve entrar em `with_recipient_feedback_locks` **antes** desses locks; o callback sozinho não conserta uma ordem já invertida pelo chamador. O wrapper não deve ser chamado de dentro de um recipient lock.
- Eventos avulsos `open`, `click`, `unsubscribe` e eventos DirectInbox não passam a adquirir conta/estado no callback. O teste de callbacks avulsos não representa uma execução completa do controller de unsubscribe.

Sem consultas ao provedor, DNS, envio, renderização ou agregação de reputação sob os locks acrescentados. Classifier e SQL de métricas não foram modificados: NoEmail continua genérico; Suppressed global continua nocivo com motivo provider_suppression; OnAccount/OnTenant/EmailValidation continuam prevenção; UnsubscribedRecipient continua opt-out.

## Tick DirectInbox

O job entra em `campaign.with_delivery_lock` (account → estado existente → campaign, com reload) antes de conferir modo e status. Aceita `sending` existente; só promove `scheduled` com data presente e vencida. Import queued/processing impede promoção e tick. Pausa/cancelamento/estado terminal que venceram a disputa permanecem intactos. O update scheduled → sending fica dentro desse mesmo bloco, sem chamar uma transição que volte a adquirir locks de pais a partir de um campaign lock isolado.

O engine só é construído/chamado após o bloco retornar elegível e a transação terminar. Caminhos recusados não enfileiram um novo tick. Horário comercial, teto diário, intervalo, provider e auto-pausa continuam no engine existente e não foram alterados.

## Regressões preparadas; ainda não executadas

Os dois arquivos novos desativam fixtures transacionais, usam threads com checkout explícito de conexões e verificam PIDs PostgreSQL distintos. Barreiras de corrida usam Queue e `pg_blocking_pids`, não presumem que uma thread chegou ao lock após um sleep. A pequena espera no polling só aguarda a condição real. Esperas têm limites e workers são encerrados no cleanup; erros de worker são propagados por `value`. Os dados são sintéticos por conta; cleanup não apaga auditorias append-only.

Feedback:

- Admissão primeiro, SNS depois, com estado existente e com primeiro estado ainda ausente; mesmo destinatário, sem perder evento/status/recibo/preflight.
- SNS primeiro e claim posterior de outro envio ao mesmo endereço: supressão ganha e não aparece recibo novo.
- Publicação/retomada ganha a conta enquanto SNS espera; o feedback posterior invalida a observação publicada.
- Coleta da retomada fica suspensa sem locks; SNS faz commit; publicação antiga é recusada, conservando pausa, incidente e ausência de release.
- Dois replays SNS simultâneos: um evento, uma versão, uma ocorrência e um resultado de recipient.
- `EmailEvent.create!` avulso cria o primeiro estado antes de sua FK de recipient; evento e versão já são visíveis enquanto o enqueue pós-commit está suspenso.
- Callbacks de tracking/opt-out não procuram conta/estado com recipient já travado; Delivery confirma commit do status antes do lock de conta dos contadores.
- Chamadas ao enqueue capturam `open_transactions` e são verificadas como zero.

Tick:

- Leitura inicial anterior ao cancel/pause concorrente, espera real de lock e resultado sem sobrescrever estado, chamar engine ou reagendar.
- Import queued/processing iniciado entre leitura e claim; sending com import ativo também não chama engine.
- Scheduled vencido promove; sending continua inclusive se a antiga data está no futuro; scheduled futuro/sem data e draft/paused/canceled/sent/failed não iniciam.
- Engine chamado fora da transação da promoção.

## Limite concreto fora do manifesto: unsubscribe por link

Na última leitura, `app/controllers/email_campaigns/unsubscribe_controller.rb#suppress!` ainda entra em `recipient.with_lock` antes de `SuppressionRegistry#block!`. O registry não tem um `Account.with_lock` explícito nessa versão, mas uma inserção nova em `email_suppression_states`/`email_suppressions` verifica a FK para accounts e pode esperar pelo lock da conta. Isso permite recipient → account versus account → recipient da admissão/SNS. Também deve ser considerado se o parent acrescentar um account lock explícito ao registry.

Esse caminho acontece **antes** de criar o EmailEvent de unsubscribe. Alterar seu callback, colocar account lock genérico no save ou invalidar só depois do commit não corrige essa ordem. O parent precisa fazer o controller entrar no protocolo de pais antes de travar recipient/escrever o registry, junto com uma regressão concorrente do endpoint completo. Controller/registry estão expressamente fora da propriedade desta entrega e não foram editados. A cobertura nova de callbacks avulsos não deve ser apresentada como prova de ausência de deadlock nesse endpoint. Este limite impede declarar toda a integração livre de deadlocks.

## Validação local e handoff

Inicializado rbenv antes dos comandos: `eval "$(rbenv init -)"`.

- `ruby -c` individualmente nos cinco arquivos Ruby do manifesto: **5 Syntax OK** na execução final.
- `bundle exec rubocop --cache false` com apenas os cinco caminhos Ruby do manifesto: **5 files inspected, no offenses detected** na execução final. Rodadas anteriores apontaram estilo, complexidade e assertions em hook; corrigidos dentro do escopo. O helper de barreira do tick tem uma exceção local de tamanho/ABC para manter o ciclo de conexão e sincronização junto.
- Não executados Rails/RSpec, testes puros, banco/migrações, providers, rede ou install. Leitura de diff foi somente leitura; nenhum commit, branch, PR, merge ou deploy.

Parent: primeiro executar no banco PostgreSQL isolado atualizado, com pool de pelo menos três conexões:

```sh
bundle exec rspec spec/services/email_campaigns/feedback_integration_concurrency_spec.rb spec/jobs/email_campaigns/direct_inbox/tick_transition_spec.rb
```

Depois incluir os specs existentes `spec/services/email_campaigns/sns/event_processor_spec.rb`, `spec/services/email_campaigns/reputation/feedback_spec.rb`, `spec/services/email_campaigns/reputation/concurrency_spec.rb`, `spec/services/email_campaigns/reputation/metrics_spec.rb`, `spec/services/email_campaigns/delivery_integration_concurrency_spec.rb` e `spec/services/email_campaigns/resume_integration_spec.rb` na validação integrada. Eles cobrem também as correções oficiais de classificação que esta entrega preserva. Esses comandos são handoff, não resultado executado aqui. Resolver o limite do unsubscribe no escopo do parent antes de concluir a revisão de concorrência completa.

# Relatórios de campanhas — épico #436

Implementação de leitura, consultas, apresentação e CSV. Não altera envio, importador,
contadores persistidos, rotas nem decisões de reputação. Não faz DNS, SMTP ou chamadas ao SES.

## Integração pelo responsável principal

Dentro do bloco `resources :reports` existente, adicionar:

```ruby
member do
  get :import_issues
  get 'import_issues/export', action: :export_import_issues
end
```

Endpoints resultantes, sob `/api/v1/accounts/:account_id/email_campaigns`:

- `GET reports` e `GET reports/:id`: resumo/comparação e detalhe.
- `GET reports/:id/recipients`: destinatários filtrados.
- `GET reports/:id/export`: os mesmos destinatários em CSV.
- `GET reports/:id/import_issues`: problemas persistidos do arquivo original.
- `GET reports/:id/import_issues/export`: problemas filtrados em CSV.
- `GET reports/:id/clicks` e `GET reports/:id/timeline`: contratos anteriores preservados.

A autorização existente `EmailCampaignReportPolicy` permanece: `view?` para leitura e
`export?` para CSV. Busca de campanha sempre por `Current.account.id`; outra conta recebe
404 sem conteúdo da campanha. Não foram encontradas extensões Enterprise destes relatórios.
As novas ações passam pela mesma política, inclusive eventuais extensões dessa política.

Serviços públicos reutilizáveis:

```ruby
# campaign obrigatoriamente obtida pelo escopo autorizado da conta.
query = EmailCampaigns::RecipientQuery.new(campaign, q: 'example.org', status: 'failed', problem: 'true', page: '1')
query.call       # ActiveRecord::Relation, todos os filtros, id crescente
query.paginated # página de 50 registros
query.meta      # count/current_page/per_page/total_pages/applied_filters

query = EmailCampaigns::CampaignQuery.new(account: Current.account, params: permitted_filters)
query.call      # relação para Reports e integração posterior no CampaignsController#index
query.options   # todas as campanhas autorizadas da conta; sem q/status/campaign_id

EmailCampaigns::Presentation::Hygiene.new(campaign, actor: Current.user).call
EmailCampaigns::Presentation::ImportSummary.new(campaign).call
```

No endpoint de campanha, o integrador pode atribuir o resultado de `Hygiene` a `preflight`.
Nenhum helper foi inserido no controller/jbuilder de campanhas, que pertencem a outro responsável.
Para detalhe de relatório, o Builder já inclui `preflight` e recebe `actor:` opcional.

## Filtros e significado do status

Destinatários: somente `q`, `status`, `problem`, `page` são lidos. Busca literal, sem
sensibilidade a caixa, em nome/email; `%`, `_` e barra invertida são escapados. Todos os
filtros são combinados antes de contar, paginar ou exportar.

Status bruto: `pending`, `sent`, `delivered`, `opened`, `clicked`, `bounced`, `complained`,
`unsubscribed`, `failed`, `suppressed`. São estados **atuais**, não grupos cumulativos:
um destinatário `clicked` não aparece ao filtrar `delivered`, mesmo com evento de entrega.

Aliases:

- `hard_bounced`, `temporary_bounced`, `unknown_bounced`: somente status atual `bounced`,
  classificados pelo último bounce (`occurred_at DESC, id DESC`). Sem evidência retida,
  um `bounced` entra em `unknown_bounced`.
- `preflight_invalid`, `preflight_review`, `preflight_unknown`: somente pendentes ainda
  não enviados, sem proteção ativa, com esse veredito. O campo legado `status` continua
  sendo `pending`; `preflight_status` identifica o resultado da análise.

`problem=true` significa requerer atenção: bounced de todas as classes, failed,
complained, suppressed, proteção ativa, ou pendente não enviado com veredito diferente
de valid ou evidência valid sem checagem/validade futura. `unsubscribed` e supressão ativa por
`unsubscribe` são excluídos: opt-out é uma escolha legítima, não um endereço inválido.
Revisar proteção não significa recomendar reenvio. `problem=false` seleciona o complemento.
Ausência do parâmetro não restringe. Aceita `true/false/1/0`, inclusive booleanos.

Campanhas: `q` em nome/assunto, `status` ou `campaign_status`, `campaign_id` positivo.
Valores do enum e alias `attention` (`paused` ou `failed`); não infere risco reputacional.
Aliases status/campaign_status conflitantes são rejeitados. `campaign_options` ignora
campaign_id, status/campaign_status e q: contém todas as campanhas do escopo autorizado da conta.
Resumo e comparação usam os filtros; seleção explícita da campanha resolve seu preflight
dentro do escopo autorizado mesmo quando busca/status excluem essa campanha da comparação.

Página: inteiro decimal positivo de 1 a 1.000.000, tamanho fixo 50; página além dos resultados
retorna lista vazia, sem truncar ou recircular. `total_pages=0` para conjunto vazio.
Valores inválidos, arrays/objetos nos filtros escalares e textos acima dos limites retornam
422 JSON: `{"error":"email_campaign.invalid_filter","parameter":"status"}`.
Parâmetros fora da whitelist não alteram a consulta. `q` tem limite 320 caracteres.

`since`/`until`: ausentes ou vazios são aceitos. Valores não vazios recebem 422, pois o
relatório nunca os aplicou e ainda não oferece filtro temporal. A UI atual não os envia.
Não há simulação de uma janela de eventos usando essas chaves.

## Métricas e bases

O escopo é a coorte de destinatários das campanhas selecionadas, com **todos os eventos
persistidos dessa coorte**, inclusive eventos tardios. Não existe janela reputacional móvel
nestes KPIs. O serviço externo de reputação é responsável por ela.

Campos numéricos legados continuam disponíveis: recipients, sent, delivered, opened,
clicked, bounced, complained, unsubscribed, failed, suppressed. `sent` conta destinatários
com `sent_at`, que registra aceitação, mesmo que seu estado atual tenha avançado.
Delivered/opened/clicked/bounced/complained/unsubscribed contam destinatários distintos com
um evento correspondente. Failed/suppressed são contagens de status atual.
`current_status_counts` separa todos os estados atuais; `activity` contém eventos brutos.
Contadores antigos persistidos não são regravados nem usados para estes KPIs.

| Taxa (percentual) | Numerador | Denominador |
| --- | --- | --- |
| open_rate | destinatários com abertura | destinatários entregues |
| click_rate | destinatários com clique | destinatários entregues |
| unsubscribe_rate | destinatários com opt-out | destinatários entregues |
| bounce_rate | destinatários com bounce, todos os modos | aceitos, todos os modos |
| hard_bounce_rate | destinatários aceitos SES com bounce permanente no histórico | aceitos SES |
| complaint_rate | destinatários aceitos SES com complaint | aceitos SES |

A antiga divisão de bounce/complaint por entregues foi removida. `bounce_rate` inclui
classes não permanentes e **não** serve para proteção; usar `hard_bounce_rate` na apresentação
apropriada. O relatório não toma decisões de proteção.

Denominador zero resulta em `null` e `rate_metadata.<taxa>.status=no_data`, nunca em
zero saudável. Cada taxa inclui `value`, `numerator`, `denominator`, `basis`, `status`.
Comparação de campanhas traz as taxas **planas** (`open_rate`, `click_rate`,
`hard_bounce_rate`, `unsubscribe_rate`, `bounce_rate`, `complaint_rate`) e também em `rates`,
calculadas pelo mesmo serviço do resumo.
Numeradores cumulativos podem exceder a base de entregas se faltarem eventos de entrega;
a aplicação não inventa eventos nem limita artificialmente a taxa a 100%.

`reputation_coverage` contém somente os aceitos SES das campanhas selecionadas, suas
classes de bounce e complaints, `excluded_direct_sent`, bases e taxas. Campanhas direct_inbox
não diluem essa taxa. `official_ses_ratio=false`: complaint local é uma aproximação e não
reproduz o denominador oficial de reputação do SES. Este objeto não equivale à saúde de toda
a conta e não pode ser usado como substituto de `protection`.

Classificação do bounce usa **exclusivamente** `EmailCampaigns::BounceClassifier.call`.
Na lista/filtro, usa o último evento por occurred_at/id. No KPI, SQL agrupa destinatários
distintos por classe em **todo o histórico**; o CASE deriva dos outputs reais do classificador,
sem copiar uma tabela de resultados. PREVENTED usa diretamente a constante
`EmailCampaigns::Reputation::Metrics::PREVENTED_SQL` do PR1:
`OnAccountSuppressionList`, `OnTenantSuppressionList`, `EmailValidationSuppressed`, `UnsubscribedRecipient`.
Esses eventos contam em provider_prevented, fora dos numeradores permanent/temporary/unknown.
`bounced` legado e `activity.bounce` continuam incluindo notificações de prevenção.

`Permanent/NoEmail` é falha permanente genérica (`permanent_failure`): não prova caixa inexistente.
`Suppressed` global é **permanente**, com motivo `provider_suppression`, nunca mailbox_not_found;
não pertence a provider_prevented. `UnsubscribedRecipient` preserva o motivo `unsubscribe` na lista.
Um destinatário pode ter classes diferentes em eventos históricos e aparece uma vez em cada
classe; somá-las não produz o total de pessoas. Um evento de prevenção posterior não apaga
um bounce permanente anterior. Status bounced sem evento só vira unknown na lista, sem inventar KPI.

Aliases numéricos da UI: `permanent_bounced`, `temporary_bounced`, `unknown_bounced` são
iguais aos campos preservados `permanent_bounces`, `temporary_bounces`, `unknown_bounces`,
em summary, campaigns e detalhe. As taxas continuam percentuais; contadores não mudam de unidade.

**Direct inbox:** o sender existente grava um evento chamado delivered na aceitação pelo
SMTP/Graph. Preservamos esse contador/denominador legado, mas isso não comprova entrega ao
servidor destinatário. `delivery_evidence` separa `provider_confirmed` (eventos delivered de
campanhas SES), `direct_acceptance_only` e `legacy_delivered_includes_acceptance`. Os campos
planos adicionais são `provider_confirmed_delivered` e `direct_acceptance_events`.
O parent deve usar essa evidência/rótulo na UI e manter a explicação da aceitação; não
apresentar os eventos sintéticos de direct inbox como confirmação real de entrega.
A basis de open/click/unsubscribe explicita `legacy_delivered_events_including_direct_acceptance`.

O Builder carrega campanhas uma vez e usa três agregações para todo o escopo: destinatários,
eventos (bruto + distinto) e histórico de bounces distinto por classe. Quantidade de consultas
não cresce por campanha/métrica. A consulta adicional de opções não recalcula KPIs.

O detalhe mantém arrays legados `opened` e `clicked` (até 100 pessoas), e acrescenta
`opened_count`/`clicked_count` numéricos. Nenhum payload bruto do provedor, custom_data ou
last_error é serializado. `clicks_by_url` mantém `total_clicks` e `unique_clicks`; não afirma
que houve clique humano. O timeline mantém atividade bruta, origem em **created_at**, nunca
sent_at de conclusão, e limite inferior de 30 dias.

## Higiene e problemas de importação

Dependências reais do trabalho A: campos preflight dos destinatários; `EmailSuppression`
legado somente com positivos permanentes, **sem** active/expires_at; `EmailSuppressionState.blocking`
para novos estados; associações de imports/issues; `EmailCampaignImportIssue`
com `row_number`, **`raw_address`**, `reason_code`, `suggestion`; `HygieneConfig`,
`BounceClassifier`, métodos `terminal?` e `recipient_import_active?` da campanha.
Não há chamada a classes hipotéticas. As migrações correspondentes são responsabilidade do integrador.

`RecipientState` usa subconsultas SQL com UNION dos emails legados e novos bloqueantes,
sempre limitados à conta da campanha. Para opt-out, a presença legada prevalece sobre o
motivo novo, como em `EmailSuppression.blocking_reasons_for`: unsubscribe legado continua
opt-out com estado temporário ativo, inativo ou expirado. Status unsubscribed também é opt-out.
O scope real `EmailSuppressionState.blocking` só aplica expiração ao motivo temporary_failure;
um motivo forte ativo continua bloqueante mesmo com expires_at antigo. Não se carrega um
Set de até 50 mil emails para estes filtros.

`Presentation::Recipients` chama `blocking_reasons_for(account, emails)` a cada lote:
duas consultas limitadas aos emails do lote, com prioridade legada. Motivo legado não
reconhecido sai como `legacy_suppression`, sem texto livre. Lote vazio retorna imediatamente,
sem consulta nem `IN (NULL)`. Associação account é lida na campanha, nunca em cada destinatário.

`Hygiene#call`:

- `counts.total` = destinatários atuais **ainda não enviados**, particionados em ready,
  protected, invalid, review, unknown, unchecked. A soma das seis parcelas é total.
- `historical_sent` separado; `recipients_total = counts.total + historical_sent`.
  Um destinatário já enviado nunca é chamado de ready.
- Proteção ativa/status protegido tem prioridade. Ready exige pending, valid, preflight_checked_at e validade futura.
  Valid expirado, sem checagem ou sem validade é unchecked; falha não enviada sem proteção é unknown.
- `preflight_valid_until=null` não significa prazo vencido para qualquer veredito:
  dns_disabled permanece unknown; typo permanece review; falha de formato permanece invalid.
  Unknown não fica ready e não é descartado. A seleção de trabalho é do job de higiene;
  reports não agenda, invalida ou força rechecagens globais. No código lido, `PreflightLease`
  e `RecipientPreflightJob.due` implementam o contrato (não há classe `PreflightRun`). Com DNS
  desativado, due seleciona unchecked; com DNS ativo inclui dns_disabled e TTL vencido.
  TTL nulo de formato/typo não vira rechecagem periódica.
- `issues_count` refere-se às linhas originais com problema de todos os imports, podendo
  sobrepor destinatários existentes (por exemplo, suppressed). Não somar aos destinatários.
- `validation_coverage` informa ready/total dos não enviados, sem afirmar validação histórica.
- `shadow`/`warning`: `analysis_only=true`, nenhum bloqueio por preflight é afirmado.
  Supressões já ativas continuam sendo proteção real, independentemente do modo de análise.
- `can_recheck` exige actor administrador da mesma conta, campanha não terminal e sem import ativo.
  Sem actor, false. Não concede autorização ao endpoint de escrita; ele mantém sua própria política.

Import issues: filtros `q` literal em raw_address, `reason` (alias reason_code) e page.
Reason aceita código de máquina com letras minúsculas, dígitos e `_`, até 100 caracteres;
código desconhecido válido retorna zero linhas. Motivos conflitantes são 422.
JSON oferece raw_email e alias email para a UI, classification, id, row_number, reason_code,
suggestion. Classification deriva apenas dos motivos atuais do importador (duplicate,
suppressed, invalid_email, blank_email, invalid_recipient). `invalid_recipient` vira **review**:
um nome acima de 255 caracteres não transforma email válido em inválido. Motivos futuros ficam unknown.
CSV mantém row_number/raw_email/reason_code/suggestion, com a mesma consulta da tela.

`import_summary` é o import mais recente da campanha, independente dos filtros da lista:
id, status real, completed_at, error_code, result restrito a imported/duplicates/invalid/suppressed/total,
preflight restrito a status/unchecked/issues e razões agrupadas desse import. Denominador é
`result.total` original; ausência fica null. Sem import, import_summary=null. `preflight`
separado expõe modo e status da higiene atual; não confundir snapshots da importação com
validação atual. Não se expõem storage keys ou JSON arbitrário do import.

## Exportação

UTF-8 com BOM. Preserva as primeiras oito colunas id/name/email/status/attempts/last_event_at/
opens/clicks. Acrescenta delivery_outcome/reason_code/preflight_status/preflight_reason/
preflight_suggestion/suppression_reason/sent_at.

Sem teto silencioso de 10.000: Enumerator faz paginação por ID, até 500 registros por lote.
Cada lote agrega opens/clicks, busca último bounce e motivos bloqueantes das duas tabelas da conta. Nenhuma
lista completa de destinatários/eventos é materializada. Não aplica page ao CSV.
O maior ID filtrado é capturado antes dos headers; novas importações além desse ID não entram.
É uma leitura progressiva: atualizações/deleções concorrentes ainda podem mudar filtros ou
valores entre lotes; não promete um snapshot transacional. Não mantém transação aberta durante
transferência. A integração deve verificar buffering de middleware/proxy com response_body
Enumerator; X-Accel-Buffering=no é enviado, sem adicionar infraestrutura.

Todas as células textuais recebem neutralização de `= + - @`, inclusive após espaços ou
caracteres de controle. CSV cuida de aspas, vírgulas e quebras de linha. Validação de filtros,
autorização e captura do horizonte ocorrem antes dos headers para erros conhecidos retornarem
JSON 422/403/404. Erro de infraestrutura após começar o stream não pode trocar CSV por JSON.

## DTO público de proteção e integração obrigatória do parent

`GET reports` já retorna `payload = {summary,campaigns,campaign_options,applied_filters,
protection,preflight,meta}`. `meta = {count,applied_filters}` descreve a comparação sem
paginação. `preflight=null` sem seleção autorizada; proteção continua sendo da conta.
O Builder memoiza **uma** apresentação de proteção por index, fora do loop de campanhas.
`GET reports/:id` inclui protection/preflight e preserva os arrays opened/clicked antigos.

```text
{state, reason_code, mode, scope:'account', release_eligible,
 current:{sent, permanent_bounces, temporary_bounces, unknown_bounces, complaints,
          hard_bounce_rate, complaint_rate, evaluated_at, window_start, window_end},
 trigger:{at, reason_code, metrics}, provider:{state, observed_at},
 capabilities:{reevaluate, resume, override}, domains}
```

Fontes reais, lidas do PR1 em `../436-email-reputation` sem escrita:
`EmailReputationState`, `Reputation::Policy`, `LegacyDecision`, `ProviderConfig`, `ProviderGate`,
`EmailProviderState`. Não se chama Metrics, Observation, Evaluator, ProviderMonitor,
Guardrail.evaluate!/reevaluate!/resume!, DNS, AWS ou qualquer rede no GET. Não se chama
`for_account`, que pode criar estado. Leitura do estado da conta e associação administrativa
uma vez por instância; provider gate faz uma busca pontual e, quando necessário para exibir
telemetria, mais uma busca pontual. Leitura SuperAdmin é memoizada. Nenhuma consulta de
reputação cresce com o número de campanhas/destinatários. Hygiene da seleção tem suas
agregações próprias; GET não realiza recheck nem writes.

Mapeamento persistido → público:

- level warning → state attention; healthy/attention/high_risk/unknown mantidos; latch
  blocked ou flag legado → paused, mesmo quando a avaliação atual já permitir release.
  Ausência/zero sent → unknown se não houver latch. Level persistido não reconhecido
  levanta erro, sem fabricar saúde ou esconder divergência de schema.
- `current_metrics.sent/permanent/transient/unknown/complaints` → contadores de current;
  permanent_ratio/complaint_ratio são multiplicados por 100 **somente no DTO** (até quatro
  casas). `0.025 → 2.5`; valores ausentes/base zero → null. `cohort_start/end` → window_start/end.
  `evaluated_at` vem da coluna de avaliação, nunca da data do trigger. Métricas são a
  coorte local SES de sete dias, inclusive quando a campanha selecionada é direct inbox.
- trigger_snapshot.triggered_at/code/metrics → trigger.at/reason_code/metrics. É uma
  allowlist; não reutiliza métricas atuais nem altera o snapshot. Trigger ausente → null;
  métricas de trigger ausentes mantêm valores null. Histórico permanece após release.
- `reputation_paused/reputation_threshold/legacy_pause → reputation`,
  `permanent_failures → hard_bounce_rate`, `complaints → complaint_rate`.
  Gate que bloqueia → provider_blocked. `manual/manual_pause/user → manual` apenas para
  o motivo da campanha (`Protection.pause_reason(campaign)`), sem atribuir pausa manual à conta.
  Motivos desconhecidos → unknown, sem mensagens livres. JSON de pausa `{kind,code}`
  precisa passar por esse normalizador no Jbuilder de campanhas.
- provider healthy exige monitor ligado e observação healthy recente. Gate nil não
  prova saúde: monitor off/ausente com política allow → unknown. Unknown com política
  block, latch ou bloqueio manual → blocked. Direct inbox → not_applicable e ignora
  **somente** o gate SES; mantém proteção da conta. Se monitor off ou unknown_action=allow
  permitir envio, isso não veta release por si só, mas nunca aparece como healthy.
- domains=[]: o PR1 não persiste métricas de domínio; não inferimos domínios nem pontuação
  a partir de destinatários/from_email. Nenhum ID de conta AWS, razão de operador, actor,
  override/budget, política interna, fingerprint ou dados de outra conta são serializados.

### Release reputacional e retomada manual

O parent informou que o produtor já publica `current_metrics.evaluation_generation`
no CAS bem sucedido do Evaluator. O adapter continua exigindo esse marcador para release
reputacional. Não preencher o marcador retroativamente copiando a geração atual; apenas
uma observação realmente publicada pode fornecê-lo. C/Evaluator não foi alterado aqui.

`release_eligible` exige simultaneamente: avaliação não futura nem mais antiga que a janela
de sete dias; level conhecido e diferente de unknown; marcador inteiro positivo igual a
observation_generation; evaluated_feedback_version == feedback_version; contagens completas
não negativas; current_metrics.resume_allowed estritamente true; snapshot da policy igual
à configuração atual; métricas aprovadas pela **Policy real** (e LegacyDecision em shadow/warning);
ProviderGate sem bloqueio. Ratios internos continuam frações. Override ativo não substitui
nenhuma dessas evidências. Esse sinal não limpa blocked nem transforma paused em healthy.
Um novo feedback/uma nova geração invalida o release até uma nova publicação consistente.

`capabilities.resume` distingue dois caminhos, ambos com campanha paused, autorização
EmailCampaignPolicy de update/resume, actor/membership administrativa da mesma conta,
provedor permitido, nenhum import ativo e higiene válida:

- Conta protegida (`state.blocked` ou flag legada da conta): exige `release_eligible=true`.
- Conta sem bloqueio: a pausa da campanha pode ser retomada sem amostra mínima SES, sem
  estado de risco e sem marcador de geração. `release_eligible` pode permanecer false;
  isso não torna a conta/provedor desconhecidos em saudáveis.

Higiene exige DTO Hash com modo igual à configuração real e contagens inteiras não negativas
reconciliadas entre ready/protected/invalid/review/unknown/unchecked. Ausência, inconsistência,
lista vazia ou somente protegidos nega resume. O adapter aplica `PreflightDecision#campaign_allowed?`:
shadow/warning não acrescentam enforcement de DNS; enforce exige validação fresca de todos
os pending, como o backend atual. Em enforce o DTO também precisa de ready positivo.

Uma consulta EXISTS adicional prova que há pelo menos um pending não enviado, sem
ses_message_id preenchido e sem supressão ativa/legada, usando `Reports::RecipientState`.
Em enforce esse candidato também precisa pertencer a ready_ids (valid, checked_at presente,
valid_until futuro). Contagens prontas não substituem essa prova: linhas já enviadas ou
ambíguas não permitem retomada. Nenhum destinatário é carregado em memória ou alterado.
No máximo dois EXISTS de destinatários por campanha (decisão comum em enforce + candidato),
além da consulta de import ativo e das leituras de higiene/provedor/autorização existentes.

Direct inbox ignora somente o gate do SES. Uma pausa manual sem bloqueio da conta pode ser
retomada sem amostra SES. Conta protegida continua exigindo release. Monitor desligado ou
unknown permitido pela configuração aparece como unknown; bloqueio explícito ou latch do
provedor continua vetando campanhas SES. Administrador da conta não é SuperAdmin: override
só é anunciado com ambas as autorizações e não substitui os requisitos de resume.
Sem campanha selecionada, capabilities são false.

### Wiring de campanha e POSTs pelo parent; contrato da UI

1. Preservar o marcador já publicado pelo PR1 ao integrar e rodar a suíte local. Instanciar o adapter por **request**,
   nunca singleton global nem reutilizado antes/depois de uma mutação:

   ```ruby
   preflight = EmailCampaigns::Presentation::Hygiene.new(@campaign, actor: Current.user).call
   protection = EmailCampaigns::Presentation::Protection.new(account: Current.account, actor: Current.user)
                                                      .call(campaign: @campaign, preflight: preflight)
   # No Jbuilder da campanha, mantendo os campos antigos:
   json.pause_reason EmailCampaigns::Presentation::Protection.pause_reason(@campaign)
   json.preflight preflight
   json.protection protection
   ```

   A campanha deve vir de `Current.account`/policy scope. O adapter também rejeita conta
   divergente. Na lista, preparar contexto da conta uma vez fora do loop; não coletar métricas
   por campanha. Capacidades/higiene de uma seleção não devem ser copiadas para outras campanhas.
2. Autorizar `POST campaigns/:id/reevaluate` e `recheck` com a política administrativa da
   campanha, usando somente a conta/campanha autenticadas. Reevaluate executa o serviço real
   de avaliação; recheck agenda/invalida conforme o serviço de higiene real. Nenhum deles libera
   a pausa. Após a operação, reload da campanha/conta e **nova** apresentação, respondendo
   `{payload: <campanha atualizada com id,status,pause_reason,protection,preflight>}` via show.
   O PR1 lido ainda retorna `{protection: <payload interno>}` em reevaluate: esse retorno deve
   ser substituído, não repassado ao cliente. Resume também retorna o mesmo DTO atualizado.
3. POST resume continua validando política, higiene e provider no serviço transacional real;
   para conta protegida, também geração/feedback/release. Pausa manual sem bloqueio não deve
   adquirir a exigência reputacional de amostra mínima. O DTO é orientação visual; jamais aceitar release_eligible do cliente
   ou usá-lo como autorização persistida. A elegibilidade pode mudar após o GET.
4. Na UI, a retomada deliberada de uma conta ainda paused exige **ambos**
   `protection.release_eligible === true` e `protection.capabilities.resume === true`, além
   de campanha paused e ausência de provider blocked/paused/disabled. Não remover o veto do
   provider. O helper agora permite esse caso estritamente com os dois flags, mantendo o
   título de pausa e seu trigger. Clique/erro de API não alteram o estado: apenas o payload
   de um POST bem sucedido atualiza o painel. Retorno ainda paused continua exibindo pausa.
   Pausa manual com conta não bloqueada usa capabilities.resume, sem exigir release_eligible.
   DTO ausente/incompleto ou estados desconhecidos fora do contrato negam a ação; não há
   fallback baseado somente no motivo manual. Provider unknown é um estado válido quando
   a política do servidor permite; provider ausente não é prova de permissão.
5. Preservar filtros e APIs de lista/CSV. `campaign_options` vem do campo próprio sem aplicar
   filtros locais. Os aliases de razões reais para a UI estão abaixo. Erros de configuração,
   avaliação substituída e códigos novos permanecem genéricos seguros; nunca exibir exception
   message, last_error, payload interno, detalhes AWS ou dados do operador.

## Diferenças exatas para o adapter C/principal

A correção de resume altera somente o helper da UI e seus testes focados; traduções são
preservadas. Painel, Health e página já consomem esse helper sem alteração de seus módulos.
O contrato de integração permanece:

- `campaigns[].open_rate/click_rate/hard_bounce_rate/unsubscribe_rate`: já disponíveis como
  número percentual ou null, além de rates aninhadas; nenhuma conversão necessária.
- `reevaluate`/`recheck`: devolver `{payload: <campaign com protection e preflight>}`.
  `EmailCampaignHealth` também aceita `payload.campaign`, mas testes de C usam payload direto.
  Essas actions/rotas e o wiring da apresentação no endpoint de campanhas pertencem ao principal.
- `preflight.counts.total`: seis categorias dos não enviados; duplicate é opcional para C
  e permanece ausente aqui. Não somar issues nem histórico enviado às categorias.
- `preflight.status='blocked'`: já alinhado ao alias blocked→protected de EmailHygieneSummary.
  `no_data` continua desconhecido. Unknown DNS permanece unknown/review, sem ready.
- `classification='review'` para invalid_recipient já corresponde ao badge review de C;
  a razão precisa ser mapeada para review, nunca para invalid.
- `reasonKey` de C ainda não mapeia vários códigos reais. Mapeamentos para suas chaves
  **já existentes**: unsubscribe→unsubscribed; temporary_failure/mailbox_full→temporary;
  permanent_failure→permanent; provider_suppression→provider; invalid_email/blank_email/
  unsupported_local_part/nxdomain/null_mx/no_mail_route→invalid;
  invalid_recipient/provider_typo/idn_requires_ascii_domain→review.
  legacy_suppression/undetermined_bounce/dns_disabled/mixed_null_mx/dns_* ficam unknown.
  Não converter supressão do provedor em caixa inexistente, nem unknown em endereço inválido.
- Filtro de atenção de C já envia problem=true e omite status; problem=false na API significa
  complemento, mas o cliente atual omite false intencionalmente. A ausência continua sem filtro.
- `import_issues/export`: action e exportador prontos aqui, rota ainda depende do principal.
  O cliente C atual envia apenas page nos issues; backend já aceita q e reason/reason_code.
- Timestamps de atributos permanecem objetos Time no serviço e viram strings ISO no Jbuilder;
  CSV converte explicitamente com iso8601. Não usar `String#iso8601` para datas já serializadas.
  Timeline usa group/count tipado pelo ActiveRecord; spec de controller adicionada para verificar bucket ISO.
- `since/until` não vazios agora retornam 422 explícito. É uma mudança visível em relação
  ao antigo aceite silencioso, **não** suporte a janela temporal completa.

## Exemplo sintético de destinatário

```json
{
  "id": 123,
  "name": "Contato exemplo",
  "email": "contato@example.org",
  "status": "bounced",
  "attempts": 1,
  "last_event_at": "2026-09-16T12:05:00Z",
  "sent_at": "2026-09-16T12:00:00Z",
  "opens": 0,
  "clicks": 0,
  "delivery_outcome": "temporary",
  "reason_code": "mailbox_full",
  "preflight_status": "valid",
  "preflight_reason": "mx",
  "preflight_suggestion": null,
  "preflight_valid_until": "2026-09-16T13:00:00Z",
  "suppression_reason": null
}
```

## Validação de integração pendente

Specs novas: `spec/services/email_campaigns/presentation/protection_spec.rb`,
`spec/services/email_campaigns/reports/*436_spec.rb` e
`spec/controllers/email_campaigns/reports_436_spec.rb`. Cobrem isolação, whitelists,
combinações/escapes, aliases, paginação, 10.001 registros CSV, fórmulas, opções independentes,
eventos duplicados/tardios, bases vazias, SES/direct, limite de consultas, higiene e import issues.

**Não executadas nesta worktree**, por restrição explícita. Apenas no ambiente isolado já
preparado pelo responsável principal, após integrar modelos/migrações/rotas:

```sh
eval "$(rbenv init -)"
bundle exec rspec spec/services/email_campaigns/reports/recipient_query_436_spec.rb spec/services/email_campaigns/reports/metrics_436_spec.rb spec/services/email_campaigns/reports/presentation_436_spec.rb spec/services/email_campaigns/reports/export_and_issues_436_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb spec/services/email_campaigns/presentation/protection_spec.rb
```

Verificações de relatórios estão em `docs/audit/436-reports.md`; o contrato final de resume,
manifesto de arquivos e verificações deste recorte estão em `docs/audit/436-resume-contract.md`. Revisão independente,
execução Rails, medição de queries SQL e validação da entrega HTTP do Enumerator continuam pendentes.

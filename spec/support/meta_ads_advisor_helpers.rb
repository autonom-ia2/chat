# O consultor de anúncios (#1110, F5): cenário montado direto no banco, como a coleta (F2a), a ligação conversa →
# anúncio (F2b) e o CRM deixariam. Assinaturas fixas (§6.1 do desenho): a bateria de cenários-gabarito
# (`scenarios_spec.rb`) e os specs de PathList e MetaComparison escrevem contra elas.
#
# `advisor_setup` guarda a conta, a conexão, o funil e um atendente em @advisor; os outros ajudantes usam esse
# cenário. Datas são do fuso da conta de anúncios (`ad_account_timezone`), o mesmo do `Panel::Report`.
module MetaAdsAdvisorHelpers
  # A conta "act_9001": a coluna guarda o id sem o prefixo `act_`, como o Setup grava o que vem da Graph.
  ADVISOR_AD_ACCOUNT_ID = '9001'.freeze
  ADVISOR_SALE_CENTS = 100_000
  ADVISOR_QUOTE_CENTS = 150_000
  ADVISOR_NOON = 12

  # → [account, connection]. WhatsApp marcado como destino; funil com etapa de proposta e etapa de venda.
  def advisor_setup(timezone: 'America/Sao_Paulo')
    account = create(:account)
    account.enable_features!('meta_ads_hub')
    connection = create_meta_ads_insights_connection(account, ad_account_id: ADVISOR_AD_ACCOUNT_ID, timezone: timezone)
    connection.update!(destinations: { 'whatsapp' => true })
    user = create(:user, account: account, role: :administrator)
    pipeline, = create_crm_pipeline(account: account, user: user)
    @advisor = {
      account: account, connection: connection, user: user, inbox: create_crm_inbox(account: account), pipeline: pipeline,
      quote_stage: advisor_stage(account, pipeline, 'Proposta', 'opportunity', 1),
      sale_stage: advisor_stage(account, pipeline, 'Venda', 'negotiation', 2), adsets: {}
    }
    [account, connection]
  end

  # Um total por período, espalhado por igual entre os dias; o resto da divisão vai para o último dia. Soma ao que
  # o dia já tinha, para o mesmo período poder receber gasto e impressões em chamadas separadas.
  # A lista de parâmetros é a assinatura fixa da §6.1, contra a qual a bateria foi escrita.
  def advisor_insights(ad_id:, adset_id:, from:, to:, spend:, impressions:, link_clicks:, conversations_started: 0) # rubocop:disable Metrics/ParameterLists
    advisor_ad(ad_id, adset_id)
    days = (from.to_date..to.to_date).to_a
    totals = { spend: (spend * 100).round, impressions: impressions, link_clicks: link_clicks, conversations_started: conversations_started }
    days.each_with_index do |date, index|
      share = totals.transform_values { |total| (total / days.size) + (index == days.size - 1 ? total % days.size : 0) }
      advisor_insight_day(ad_id, adset_id, date, share)
    end
  end

  # A frequência de 7 dias da Meta (D5.4), com `date_end` como a Meta devolve.
  def advisor_frequency(ad_id:, adset_id:, frequency:, date_end: Date.new(2026, 10, 6))
    advisor_ad(ad_id, adset_id)
    connection = @advisor[:connection]
    Crm::MetaAdFrequencyWindow.create!(account_id: connection.account_id, ad_account_id: connection.ad_account_id, ad_id: ad_id,
                                       adset_id: adset_id, window_days: 7, date_end: date_end, reach: 1_000,
                                       impressions: (1_000 * frequency).round, frequency: frequency, fetched_at: Time.current)
  end

  # → conversas, uma por dia em rodízio de `from` a `to`, às 12h no fuso da conta. Cada uma com o toque de
  # WhatsApp (sem anúncio quando ad_id é nil), a mensagem do cliente no toque e a resposta `reply_after` segundos
  # depois (nil = sem resposta).
  def advisor_conversations(ad_id:, count:, from:, to:, reply_after: 120)
    days = (from.to_date..to.to_date).to_a
    zone = ActiveSupport::TimeZone[@advisor[:connection].ad_account_timezone]
    Array.new(count) do |index|
      day = days[index % days.size]
      advisor_conversation(ad_id, zone.local(day.year, day.month, day.day, ADVISOR_NOON), reply_after)
    end
  end

  # → card ganho na etapa de venda.
  def advisor_sale(conversation)
    advisor_card(conversation, stage: @advisor[:sale_stage], status: :won, value_cents: ADVISOR_SALE_CENTS)
  end

  # → card aberto na etapa de proposta, esperando há `waiting_days` dias.
  def advisor_stalled_quote(conversation, waiting_days: 5)
    waiting = waiting_days.days.ago
    advisor_card(conversation, stage: @advisor[:quote_stage], status: :open, value_cents: ADVISOR_QUOTE_CENTS, last_message_at: waiting,
                               entered_stage_at: waiting)
  end

  # Saídas que não contam como resposta (D5.6): boas-vindas/fora de horário (tipo `template`) e automação.
  def advisor_template_reply(conversation, after:)
    advisor_message(conversation, :template, advisor_first_incoming(conversation) + after, sender: nil)
  end

  def advisor_automation_reply(conversation, after:)
    at = advisor_first_incoming(conversation) + after
    advisor_message(conversation, :outgoing, at, sender: nil, content_attributes: { 'automation_rule_id' => 1 })
  end

  # Uma ação já recomendada, com o que a pessoa fez (aceita, dispensada, aberta ou vencida). Assinatura da §6.1.
  def advisor_resolved(account, kind:, subject_key:, status:, local_date:, ad_id: nil, facts: {}) # rubocop:disable Metrics/ParameterLists
    resolved = %w[accepted dismissed].include?(status.to_s)
    ad_id ||= subject_key.delete_prefix('ad:') if subject_key.start_with?('ad:')
    Crm::MetaAdvisorAction.create!(account_id: account.id, local_date: local_date, kind: kind, subject_key: subject_key, status: status,
                                   ad_id: ad_id, position: 1, facts: facts, shown_at: Time.current,
                                   resolved_at: (Time.current if resolved), resolved_via: ('panel' if resolved))
  end

  # O consultor sem IA e sem cache: Facts → History → Rules → today → Decision (§6).
  # → { rules: { "<regra>" | "<regra>:<ad_id>" => status }, actions: [[kind, ad_id, status]] }
  def advisor_evaluate(connection)
    local_date = connection.ad_account_today
    Redis::Alfred.delete(advisor_facts_key(connection, local_date))
    facts = Crm::MetaAds::Advisor::Facts.new(connection, now: Time.current).payload
    rules = Crm::MetaAds::Advisor::Rules.evaluate(facts, history: advisor_history(connection.account_id, local_date))
    actions = Crm::MetaAds::Advisor::Decision.for(facts, rules, today: advisor_today(connection.account_id, local_date))
    { rules: rules.to_h { |rule| [advisor_rule_key(rule), rule[:status].to_s] },
      actions: actions.map { |action| [action[:kind].to_s, action[:ad_id], action[:status]&.to_s] } }
  end

  private

  def advisor_stage(account, pipeline, name, type, position)
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: name, position: position, metadata: { 'funnel_stage_type' => type })
  end

  # O nome do anúncio no cache de objetos, como o NameResolver deixaria (a ação mostra `ad_name`).
  def advisor_ad(ad_id, adset_id)
    @advisor[:adsets][ad_id] = adset_id
    Crm::MetaAdObject.find_or_create_by!(account_id: @advisor[:account].id, meta_object_id: ad_id) do |object|
      object.assign_attributes(object_type: 'ad', name: "Anúncio #{ad_id}", adset_id: adset_id, fetched_at: Time.current)
    end
  end

  def advisor_insight_day(ad_id, adset_id, date, share)
    connection = @advisor[:connection]
    row = Crm::MetaAdInsightDaily.find_or_initialize_by(account_id: connection.account_id, ad_account_id: connection.ad_account_id,
                                                        ad_id: ad_id, date: date)
    row.update!(adset_id: adset_id, currency: 'BRL', attribution_window: '7d_click', fetched_at: Time.current,
                spend: row.spend.to_d + (share[:spend].to_d / 100), impressions: row.impressions + share[:impressions],
                link_clicks: row.link_clicks + share[:link_clicks],
                conversations_started: row.conversations_started + share[:conversations_started])
  end

  def advisor_conversation(ad_id, at, reply_after)
    connection = @advisor[:connection]
    conversation = create(:conversation, account: connection.account, inbox: @advisor[:inbox], created_at: at, last_activity_at: at)
    Crm::MetaAdLink.create!(account: connection.account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                            certainty: ad_id ? 'ad' : 'unknown', ad_id: ad_id, adset_id: ad_id && @advisor[:adsets][ad_id],
                            ad_account_id: ad_id && connection.ad_account_id, first_touch: true, touched_at: at)
    advisor_message(conversation, :incoming, at, sender: conversation.contact)
    advisor_message(conversation, :outgoing, at + reply_after, sender: @advisor[:user]) if reply_after
    conversation
  end

  def advisor_message(conversation, type, at, sender:, content_attributes: {})
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: type,
                                  content: "Mensagem #{type}", sender: sender, content_attributes: content_attributes, created_at: at)
  end

  def advisor_first_incoming(conversation)
    conversation.messages.incoming.minimum(:created_at)
  end

  def advisor_card(conversation, **attributes)
    Crm::Card.create!(account: conversation.account, pipeline: @advisor[:pipeline], title: 'Cotação', currency: 'BRL',
                      primary_conversation: conversation, **attributes)
  end

  def advisor_facts_key(connection, local_date)
    "crm:meta_ads:advisor:facts:#{Crm::MetaAds::Advisor::Rules::RULES_VERSION}:#{connection.account_id}:" \
      "#{connection.ad_account_id}:#{local_date.iso8601}"
  end

  # "tracking" nas regras de conta, "fatigue:<ad_id>" nas de anúncio.
  def advisor_rule_key(rule)
    rule[:scope].to_s == 'ad' ? "#{rule[:key]}:#{rule[:ad_id]}" : rule[:key].to_s
  end

  # { scale_accepted_ad_ids: [...] }: o History real, o mesmo que a Analysis usa (§1.3).
  def advisor_history(account_id, local_date)
    Crm::MetaAds::Advisor::History.for(account_id, local_date)
  end

  # { [kind, subject_key] => { status:, position:, facts:, ... } } das ações de hoje, pelo History real (§1.4).
  def advisor_today(account_id, local_date)
    Crm::MetaAds::Advisor::History.today(account_id, local_date)
  end
end

RSpec.configure do |config|
  config.include MetaAdsAdvisorHelpers
end

# Saúde do modelo (#1338): o que aconteceu com os envios de cada modelo nos últimos 30 dias, por todas as caixas da conta
# na mesma WABA (o modelo é da WABA). Só o que saiu pelo Chat2You; o relatório da Meta (`template_analytics`) fica para
# depois, com OK do Rodrigo (ligar `is_enabled_for_insights` não tem volta).
#
# - Conversa: mensagem enviada, não privada, que não falhou e leva o modelo (`additional_attributes.template_params`
#   name + language). Recebeu = entregue ou lida; leu = lida; respondeu = entregue e o contato escreveu na mesma conversa
#   até 72 h depois (a janela de "Respondeu" das campanhas, CampaignJourney::ReplyMarker).
# - Campanha (Enterprise): destinatários aceitos pela Meta no período (`sent_at`, enviado/entregue/lido) das campanhas do
#   modelo (`campaigns.template_params`); respondeu = destinatário entregue no período cuja conversa ganhou a marca da
#   campanha (CampaignJourney::ResultReplies, a mesma marca da tela de resultado). O envio de campanha não cria mensagem com
#   `template_params`, então nada é contado duas vezes (ver Whatsapp::TemplateSendCount).
# - Custo: entregues × preço da categoria atual do modelo (Whatsapp::Pricing). É estimativa: a Meta pode não cobrar um
#   aviso de serviço dentro da janela de atendimento. Sem preço para a categoria, sem custo.
# - Média de resposta dos modelos (respostas ÷ entregues de todos), só com pelo menos 3 modelos que entregaram algo.
#
#   Whatsapp::Templates::Health.new(inbox:, templates:).perform
#   # => { ['boas_vindas', 'pt_br'] => { days: 30, sent:, delivered:, read:, replied:,
#   #                                    cost: { total:, per_reply:, currency: } | nil, average_reply_rate: } }
class Whatsapp::Templates::Health
  DAYS = 30
  REPLY_WINDOW = CampaignJourney::ReplyMarker::REPLY_WINDOW
  MIN_TEMPLATES_FOR_AVERAGE = 3
  CACHE_TTL = 5.minutes
  CAMPAIGN_ACCEPTED = %w[sent delivered read].freeze
  DELIVERED = %w[delivered read].freeze
  NAME = "messages.additional_attributes -> 'template_params' ->> 'name'".freeze
  LANGUAGE = "LOWER(messages.additional_attributes -> 'template_params' ->> 'language')".freeze
  FIELDS = %i[sent delivered read replied].freeze
  EMPTY = FIELDS.index_with(0).freeze

  def initialize(inbox:, templates:, now: Time.current)
    @inbox = inbox
    @templates = templates
    @now = now
  end

  def perform
    counts = cached_counts
    numbers = @templates.to_h { |template| [key_for(template), counts.fetch(key_for(template), EMPTY)] }
    average = average_reply_rate(numbers.values)
    @templates.to_h do |template|
      key = key_for(template)
      [key, numbers[key].merge(days: DAYS, cost: cost(template, numbers[key]), average_reply_rate: average)]
    end
  end

  private

  def key_for(template)
    WhatsappTemplateProfile.key_for(template['name'], template['language'])
  end

  def account
    @inbox.account
  end

  def window
    (@now - DAYS.days)..@now
  end

  # A WABA é da caixa: o mesmo modelo sai por todas as caixas da conta ligadas a ela.
  # Sem WABA, só a própria caixa (WABA vazia não junta caixas sem relação).
  def inbox_ids
    @inbox_ids ||= waba_inbox_ids
  end

  def waba_inbox_ids
    waba = @inbox.channel.try(:waba_id).to_s
    return [@inbox.id] if waba.blank?

    ids = Channel::Whatsapp.where(account_id: account.id).where("provider_config ->> 'business_account_id' = ?", waba)
                           .joins(:inbox).pluck('inboxes.id')
    (ids + [@inbox.id]).uniq.sort
  end

  # Contagens de todos os modelos da WABA, guardadas por 5 minutos (a lista de modelos é lida a cada 30 s).
  def cached_counts
    key = ['whatsapp_template_health', account.id, inbox_ids, @now.utc.beginning_of_hour]
    Rails.cache.fetch(key, expires_in: CACHE_TTL, race_condition_ttl: 30.seconds) do
      add(message_counts, campaign_counts)
    end
  end

  def add(first, second)
    first.merge(second) { |_key, a, b| a.merge(b) { |_field, x, y| x + y } }
  end

  def message_counts
    sent_messages.reorder(nil).group(Arel.sql(NAME), Arel.sql(LANGUAGE)).pluck(
      Arel.sql(NAME), Arel.sql(LANGUAGE), Arel.sql('COUNT(*)'),
      Arel.sql("COUNT(*) FILTER (WHERE messages.status IN (#{status_values(DELIVERED)}))"),
      Arel.sql("COUNT(*) FILTER (WHERE messages.status = #{Message.statuses[:read]})"),
      Arel.sql("COUNT(*) FILTER (WHERE messages.status IN (#{status_values(DELIVERED)}) AND #{replied_sql})")
    ).to_h { |row| [row.first(2), FIELDS.zip(row.drop(2)).to_h] }
  end

  def sent_messages
    Message.where(account_id: account.id, inbox_id: inbox_ids, message_type: :outgoing, private: false, created_at: window)
           .where.not(status: :failed)
           .where("#{NAME} IS NOT NULL")
  end

  def status_values(statuses)
    statuses.map { |status| Message.statuses.fetch(status) }.join(', ')
  end

  def replied_sql
    incoming = Message.message_types[:incoming]
    seconds = REPLY_WINDOW.to_i
    'EXISTS (SELECT 1 FROM messages replies WHERE replies.conversation_id = messages.conversation_id ' \
      "AND replies.message_type = #{incoming} AND replies.created_at > messages.created_at " \
      "AND replies.created_at <= messages.created_at + INTERVAL '#{seconds} seconds')"
  end

  def campaign_counts
    return {} unless ChatwootApp.enterprise?

    campaigns = campaigns_with_recipients
    recipients = recipient_counts(campaigns.map(&:id))
    campaigns.reduce({}) do |result, campaign|
      numbers = recipients.fetch(campaign.id, EMPTY).merge(replied: campaign_replied(campaign))
      add(result, campaign_key(campaign) => numbers)
    end
  end

  # Só quem recebeu no período e respondeu (a marca da campanha na conversa): nunca mais respostas que entregues.
  def campaign_replied(campaign)
    contacts = CampaignJourney::ResultReplies.new(account, CampaignJourney::CampaignMarks.source_id_for(campaign)).contact_ids
    return 0 if contacts.empty?

    accepted_recipients.where(campaign_id: campaign.id, status: DELIVERED, contact_id: contacts).count
  end

  def campaign_key(campaign)
    [campaign.template_params['name'].to_s, campaign.template_params['language'].to_s.downcase]
  end

  def accepted_recipients
    CampaignRecipient.where(account_id: account.id, inbox_id: inbox_ids, status: CAMPAIGN_ACCEPTED, sent_at: window)
  end

  def campaigns_with_recipients
    Campaign.where(account_id: account.id, id: accepted_recipients.select(:campaign_id))
            .where("template_params ->> 'name' IS NOT NULL").to_a
  end

  def recipient_counts(campaign_ids)
    statuses = CampaignRecipient.statuses
    accepted_recipients.where(campaign_id: campaign_ids).reorder(nil).group(:campaign_id).pluck(
      :campaign_id, Arel.sql('COUNT(*)'),
      Arel.sql("COUNT(*) FILTER (WHERE status IN (#{statuses[:delivered]}, #{statuses[:read]}))"),
      Arel.sql("COUNT(*) FILTER (WHERE status = #{statuses[:read]})")
    ).to_h { |row| [row.first, FIELDS.zip(row.drop(1) + [0]).to_h] }
  end

  def cost(template, numbers)
    return if numbers[:sent].zero?

    price = price_for(template['category'])
    return if price.nil? || price.currency.blank?

    total = price.amount * numbers[:delivered]
    { total: total.to_f, per_reply: numbers[:replied].positive? ? (total / numbers[:replied]).round(4).to_f : nil,
      currency: price.currency }
  end

  # Uma leitura da tabela por categoria, não uma por modelo.
  def price_for(category)
    @prices ||= {}
    @prices.fetch(category.to_s) { @prices[category.to_s] = Whatsapp::Pricing.per_message(category) }
  end

  def average_reply_rate(numbers)
    delivering = numbers.select { |item| item[:delivered].positive? }
    return if delivering.size < MIN_TEMPLATES_FOR_AVERAGE

    ((delivering.sum { |item| item[:replied] } * 100.0) / delivering.sum { |item| item[:delivered] }).round
  end
end

class Crm::Kanban::CardPayloadBuilder
  UNRESOLVED_COMPANY = Object.new.freeze

  def initialize(card:, conversation_visibility:, account_user:, pending_suggestion: nil, company: UNRESOLVED_COMPANY)
    @card = card
    @account_user = account_user
    @conversation_visibility = conversation_visibility
    @pending_suggestion = pending_suggestion
    @company = company.equal?(UNRESOLVED_COMPANY) ? Crm::Cards::CompanyResolver.for_card(card) : company
  end

  # Valor de venda (#2075): sem `sales_value_view`, o card sai sem value_cents, menos o card de que a pessoa é dona.
  def perform
    payload = identity_payload.merge(status_payload, link_payload)
    Crm::ValorDeVenda.ve_o_card?(@account_user, @card) ? payload : Crm::ValorDeVenda.oculta_card!(payload)
  end

  private

  def identity_payload
    {
      id: @card.id,
      title: @card.title,
      pipeline_id: @card.pipeline_id,
      stage_id: @card.stage_id,
      contact_id: @card.contact_id,
      conversation_id: visible_primary_conversation&.id,
      inbox_id: @card.inbox_id,
      owner_id: @card.owner_id,
      team_id: @card.team_id
    }
  end

  def status_payload
    {
      value_cents: @card.value_cents,
      currency: @card.currency,
      priority: @card.priority,
      score: @card.score,
      score_source: score_source,
      status: @card.status,
      is_standalone: @card.standalone?,
      # Epoch seconds across the board payload so the frontend timeHelper.js
      # (fromUnixTime-based) renders them consistently without Invalid-Date.
      next_follow_up_at: @card.next_follow_up_at&.to_i,
      next_follow_up_source: next_follow_up_source,
      last_message_at: @card.last_message_at&.to_i,
      entered_stage_at: @card.entered_stage_at&.to_i,
      ai_suggestion: ai_suggestion_payload
    }.compact
  end

  # Type of the follow-up that owns next_follow_up_at (the nearest active one) so
  # the card badge can show 🤖 (AI cadence) vs 🔔 (manual reminder) WITHOUT a
  # per-card query: the nearest is the AI touch iff the active cadence's
  # next_due_at equals next_follow_up_at; otherwise it is a manual/other follow-up.
  def next_follow_up_source
    return if @card.next_follow_up_at.blank?

    state = (@card.metadata || {}).dig('ai', 'auto_followup_state') || {}
    return 'manual' unless state['active'] == true && state['next_due_at'].present?

    Time.zone.parse(state['next_due_at'].to_s).to_i == @card.next_follow_up_at.to_i ? 'ai' : 'manual'
  rescue ArgumentError, TypeError
    'manual'
  end

  def score_source
    (@card.metadata || {}).dig('ai', 'score', 'source').presence
  end

  # Sugestão de etapa (#2150): só quem tem crm_manage_ai a lê; sem a chave, o card sai sem ai_suggestion.
  def ai_suggestion_payload
    return unless Crm::Ai::Config.enabled? && Crm::SugestaoDeEtapa.le?(@account_user)

    suggestion = @pending_suggestion || @card.ai_stage_suggestions.current_pending.includes(:to_stage).first
    return if suggestion.blank? || suggestion.fechar_fora_da_tela?(@card)

    {
      id: suggestion.id,
      to_stage_id: suggestion.to_stage_id,
      to_stage_name: suggestion.to_stage&.name,
      confidence: suggestion.confidence.to_f
    }.merge(suggestion.fechar ? { fechar: suggestion.fechar } : {})
  end

  def link_payload
    {
      contact: compact_contact,
      company: (Crm::Cards::CompanyResolver.payload(@company) if full_contact?),
      owner: compact_user(@card.owner),
      responsible: responsible_payload,
      inbox: compact_inbox,
      conversation: compact_conversation,
      labels: labels_payload,
      contact_labels: contact_labels_payload,
      campaigns: campaigns_payload
    }
  end

  # Label titles (strings) of the PRIMARY conversation only, in cached_label_list
  # order — color/id resolution happens client-side against the labels store.
  # [] when the primary conversation is hidden/absent (same gate as SLA/summary).
  # Shape mirrored in Crm::Cards::PayloadBuilder — keep both identical.
  def labels_payload
    conversation = visible_primary_conversation
    return [] if conversation.blank?

    conversation.cached_label_list_array
  end

  # Label titles of the CONTACT (e.g. campaign import labels — never synced onto
  # the conversation, see CampaignImports::Importer#apply_labels!). Not gated on
  # conversation visibility: the contact itself is always shown on the card.
  # Reads the preloaded label_taggings (see Crm::Kanban::BoardPayloadBuilder's
  # preload) instead of contact.label_list to avoid an N+1 query per card.
  # Shape mirrored in Crm::Cards::PayloadBuilder — keep both identical.
  def contact_labels_payload
    contact = @card.contact
    return [] if contact.blank? || !full_contact?

    contact.label_taggings.reject(&:tagger_id).filter_map { |tagging| tagging.tag&.name }
  end

  # CTWA multi-touch: aggregated campaign touches of the card, first touch -> last;
  # the pill uses campaigns[0].headline and the badge uses length-1. Each source
  # conversation is authorized by Crm::Cards::PayloadBuilder, matching the
  # list/websocket and server-side campaign filters.
  # Anúncio de origem (#2271): sem `meta_ads_view`, o toque de anúncio sai sem título, nomes, prévia e miniatura.
  def campaigns_payload
    Crm::Cards::PayloadBuilder.aggregated_campaigns_for(@card, conversation_visibility: @conversation_visibility,
                                                               ad_visible: @conversation_visibility.anuncio_visivel?)
  end

  def compact_contact
    return if @card.contact.blank?

    basic = { id: @card.contact.id, name: @card.contact.name, phone_number: @card.contact.phone_number }
    return basic unless full_contact?

    # Selo "Cliente" no card do quadro (#1258).
    basic.merge(contact_type: @card.contact.contact_type, customer_since: @card.contact.customer_since&.to_i)
  end

  # #1849: sem ver contatos, o quadro leva só nome e telefone do contato, sem empresa, etiquetas do contato nem selo.
  def full_contact?
    @conversation_visibility.full_contact?
  end

  def compact_user(user)
    return if user.blank?

    { id: user.id, name: user.name }
  end

  def compact_inbox
    return if @card.inbox.blank?

    {
      id: @card.inbox.id,
      name: @card.inbox.name,
      channel_type: @card.inbox.channel_type
    }
  end

  def compact_conversation
    conversation = visible_primary_conversation
    return if conversation.blank?

    payload = {
      id: conversation.id,
      display_id: conversation.display_id,
      inbox_id: conversation.inbox_id,
      status: conversation.status,
      first_reply_created_at: conversation.first_reply_created_at&.to_i,
      waiting_since: conversation.waiting_since&.to_i
    }
    applied_sla = applied_sla_payload(conversation)
    payload[:applied_sla] = applied_sla if applied_sla.present?
    payload
  end

  # SLA badge data for the board feed; mirrors Crm::Cards::PayloadBuilder so the
  # Kanban and List views agree. Gated on the account 'sla' feature.
  def applied_sla_payload(conversation)
    return unless @card.account.feature_enabled?('sla')

    conversation.applied_sla&.push_event_data
  end

  # Conversa que a pessoa não vê (#2283): o nome de quem atende essa conversa não vai, como no Crm::Cards::PayloadBuilder
  # (o tempo real do quadro chega por ele); no lugar, o dono do card, senão o robô.
  def responsible_payload
    conversation = @card.primary_conversation
    if conversation&.assignee_id.present? && visible_primary_conversation.nil?
      return Crm::Cards::PayloadBuilder.responsible_without_conversation_agent(@card)
    end

    @card.responsible_descriptor
  end

  def visible_primary_conversation
    conversation = @card.primary_conversation
    return if conversation.blank?
    return conversation if @conversation_visibility.visible?(conversation)

    nil
  end
end

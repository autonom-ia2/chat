class Autonomia::Prospecting::CampaignSegmentBuilder
  Result = Struct.new(:list, :label, :campaign, :eligible_leads, :blocked_leads, :created_contacts_count, keyword_init: true)

  Error = Class.new(StandardError)

  ELIGIBLE_STATUS = 'ready_for_campaign'.freeze
  # Os dois tipos que recebem o segmento pela etiqueta (#732, item 11): a campanha de envio único (Campaign, pelo
  # display_id) e a campanha da API do WhatsApp (WhatsappApiCampaign, pelo id). Sem tipo, é a de envio único, como antes.
  ONE_OFF = 'one_off'.freeze
  WHATSAPP_API = 'whatsapp_api'.freeze
  CAMPAIGN_TYPES = [ONE_OFF, WHATSAPP_API].freeze

  def initialize(list:, user:, campaign_id: nil, segment_name: nil, campaign_type: nil)
    @list = list
    @account = list.account
    @user = user
    @campaign_id = campaign_id.presence
    @campaign_type = campaign_type.presence || ONE_OFF
    @segment_name = segment_name.presence || list.name
  end

  # A etiqueta desta lista já está na audiência de alguma campanha da conta. A campanha one-off decide quem recebe pelas
  # etiquetas na hora do envio, então reaplicar a etiqueta aumenta a audiência mesmo sem campaign_id (#680).
  # A campanha da API do WhatsApp também decide o público pelas etiquetas, ao começar: só a agendada ainda cresce.
  def feeds_existing_campaign?
    label = @account.labels.find_by(title: label_title)
    return false if label.nil?

    [*@account.campaigns, *@account.whatsapp_api_campaigns.scheduled].any? { |campaign| audience_has_label?(campaign, label) }
  end

  def perform
    ensure_segment_possible!

    created_contacts_count = 0
    label = nil
    campaign = nil

    with_suppressed_contact_events do
      ActiveRecord::Base.transaction do
        label = ensure_label!
        created_contacts_count = label_segment!(label)
        campaign = attach_to_campaign!(label) if @campaign_id.present?
        persist_segment_metadata!(label, campaign)
      end
    end

    Result.new(
      list: @list.reload,
      label: label.reload,
      campaign: campaign&.reload,
      eligible_leads: eligible_leads,
      blocked_leads: blocked_details,
      created_contacts_count: created_contacts_count
    )
  end

  # Cada lead que fica fora, com o motivo (#680, ACAO-26/27). Público para a tela explicar mesmo quando ninguém entra.
  def blocked_details
    @blocked_details ||= leads.filter_map do |lead|
      reason_code = block_reason(lead)
      next if reason_code.nil?

      { lead: lead, reason_code: reason_code, message: I18n.t("autonomia.prospecting.campaign_blocked.#{reason_code}") }
    end
  end

  private

  def leads
    @leads ||= @list.leads.order(:id).to_a
  end

  def eligible_leads
    @eligible_leads ||= leads.select { |lead| block_reason(lead).nil? }
  end

  def block_reason(lead)
    @block_reasons ||= leads.to_h { |item| [item.id, compute_block_reason(item)] }
    @block_reasons[lead.id]
  end

  # A ordem é a da explicação mais útil: primeiro o que a pessoa decidiu (descarte, pedido para parar, bloqueio),
  # depois o que falta no lead. Contato bloqueado ou que pediu para parar nunca recebe a etiqueta.
  # A recusa de outro lead com o mesmo contato, telefone ou e-mail também vale (ConsentVeto).
  def compute_block_reason(lead)
    return 'discarded' if lead.discarded?
    return 'opt_out' if lead.no_consent?

    contact = existing_contact(lead)
    return 'opt_out' if consent_veto.vetoed?(lead: lead, contact: contact)

    contact_block_reason(contact) || lead_block_reason(lead)
  end

  def consent_veto
    @consent_veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end

  def contact_block_reason(contact)
    return if contact.nil?
    return 'contact_blocked' if contact.blocked?

    'opt_out' if contact_opted_out?(contact)
  end

  def lead_block_reason(lead)
    return 'no_phone' if lead.phone.blank?
    return 'no_whatsapp' unless whatsapp_verified?(lead)

    'not_ready' unless lead.status == ELIGIBLE_STATUS
  end

  # O mesmo contato que o ContactConverter vai etiquetar: o do lead ou o que ele acha pelo WhatsApp verificado, pelo
  # telefone, pelo identificador ou pelo e-mail.
  def existing_contact(lead)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user).existing_contact
  end

  # Quem respondeu "parar" ao follow-up da IA fica marcado no card (Crm::FollowUps::AutoFollowupCanceler).
  def contact_opted_out?(contact)
    @account.crm_cards.where(contact_id: contact.id)
            .exists?(["metadata->'ai'->'auto_followup_state'->>'opted_out' = 'true'"])
  end

  def whatsapp_verified?(lead)
    lead.metadata.to_h.dig('whatsapp_verification', 'status') == 'verified'
  end

  def ensure_label!
    label = @account.labels.find_or_initialize_by(title: label_title)
    raise Error, 'prospecting.campaign.label_collision_visible_on_sidebar' if label.persisted? && label.show_on_sidebar?

    label.assign_attributes(
      description: "Segmento gerado pela prospeccao: #{@list.name}",
      show_on_sidebar: false
    )
    label.save!
    label
  end

  def label_title
    @label_title ||= begin
      slug = ActiveSupport::Inflector.transliterate(@segment_name.to_s)
                                     .downcase
                                     .gsub(/[^a-z0-9_-]+/, '_')
                                     .gsub(/\A_+|_+\z/, '')
                                     .presence || 'lista'
      "prospeccao_#{@list.id}_#{slug}"[0, 120]
    end
  end

  def apply_label!(contact, label)
    contact.label_list.add(label.title)
    contact.save!
  end

  # Etiqueta os elegíveis e tira a etiqueta de quem ficou fora por recusa (SegmentLabelRemover). Devolve quantos
  # contatos foram criados agora.
  def label_segment!(label)
    converted = eligible_leads.map { |lead| Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user).perform }
    converted.each { |result| apply_label!(result.contact, label) }
    kept_contact_ids = converted.map { |result| result.contact.id }
    Autonomia::Prospecting::SegmentLabelRemover.new(label: label, user: @user, kept_contact_ids: kept_contact_ids).perform(blocked_details)
    converted.count(&:created)
  end

  def ensure_segment_possible!
    raise Error, 'prospecting.campaign.unsupported_campaign' if @campaign_id.present? && CAMPAIGN_TYPES.exclude?(@campaign_type)
    raise Error, 'prospecting.campaign.empty_list' if leads.empty?
    raise Error, 'prospecting.campaign.no_eligible_leads' if eligible_leads.empty?
  end

  def attach_to_campaign!(label)
    return attach_to_whatsapp_api_campaign!(label) if @campaign_type == WHATSAPP_API

    campaign = @account.campaigns.find_by!(display_id: @campaign_id)
    raise Error, 'prospecting.campaign.unsupported_campaign' unless campaign.one_off?
    raise Error, 'prospecting.campaign.campaign_not_active' unless campaign.active?

    add_label_to_audience!(campaign, label)
  end

  # A campanha da API resolve o público quando começa (WhatsappApiCampaigns::Scheduler, sob o mesmo lock): depois disso,
  # a etiqueta nova não levaria ninguém. Por isso só a agendada recebe o segmento.
  def attach_to_whatsapp_api_campaign!(label)
    raise Error, 'prospecting.campaign.unsupported_campaign' unless WhatsappApiCampaigns::Config.enabled?

    campaign = @account.whatsapp_api_campaigns.find(@campaign_id)
    campaign.with_lock do
      raise Error, 'prospecting.campaign.campaign_not_active' unless campaign.scheduled?

      add_label_to_audience!(campaign, label)
    end
  end

  def add_label_to_audience!(campaign, label)
    audience = Array(campaign.audience).map { |item| item.to_h.stringify_keys }
    audience << { 'type' => 'Label', 'id' => label.id } unless audience_has_label?(campaign, label)
    campaign.update!(audience: audience)
    campaign
  end

  def audience_has_label?(campaign, label)
    Array(campaign.audience).any? do |item|
      item = item.to_h.stringify_keys
      item['type'] == 'Label' && item['id'].to_s == label.id.to_s
    end
  end

  def persist_segment_metadata!(label, campaign)
    metadata = @list.metadata.to_h
    reference = Autonomia::Prospecting::CampaignSegmentPayload.campaign(campaign).to_h
    metadata['campaign_segment'] = {
      'label_id' => label.id,
      'label_title' => label.title,
      'campaign_id' => reference[:id],
      'campaign_type' => reference[:type],
      'campaign_title' => reference[:title],
      'eligible_count' => eligible_leads.size,
      'blocked_count' => blocked_details.size,
      'generated_by_id' => @user&.id,
      'generated_at' => Time.current.iso8601
    }.compact
    @list.update!(metadata: metadata)
  end

  def with_suppressed_contact_events
    previous = Current.suppress_contact_events
    Current.suppress_contact_events = true
    yield
  ensure
    Current.suppress_contact_events = previous
  end
end

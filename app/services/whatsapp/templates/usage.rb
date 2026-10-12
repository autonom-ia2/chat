# "Onde está em uso" de um modelo (#1330): o que ainda vai mandar este modelo (nome + idioma) por alguma caixa da
# conta na mesma WABA. Apagar ou alterar um modelo em uso faz esse envio falhar, por isso a API bloqueia (422).
#
# - campanhas agendadas ou em andamento (`campaigns.template_params` name/language);
# - avisos do agendamento: página ligada, nova (page_version 2), com a caixa de avisos, e o modelo escolhido para um
#   aviso ativo do jogo de avisos (`notice_templates[tipo]`);
# - follow-ups pendentes ou atrasados que mandam o modelo (`crm_follow_ups.metadata` template_name/template_language).
#
# Só lista o que a pessoa pode ver: campanhas com `campaign_view`, páginas com `agendamento_view` e follow-ups de
# cards do `policy_scope(::Crm::Card)` (acesso por funil, #1148). O resto vira só `uso_oculto: true`, sem número nem
# nome: a tela bloqueia com "em uso onde você não tem acesso".
class Whatsapp::Templates::Usage
  PENDING_FOLLOW_UPS = %w[pending overdue].freeze
  OPEN_CAMPAIGNS = %w[active processing].freeze

  # `visible_cards`: o escopo de cards que a pessoa vê (`policy_scope(::Crm::Card)`).
  def initialize(inbox:, name:, language:, account_user:, visible_cards:)
    @inbox = inbox
    @name = name.to_s
    @language = language.to_s
    @account_user = account_user
    @visible_cards = visible_cards
  end

  def perform
    campaigns = campaign_rows
    pages = booking_page_rows
    follow_ups = follow_up_rows
    hidden = hidden?(campaigns, pages, follow_ups)
    {
      campaigns: allowed?('campaign_view') ? campaigns : [],
      booking_pages: allowed?('agendamento_view') ? pages : [],
      follow_ups: follow_ups[:visible],
      uso_oculto: hidden,
      in_use: hidden || campaigns.any? || pages.any? || follow_ups[:visible].any?
    }
  end

  def in_use?
    perform[:in_use]
  end

  private

  def hidden?(campaigns, pages, follow_ups)
    (campaigns.any? && !allowed?('campaign_view')) || (pages.any? && !allowed?('agendamento_view')) || follow_ups[:hidden]
  end

  def allowed?(key)
    @account_user&.permission_granted?(key)
  end

  def account
    @inbox.account
  end

  # A WABA é da caixa: o mesmo modelo serve todas as caixas da conta ligadas a ela.
  def inbox_ids
    @inbox_ids ||= begin
      waba = @inbox.channel.try(:waba_id).to_s
      ids = Channel::Whatsapp.where(account_id: account.id).where("provider_config ->> 'business_account_id' = ?", waba)
                             .joins(:inbox).pluck('inboxes.id')
      (ids + [@inbox.id]).uniq
    end
  end

  def campaign_rows
    Campaign.where(account_id: account.id, inbox_id: inbox_ids, campaign_status: OPEN_CAMPAIGNS)
            .where("template_params ->> 'name' = ?", @name)
            .where("LOWER(template_params ->> 'language') = ?", @language.downcase)
            .order(:id)
            .map { |campaign| campaign_row(campaign) }
  end

  def campaign_row(campaign)
    { id: campaign.display_id, title: campaign.title, status: campaign.campaign_status, scheduled_at: campaign.scheduled_at }
  end

  def booking_page_rows
    Crm::AgentBookingProfile.where(account_id: account.id, enabled: true, page_version: Crm::AgentBookingProfile::NEW_PAGE,
                                   notice_inbox_id: inbox_ids)
                            .order(:id)
                            .filter_map { |page| booking_page_row(page) }
  end

  def booking_page_row(page)
    # Só id e título: a tela leva ao painel (crm/booking), nunca ao link público da página.
    { id: page.id, title: page.title } if page.notice_kinds.any? { |kind| same_template?(page.notice_template(kind)) }
  end

  def same_template?(template)
    template.is_a?(Hash) && template['name'] == @name && template['language'].to_s.casecmp?(@language)
  end

  # Follow-up sem caixa própria manda pela caixa da conversa dele.
  def follow_up_scope
    pending = Crm::FollowUp.where(account_id: account.id, status: PENDING_FOLLOW_UPS)
    pending.where(inbox_id: inbox_ids)
           .or(pending.where(inbox_id: nil, conversation_id: Conversation.where(inbox_id: inbox_ids).select(:id)))
           .where("metadata ->> 'template_name' = ?", @name)
           .where("LOWER(metadata ->> 'template_language') = ?", @language.downcase)
  end

  def follow_up_rows
    scope = follow_up_scope
    visible = scope.where(card_id: @visible_cards.select(:id))
    rows = visible.order(:due_at).map do |follow_up|
      { id: follow_up.id, title: follow_up.title, card_id: follow_up.card_id, due_at: follow_up.due_at, status: follow_up.status }
    end
    { visible: rows, hidden: scope.where.not(id: visible.select(:id)).exists? }
  end
end

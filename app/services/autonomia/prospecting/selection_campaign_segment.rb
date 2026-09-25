# "Adicionar à campanha" a partir dos leads selecionados (#680, ACAO-25/37). Como no Orth, a seleção vira uma lista
# (criada ou reusada pelo nome do segmento) e o segmento sai do CampaignSegmentBuilder, o mesmo das Listas. Tudo numa
# transação: sem ninguém elegível, nem a lista nem a mudança de status ficam gravadas.
class Autonomia::Prospecting::SelectionCampaignSegment
  # O teto do envio em lote do Orth (ACAO-05).
  MAX_LEADS = 500
  # Mesmo efeito do "adicionar à lista": o lead passa a pronto para campanha, menos quem foi descartado ou recusou.
  PROMOTABLE_STATUSES = %w[new_lead qualified].freeze

  Result = Struct.new(:segment, :missing_lead_ids, keyword_init: true)

  class Error < StandardError
    attr_reader :blocked_leads, :missing_lead_ids

    def initialize(message, blocked_leads: [], missing_lead_ids: [])
      super(message)
      @blocked_leads = blocked_leads
      @missing_lead_ids = missing_lead_ids
    end
  end

  def initialize(account:, user:, lead_ids:, campaign_id: nil, segment_name: nil)
    @account = account
    @user = user
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
    @campaign_id = campaign_id
    @segment_name = segment_name.to_s.strip.presence || default_name
  end

  def perform
    raise Error, 'prospecting.campaign.empty_selection' if @lead_ids.empty?
    raise Error, 'prospecting.campaign.too_many_leads' if @lead_ids.size > MAX_LEADS

    ActiveRecord::Base.transaction do
      list = find_or_create_list!
      leads.each { |lead| add_to_list!(list, lead) }
      Result.new(segment: build_segment(list), missing_lead_ids: missing_lead_ids)
    end
  end

  private

  def leads
    @leads ||= Autonomia::Prospecting::Lead.where(account: @account, id: @lead_ids).order(:id).to_a
  end

  def missing_lead_ids
    @lead_ids - leads.map(&:id)
  end

  def find_or_create_list!
    @account.autonomia_prospecting_lists.find_or_create_by!(name: @segment_name) { |list| list.user = @user }
  end

  def add_to_list!(list, lead)
    list.list_leads.find_or_create_by!(lead: lead) { |list_lead| list_lead.account = @account }
    lead.ready_for_campaign! if PROMOTABLE_STATUSES.include?(lead.status)
  end

  def build_segment(list)
    builder = Autonomia::Prospecting::CampaignSegmentBuilder.new(
      list: list, user: @user, campaign_id: @campaign_id, segment_name: @segment_name
    )
    builder.perform
  rescue Autonomia::Prospecting::CampaignSegmentBuilder::Error => e
    raise Error.new(e.message, blocked_leads: builder.blocked_details, missing_lead_ids: missing_lead_ids)
  end

  def default_name
    I18n.t('autonomia.prospecting.selection_list_name', date: I18n.l(Time.zone.now, format: :short))
  end
end

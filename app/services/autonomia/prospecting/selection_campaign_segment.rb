# "Adicionar à campanha" a partir dos leads selecionados (#680, ACAO-25/37). A seleção vira uma lista nova, só com os
# leads selecionados, e o segmento sai do CampaignSegmentBuilder, o mesmo das Listas. Como no Orth, a audiência é
# exatamente a seleção: uma lista de mesmo nome (de outro envio ou de outro usuário) nunca é reaproveitada, senão os
# leads dela ganhariam a etiqueta e entrariam na campanha. Nome repetido ganha um número: "Seleção (2)".
# Tudo numa transação: sem ninguém elegível, nem a lista nem a mudança de status ficam gravadas.
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

  # campaign: { id:, type: }, a campanha escolhida e o tipo dela (#732, item 11); vazio cria só o segmento.
  def initialize(account:, user:, lead_ids:, campaign: {}, segment_name: nil)
    @account = account
    @user = user
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
    @campaign = campaign.to_h.symbolize_keys
    @segment_name = segment_name.to_s.strip.presence || default_name
  end

  def perform
    raise Error, 'prospecting.campaign.empty_selection' if @lead_ids.empty?
    raise Error, 'prospecting.campaign.too_many_leads' if @lead_ids.size > MAX_LEADS

    ActiveRecord::Base.transaction do
      list = create_list!
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

  def create_list!
    @account.autonomia_prospecting_lists.create!(name: free_name, user: @user)
  end

  def free_name
    lists = @account.autonomia_prospecting_lists
    return @segment_name unless lists.exists?(name: @segment_name)

    taken = lists.where('name LIKE ?', "#{ActiveRecord::Base.sanitize_sql_like(@segment_name)} (%)").pluck(:name).to_set
    (2..).each do |number|
      candidate = "#{@segment_name} (#{number})"
      return candidate unless taken.include?(candidate)
    end
  end

  def add_to_list!(list, lead)
    list.list_leads.find_or_create_by!(lead: lead) { |list_lead| list_lead.account = @account }
    lead.ready_for_campaign! if PROMOTABLE_STATUSES.include?(lead.status)
  end

  def build_segment(list)
    builder = Autonomia::Prospecting::CampaignSegmentBuilder.new(
      list: list, user: @user, campaign_id: @campaign[:id], campaign_type: @campaign[:type], segment_name: @segment_name
    )
    builder.perform
  rescue Autonomia::Prospecting::CampaignSegmentBuilder::Error => e
    raise Error.new(e.message, blocked_leads: builder.blocked_details, missing_lead_ids: missing_lead_ids)
  end

  def default_name
    I18n.t('autonomia.prospecting.selection_list_name', date: I18n.l(Time.zone.now, format: :short))
  end
end

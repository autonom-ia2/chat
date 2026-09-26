# Evento ao vivo do lead (#678): quando o enriquecimento, a verificação de WhatsApp ou o varredor mudam um lead
# no servidor, a tela troca o card e o painel sem recarregar. Vai para quem pode ver a Prospecção na conta, com o
# mesmo lead que GET leads/:id devolve para essa pessoa (#732): o agente só recebe o lead que ele pode abrir (das
# próprias buscas ou de uma lista), e sem o bloco técnico da nota, que é do administrador.
class Autonomia::Prospecting::LeadBroadcaster
  include Events::Types

  def self.updated(lead)
    new(lead).broadcast
  end

  def initialize(lead)
    @lead = lead
    @account = lead.account
  end

  def broadcast
    with_details, without_details = viewers.partition(&:score_details?)
    deliver(with_details, full_payload)
    deliver(without_details, restricted_payload(without_details.first))
  end

  private

  def viewers
    @account.account_users.includes(:user).select { |account_user| account_user.permission_granted?('prospecting_view') }
            .map { |account_user| Autonomia::Prospecting::Visibility.new(account_user) }
            .select { |visibility| visibility.lead_visible?(@lead) }
  end

  def deliver(group, payload)
    tokens = group.filter_map { |visibility| visibility.account_user.user.pubsub_token }
    return if tokens.empty?

    ActionCableBroadcastJob.perform_later(tokens, PROSPECTING_LEAD_UPDATED, payload)
  end

  # JSON puro (chaves string): o job serializa sem depender de BigDecimal nem de Time.
  def full_payload
    { 'account_id' => @account.id, 'lead' => lead_json }
  end

  def restricted_payload(visibility)
    return if visibility.nil?

    { 'account_id' => @account.id, 'lead' => visibility.lead_payload(lead_json) }
  end

  def lead_json
    @lead_json ||= Autonomia::Prospecting::LeadPayload.new(account: @account).build(@lead).as_json
  end
end

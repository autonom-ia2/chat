# Evento ao vivo do lead (#678): quando o enriquecimento, a verificação de WhatsApp ou o varredor mudam um lead
# no servidor, a tela troca o card e o painel sem recarregar. Vai para quem pode ver a Prospecção na conta, com o
# mesmo lead que GET leads/:id devolve.
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
    tokens = viewer_tokens
    return if tokens.empty?

    ActionCableBroadcastJob.perform_later(tokens, PROSPECTING_LEAD_UPDATED, payload)
  end

  private

  def viewer_tokens
    @account.account_users.includes(:user).select { |account_user| account_user.permission_granted?('prospecting_view') }
            .filter_map { |account_user| account_user.user.pubsub_token }
  end

  # JSON puro (chaves string): o job serializa sem depender de BigDecimal nem de Time.
  def payload
    {
      'account_id' => @account.id,
      'lead' => Autonomia::Prospecting::LeadPayload.new(account: @account).build(@lead).as_json
    }
  end
end

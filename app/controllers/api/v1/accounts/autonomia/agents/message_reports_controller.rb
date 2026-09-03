# "Resposta errada" numa mensagem do agente Autonom.ia (#284 · Entrega 1). Reusa o model
# Captain::MessageReport do upstream (sem FK para Captain; só account/conversation/message/user).
# NÃO herda de Autonomia::BaseController: aquele exige administrador, e o feedback é do ATENDENTE.
# Mantém o gate da feature por conta e o isolamento de conta (mensagem buscada em Current.account).
class Api::V1::Accounts::Autonomia::Agents::MessageReportsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :set_message
  before_action :authorize_report
  before_action :ensure_autonomia_agent_message

  def create
    @message_report = ::Captain::MessageReport.create!(
      message: @message,
      user: Current.user,
      report_reason: permitted_params[:report_reason],
      description: permitted_params[:description]
    )
  end

  private

  def ensure_feature_enabled
    head :not_found unless ::Autonomia::Agents::Config.enabled?(Current.account)
  end

  def set_message
    @message = Current.account.messages.find(permitted_params[:message_id])
  end

  # Qualquer membro da conta reporta (policy própria), desde que enxergue a conversa (mesma regra
  # de acesso por caixa/time do resto do produto).
  def authorize_report
    authorize(@message, :create?, policy_class: ::Autonomia::Agents::MessageReportPolicy)
    authorize(@message.conversation, :show?)
  end

  # Só mensagens postadas pelo agente Autonom.ia (AgentBot-espelho carimbado com autonomia_agent_id).
  def ensure_autonomia_agent_message
    return if @message.sender_type == 'AgentBot' && @message.content_attributes.to_h['autonomia_agent_id'].present?

    render json: { error: 'Only Autonomia agent messages can be reported' }, status: :unprocessable_entity
  end

  def permitted_params
    params.permit(:message_id, :report_reason, :description)
  end
end

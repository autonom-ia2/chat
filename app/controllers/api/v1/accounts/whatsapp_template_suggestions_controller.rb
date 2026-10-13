# "Criar com IA" e "Melhorar com IA" da tela de Modelos do WhatsApp (#1333, épico #1320). Nada é salvo nem enviado à Meta.
#
#   POST /api/v1/accounts/:account_id/whatsapp_template_suggestions
#     criar:    { mode: 'create', goal:, tone?, category? }
#     melhorar: { mode: 'improve', text: (com {{chave.do.catalogo}}), improvements: [...], tone?, category?, meta_reason? }
#   => 202 { id, status: 'pending', poll_url }  (padrão `DeferInteractiveAi`; o resultado sai em GET ai_requests/:id:
#      { payload: { status, question, suggestions, options } } ou { error: 'suggestion_unavailable', message })
#
# Mesma porta de escrever modelo: flag `whatsapp_templates_journey` (404 sem ela) e `whatsapp_templates_manage`; o job
# confere as duas de novo antes de chamar a IA. Pedido fora do formato: 422 na hora, sem enfileirar.
class Api::V1::Accounts::WhatsappTemplateSuggestionsController < Api::V1::Accounts::BaseController
  include DeferInteractiveAi

  before_action :ensure_journey_enabled
  before_action :check_authorization

  def create
    defer_interactive_ai(Whatsapp::Templates::Sugestao::OPERACAO, Whatsapp::Templates::Sugestao.entradas(suggestion_params))
  rescue Whatsapp::Templates::Redacao::Invalida
    render_error('suggestion_invalid')
  end

  private

  def suggestion_params
    {
      mode: params[:mode].to_s, goal: params[:goal].to_s, text: params[:text].to_s, tone: params[:tone].to_s,
      category: params[:category].to_s, meta_reason: params[:meta_reason].to_s, improvements: Array(params[:improvements])
    }.with_indifferent_access
  end

  def ensure_journey_enabled
    render_error('feature_disabled', :not_found) unless Current.account.feature_enabled?('whatsapp_templates_journey')
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :create?, policy_class: WhatsappTemplatePolicy)
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("whatsapp_templates.errors.#{code}") }, status: status
  end
end

# "Criar com IA" e "Melhorar com IA" da tela de Modelos do WhatsApp (#1333, épico #1320). Escreve opções de texto com o
# redator compartilhado (`Whatsapp::Templates::Redacao`); nada é salvo nem enviado à Meta.
#
#   POST /api/v1/accounts/:account_id/whatsapp_template_suggestions
#     criar:    { mode: 'create', goal:, tone?, category? }
#     melhorar: { mode: 'improve', text: (com {{chave.do.catalogo}}), improvements: [...], tone?, category?, meta_reason? }
#   => { payload: { status: ok|precisa_mais_info|nao_se_aplica, question, suggestions, options: [...] } }
#
# Mesma porta de escrever modelo: flag `whatsapp_templates_journey` (404 sem ela) e `whatsapp_templates_manage`.
# Sem IA (desligada, sem chave, erro) ou sem opção que passe na conferência: 422 com uma frase simples.
class Api::V1::Accounts::WhatsappTemplateSuggestionsController < Api::V1::Accounts::BaseController
  MODES = %w[create improve].freeze

  before_action :ensure_journey_enabled
  before_action :check_authorization

  def create
    result = write
    return render_unavailable if result[:status] == 'ok' && result[:opcoes].empty?

    render json: { payload: payload(result) }
  rescue Whatsapp::Templates::Redacao::Invalida
    render_error('suggestion_invalid')
  rescue Ai::Redacao::Escrever::Indisponivel => e
    Rails.logger.info("[whatsapp_templates][redacao] unavailable account_id=#{Current.account.id} reason=#{e.message}")
    render_unavailable
  end

  private

  def write
    mode = params[:mode].to_s
    raise Whatsapp::Templates::Redacao::Invalida, 'mode' unless MODES.include?(mode)

    writer = Whatsapp::Templates::Redacao.new(account: Current.account)
    mode == 'create' ? create_with(writer) : improve_with(writer)
  end

  def create_with(writer)
    writer.criar(objetivo: params[:goal].to_s, tom: params[:tone].to_s, tipo: params[:category].to_s)
  end

  def improve_with(writer)
    writer.melhorar(texto: params[:text].to_s, melhorias: Array(params[:improvements]), tom: params[:tone].to_s,
                    tipo: params[:category].to_s, recusa: params[:meta_reason].to_s)
  end

  def payload(result)
    { status: result[:status], question: result[:pergunta], suggestions: result[:sugestoes],
      options: result[:opcoes].map { |option| option_json(option) } }
  end

  def option_json(option)
    whatsapp = option[:whatsapp]
    { text: option[:texto], keys: option[:chaves_usadas], category: option[:categoria_prevista],
      reason: option[:motivo_categoria], changes: option[:o_que_mudou], name: whatsapp[:nome_sugerido],
      header: whatsapp[:cabecalho], footer: whatsapp[:rodape], buttons: whatsapp[:botoes] }
  end

  def ensure_journey_enabled
    render_error('feature_disabled', :not_found) unless Current.account.feature_enabled?('whatsapp_templates_journey')
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :create?, policy_class: WhatsappTemplatePolicy)
  end

  def render_unavailable
    render_error('suggestion_unavailable')
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("whatsapp_templates.errors.#{code}") }, status: status
  end
end

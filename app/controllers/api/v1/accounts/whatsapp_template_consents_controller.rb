# Autorização do dono para o sistema criar modelos da Meta (#1586, épico #1585). Tela: Modelos › Autorização.
#
#   GET  /api/v1/accounts/:account_id/whatsapp_template_consent
#   POST /api/v1/accounts/:account_id/whatsapp_template_consent  { operacao: 'ligar'|'desligar', marcas: ['utility', 'marketing'],
#                                                                  versao_aviso: (a versão que a tela mostrou) }
#   => { payload: { utility: { ativo, mudanca: { acao, por, em } | null }, marketing: { ... },
#                   aviso: { versao, vigente_desde, moeda, precos, textos: { ligar: {...}, desligar: {...} }, limites } } }
#   Recusado: 422 { error: acao_invalida | marca_invalida | utility_desligada, message } ou 409 aviso_mudou.
#
# Ver e mudar: administrador e `whatsapp_templates_manage` (o mesmo gate de criar modelos na tela de Modelos). Mudar
# também pede a flag `whatsapp_templates_journey` da conta (sem ela, 404), como escrever modelos.
class Api::V1::Accounts::WhatsappTemplateConsentsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_journey_enabled, only: :create

  def show
    render json: { payload: consentimento.estado }
  end

  def create
    estado = consentimento.mudar(acao: params[:operacao].to_s, marcas: Array(params[:marcas]), versao: params[:versao_aviso].to_s)
    render json: { payload: estado }
  rescue Whatsapp::Templates::Consentimento::Invalida => e
    render json: { error: e.codigo, message: I18n.t("whatsapp_templates.consent.errors.#{e.codigo}") },
           status: e.codigo == 'aviso_mudou' ? :conflict : :unprocessable_entity
  end

  private

  def consentimento
    Whatsapp::Templates::Consentimento.new(account: Current.account, user: Current.user)
  end

  def ensure_journey_enabled
    return if Current.account.feature_enabled?('whatsapp_templates_journey')

    render json: { error: 'feature_disabled', message: I18n.t('whatsapp_templates.errors.feature_disabled') }, status: :not_found
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :create?, policy_class: WhatsappTemplatePolicy)
  end
end

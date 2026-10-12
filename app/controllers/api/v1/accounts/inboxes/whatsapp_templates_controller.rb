# API de Modelos do WhatsApp oficial de uma caixa (#1330, épico #1320). Só caixas `whatsapp_cloud` com WABA gravada.
# A WABA é sempre a da caixa: nenhum parâmetro do pedido escolhe WABA, e o id do modelo só vale se estiver na lista
# sincronizada desta caixa (e a Meta confirmar que é da WABA dela).
# Escrever na Meta (criar, editar, apagar, subir mídia) só com a flag `whatsapp_templates_journey` na conta:
# sem ela, 404 antes de qualquer outra coisa. Listar e "onde está em uso" seguem abertos.
class Api::V1::Accounts::Inboxes::WhatsappTemplatesController < Api::V1::Accounts::BaseController
  WRITE_ACTIONS = %i[create update destroy media].freeze

  before_action :ensure_journey_enabled, only: WRITE_ACTIONS
  before_action :fetch_inbox
  before_action :check_authorization

  rescue_from Whatsapp::Templates::MetaClient::NotFound, with: :template_not_found
  rescue_from Whatsapp::Templates::MetaClient::Unreachable, with: :meta_unreachable
  rescue_from Whatsapp::Templates::MetaClient::MetaError, with: :meta_refused
  rescue_from Whatsapp::Templates::Manager::Refused, with: :refused

  def index
    @inbox.channel.sync_templates if ActiveModel::Type::Boolean.new.cast(params[:refresh])
    render json: { payload: manager.list, meta: { last_synced_at: @inbox.channel.reload.message_templates_last_updated } }
  end

  def create
    render json: manager.create(template_params), status: :created
  end

  def update
    render json: manager.update(params[:id], template_params)
  end

  def destroy
    manager.destroy(params[:id])
    head :no_content
  end

  def media
    return render_error('media_invalid') unless params[:file].respond_to?(:original_filename)

    render json: manager.upload(params[:file]), status: :created
  end

  def usage
    render json: manager.usage(params[:id])
  end

  private

  def ensure_journey_enabled
    render_error('feature_disabled', :not_found) unless Current.account.feature_enabled?('whatsapp_templates_journey')
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    render_error('inbox_not_supported', :not_found) unless Whatsapp::Templates::MetaClient.supported?(@inbox)
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :"#{action_name}?", policy_class: WhatsappTemplatePolicy)
  end

  def manager
    @manager ||= Whatsapp::Templates::Manager.new(inbox: @inbox, user: Current.user, account_user: Current.account_user,
                                                  visible_cards: policy_scope(::Crm::Card))
  end

  # O conteúdo dos componentes (texto, exemplos, botões) vai para a Meta como veio; o `MetaClient` só deixa passar as
  # chaves de componente que a Meta conhece.
  def template_params
    permitted = params.require(:template).permit(:name, :language, :category, :parameter_format, :message_send_ttl_seconds,
                                                 :friendly_name, fields: {},
                                                                 header_media: %i[handle blob_signed_id file_name content_type byte_size])
    components = params[:template][:components]
    return permitted.to_h unless components

    permitted.to_h.merge('components' => Array(components).grep(ActionController::Parameters).map { |item| item.permit!.to_h })
  end

  def template_not_found
    render_error('template_not_found', :not_found)
  end

  def meta_unreachable
    render_error('meta_unreachable', :service_unavailable)
  end

  def meta_refused(error)
    render json: { error: 'meta_refused', message: error.message }, status: :unprocessable_entity
  end

  def refused(error)
    render json: { error: error.code, message: I18n.t("whatsapp_templates.errors.#{error.code}") }.merge(error.details),
           status: :unprocessable_entity
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("whatsapp_templates.errors.#{code}") }, status: status
  end
end

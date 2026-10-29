# API de Modelos do WhatsApp oficial de uma caixa (#1330, épico #1320). Só caixas `whatsapp_cloud` com WABA gravada.
# A WABA é sempre a da caixa: nenhum parâmetro do pedido escolhe WABA, e o id do modelo só vale se estiver na lista
# sincronizada desta caixa (e a Meta confirmar que é da WABA dela).
# Escrever na Meta (criar, editar, apagar, subir mídia) só com a flag `whatsapp_templates_journey` na conta:
# sem ela, 404 antes de qualquer outra coisa. Listar e "onde está em uso" seguem abertos.
class Api::V1::Accounts::Inboxes::WhatsappTemplatesController < Api::V1::Accounts::BaseController
  WRITE_ACTIONS = %i[create update destroy media media_status].freeze

  before_action :ensure_journey_enabled, only: WRITE_ACTIONS
  before_action :fetch_inbox
  before_action :check_authorization
  before_action :ensure_products_enabled, only: %i[create update]

  rescue_from Whatsapp::Templates::MetaClient::NotFound, with: :template_not_found
  rescue_from Whatsapp::Templates::MetaClient::Unreachable, with: :meta_unreachable
  rescue_from Whatsapp::Templates::MetaClient::MetaError, with: :meta_refused
  rescue_from Whatsapp::Templates::Manager::Refused, with: :refused

  # "Atualizar" pede a lista nova à Meta. Se o sync não deu certo (#1382, `SyncFields::Result`), a resposta diz isso com o
  # código (422; 502 quando a Meta não respondeu), em vez de devolver a lista antiga como se fosse nova; a tela lê a lista
  # guardada sem `refresh` e avisa.
  def index
    if ActiveModel::Type::Boolean.new.cast(params[:refresh])
      result = @inbox.channel.sync_templates
      return render_sync_failure(result.code) if result.respond_to?(:ok?) && !result.ok?
    end
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

  # Vídeo que precisa de conversão (#2370) volta 202 com `poll_url`; a tela consulta `media_status` até o resultado.
  def media
    return render_error('media_invalid') unless params[:file].respond_to?(:original_filename)

    result = manager.upload(params[:file])
    return render json: result, status: :created unless result[:conversion_id]

    render json: { status: 'pending', poll_url: media_poll_url(result[:conversion_id]) }, status: :accepted
  end

  # Mesmo formato do `pollAiRequest` da tela: `done` com `result` (o da subida) ou `failed` com `error` e `message`.
  def media_status
    data = Whatsapp::Templates::VideoConversion.read(params[:conversion_id])
    return head :not_found unless data && data['inbox_id'] == @inbox.id && data['account_user_id'] == Current.account_user&.id

    render json: { status: data['status'], result: data['result'], error: data['error'],
                   message: data['error'] && I18n.t("whatsapp_templates.errors.#{data['error']}") }
  end

  def usage
    render json: manager.usage(params[:id])
  end

  private

  def ensure_journey_enabled
    render_error('feature_disabled', :not_found) unless Current.account.feature_enabled?('whatsapp_templates_journey')
  end

  # #1418: modelo com produtos do catálogo só com a flag `whatsapp_campaign_products`. A tela já esconde o formato; o
  # servidor barra também, antes de falar com a Meta.
  def ensure_products_enabled
    return if Current.account.feature_enabled?('whatsapp_campaign_products')
    return unless params[:template].respond_to?(:key?) && Whatsapp::Templates::ProductParams.uses_catalog?(template_params)

    render_error('products_disabled')
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    render_error('inbox_not_supported', :not_found) unless Whatsapp::Templates::MetaClient.supported?(@inbox)
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :"#{action_name}?", policy_class: WhatsappTemplatePolicy)
  end

  def media_poll_url(conversion_id)
    "/api/v1/accounts/#{Current.account.id}/inboxes/#{@inbox.id}/whatsapp_templates/media/#{conversion_id}"
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
                                                                 header_media: %i[handle blob_signed_id file_name content_type byte_size],
                                                                 card_media: %i[card_index blob_signed_id])
    components = params[:template][:components]
    return permitted.to_h unless components

    permitted.to_h.merge('components' => Array(components).grep(ActionController::Parameters).map { |item| item.permit!.to_h })
  end

  # Os quatro abaixo respondem pelo `rescue_from`; o idioma da pessoa (ou da conta) vem do BaseController (#1419, #2110).
  def template_not_found
    render_error('template_not_found', :not_found)
  end

  def meta_unreachable
    render_error('meta_unreachable', :service_unavailable)
  end

  # A tela nunca recebe o texto cru da Meta (#1394): sem texto nosso, vai o genérico e o `code` (`meta_text`). Com texto
  # nosso, o `code` é a chave dele: traduzimos aqui, no idioma da pessoa, em vez do `message` que o serviço montou no
  # idioma da conta (o mesmo serviço roda fora de pedido, no sync).
  def meta_refused(error)
    message = I18n.t("whatsapp_templates.errors.#{error.own_text ? error.code : 'meta_text'}")
    render json: { error: 'meta_refused', code: error.code, message: message }, status: :unprocessable_entity
  end

  def refused(error)
    render json: { error: error.code, message: I18n.t("whatsapp_templates.errors.#{error.code}") }.merge(error.details),
           status: :unprocessable_entity
  end

  def render_sync_failure(code)
    status = code == 'meta_unreachable' ? :bad_gateway : :unprocessable_entity
    message_key = code == 'permission_denied' ? 'permission_denied' : 'sync_failed'
    render json: { error: 'sync_failed', code: code, message: I18n.t("whatsapp_templates.errors.#{message_key}") }, status: status
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("whatsapp_templates.errors.#{code}") }, status: status
  end
end

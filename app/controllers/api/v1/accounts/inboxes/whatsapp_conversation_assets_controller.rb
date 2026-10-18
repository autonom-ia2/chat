# O que a conversa precisa para mandar modelo de produto e carrossel (#1716, épico #1320), para quem atende a caixa
# (`Whatsapp::Templates::ConversationAssetsPolicy`), sem a tela de Modelos:
#   GET  catalog                 — o catálogo da WABA da caixa (como `WhatsappCatalogsController#show`);
#   GET  products?q=&after=&ids= — os produtos aprovados, ou os escolhidos relidos (como `#products`);
#   GET  template?name=&language= — do perfil do modelo, os campos que o contato preenche e as fotos aprovadas dos cartões;
#   POST media (file)            — a foto do computador para um cartão: só JPG ou PNG de até 5 MB, arquivo desta conta, sem
#                                  ir à Meta; a referência expira em um dia (vale para este envio).
# Catálogo e produtos seguem com a flag `whatsapp_campaign_products`. A WABA e o catálogo são sempre os da caixa.
class Api::V1::Accounts::Inboxes::WhatsappConversationAssetsController < Api::V1::Accounts::Inboxes::WhatsappCatalogsController
  CARD_PHOTO_TYPES = %w[image/jpeg image/png].freeze

  skip_before_action :ensure_feature_enabled, only: %i[template media]

  def catalog
    show
  end

  def template
    profile = WhatsappTemplateProfile.for_inbox(@inbox).find_by(name: params[:name].to_s, language: params[:language].to_s)
    render json: { fields: profile&.fields || {},
                   card_media: profile ? Whatsapp::Templates::CardMedia.listed(profile).select { |media| media['blob_signed_id'] } : [] }
  end

  def media
    file = params[:file]
    return render_error('card_photo_invalid') unless file.respond_to?(:original_filename)

    content_type = Marcel::MimeType.for(file)
    file.rewind
    return render_error('card_photo_invalid') unless card_photo?(content_type, file.size)

    render json: conversation_photo(file, content_type), status: :created
  end

  private

  def check_authorization
    authorize(@inbox, :"#{action_name}?", policy_class: Whatsapp::Templates::ConversationAssetsPolicy)
  end

  def card_photo?(content_type, size)
    CARD_PHOTO_TYPES.include?(content_type) && Whatsapp::Templates::HeaderMedia.upload_allowed?(content_type, size)
  end

  def conversation_photo(file, content_type)
    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: content_type, identify: false,
                                                  metadata: { 'account_id' => @inbox.account_id, 'conversation_upload' => true })
    { blob_signed_id: blob.signed_id(expires_in: Whatsapp::Templates::HeaderMedia::URL_TTL), file_name: blob.filename.to_s }
  end
end

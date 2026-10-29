# O que a API de Modelos faz numa caixa do WhatsApp oficial (#1330): lista (lista sincronizada + perfis), cria, edita,
# apaga e sobe o arquivo de exemplo do topo (duplicar é criar: a tela manda o conteúdo da cópia). A Meta é falada só
# pelo `MetaClient` (WABA e token da caixa).
#
# Regras:
# - modelo do sistema (`SystemTemplates`) não é criado, alterado nem apagado por aqui (a cópia pela tela pode);
# - modelo em uso (`Usage`, inclusive uso que a pessoa não vê) não é apagado nem tem o conteúdo alterado;
# - criar e alterar o conteúdo só chegam à Meta com a forma que ela exige (`SubmitFormat`, #1380): o que não
#   passa volta 422 com o código, sem nenhuma chamada à Graph;
# - a categoria não muda na edição (`SubmitFormat.edit_problems`, #1394): pedir outra volta 422
#   `category_change_not_allowed`, sem chamada à Graph; trocar de tipo é criar um modelo novo;
# - o estado do Chat2You fica no perfil (`WhatsappTemplateProfile`), que sobrevive ao sync. A lista da caixa só recebe o
#   modelo criado/alterado até o próximo sync trazer a versão da Meta, gravado por `ChannelList` (trava na linha do
#   canal; o mesmo escritor do sync e do `Garantir`, #1382).
class Whatsapp::Templates::Manager
  # Pedido recusado por regra nossa: `code` vai para a tela traduzido; `details` completa (o uso, o modelo que já existe).
  class Refused < StandardError
    attr_reader :code, :details

    def initialize(code, details = {})
      super(code)
      @code = code
      @details = details
    end
  end

  include Whatsapp::Templates::StoredMedia

  Draft = Struct.new(:profile, :blob, :card_blobs)
  # A categoria não está aqui: não muda na edição (#1394; a igual é ignorada e o modelo não volta para análise por ela).
  CONTENT_KEYS = %w[components message_send_ttl_seconds].freeze

  def initialize(inbox:, user:, account_user:, visible_cards:)
    @inbox = inbox
    @user = user
    @account_user = account_user
    @visible_cards = visible_cards
  end

  # Cada modelo leva a saúde dos últimos 30 dias (`health`, #1338), calculada de uma vez para a lista toda.
  def list
    profiles = WhatsappTemplateProfile.for_inbox(@inbox).with_attached_card_files.with_attached_header_file.index_by(&:key)
    health = Whatsapp::Templates::Health.new(inbox: @inbox, templates: synced).perform
    synced.map do |template|
      key = WhatsappTemplateProfile.key_for(template['name'], template['language'])
      present(template, profiles[key]).merge('health' => health[key])
    end
  end

  def create(attrs)
    attrs = attrs.to_h.deep_stringify_keys
    raise Refused, 'system_template' if Whatsapp::Templates::SystemTemplates.system?(attrs['name'])

    check_format!(attrs)
    draft = prepare_profile(attrs, attrs)
    outcome = client.create(attrs)
    raise Refused.new('name_taken', template: outcome.template) unless outcome.created

    Whatsapp::Templates::ChannelList.upsert!(@inbox.channel, outcome.template)
    present(outcome.template, save_profile(draft, outcome.template))
  end

  def update(template_id, attrs)
    attrs = attrs.to_h.deep_stringify_keys
    template = protected_template!(template_id, change: true)
    check_edit!(template, attrs)
    content = attrs.slice(*CONTENT_KEYS)
    check_format!(assume_stored_media(template.slice('category', 'components').merge(content), template)) if content.any?
    draft = prepare_profile(template, attrs)
    if content.any?
      content = with_stored_media(content, template)
      client.update(template['id'], template['name'], content)
      template = template.merge(content).merge('status' => 'PENDING')
      Whatsapp::Templates::ChannelList.upsert!(@inbox.channel, template)
    end
    present(template, save_profile(draft, template))
  end

  def destroy(template_id)
    template = protected_template!(template_id)
    client.delete_by_id(template['id'], template['name'])
    profile_for(template)&.destroy!
    Whatsapp::Templates::ChannelList.remove!(@inbox.channel, template)
    true
  end

  # Sobe o arquivo de exemplo (`MediaUpload`); vídeo que precisa de conversão volta com `conversion_id` (#2370).
  def upload(file)
    Whatsapp::Templates::MediaUpload.new(inbox: @inbox, account_user: @account_user).perform(file)
  end

  def usage(template_id)
    template = find!(template_id)
    usage_for(template)
  end

  private

  def client
    @client ||= Whatsapp::Templates::MetaClient.new(inbox: @inbox)
  end

  def check_format!(template)
    problems = Whatsapp::Templates::SubmitFormat.problems(template)
    raise Refused.new(problems.first, problems: problems) if problems.any?
  end

  def check_edit!(template, attrs)
    problems = Whatsapp::Templates::SubmitFormat.edit_problems(template, attrs)
    raise Refused.new(problems.first, problems: problems) if problems.any?
  end

  def synced
    list = @inbox.channel.message_templates
    list.is_a?(Array) ? list.select { |item| item.is_a?(Hash) } : []
  end

  # Só o que está na lista da WABA desta caixa; id de outra WABA não existe aqui.
  def find!(template_id)
    synced.find { |item| item['id'].to_s == template_id.to_s } || raise(Whatsapp::Templates::MetaClient::NotFound)
  end

  # Alterar (`change`) aceita campanha parada pelo modelo; apagar não (Usage#blocks_change).
  def protected_template!(template_id, change: false)
    template = find!(template_id)
    raise Refused, 'system_template' if system_owner(template).present?

    usage = usage_for(template)
    blocked, hidden = change ? usage.values_at(:blocks_change, :blocks_change_hidden) : usage.values_at(:in_use, :uso_oculto)
    raise Refused.new(hidden ? 'in_use_hidden' : 'in_use', usage: usage) if blocked

    template
  end

  def usage_for(template)
    Whatsapp::Templates::Usage.new(inbox: @inbox, name: template['name'], language: template['language'],
                                   account_user: @account_user, visible_cards: @visible_cards).perform
  end

  def system_owner(template, profile = profile_for(template))
    profile&.system_owner.presence || Whatsapp::Templates::SystemTemplates.owner_for(template['name'])
  end

  def present(template, profile)
    template.merge('friendly_name' => profile&.friendly_name.presence || template['name'],
                   'fields' => profile&.fields || {}, 'header_media' => profile&.header_media || {},
                   'system_owner' => system_owner(template, profile), 'profile_id' => profile&.id,
                   'card_media' => card_media(profile), 'header_file_name' => header_file_name(profile),
                   'header_file_preview_url' => header_file_preview_url(profile))
  end

  # A prévia da campanha mostra a foto aprovada (#1465): link de leitura assinado, que expira; só para foto.
  def header_file_preview_url(profile)
    file = profile&.header_file
    return unless file&.attached? && file.content_type.to_s.start_with?('image/')

    Whatsapp::Templates::HeaderMedia.signed_media(file)['media_url']
  end

  # O arquivo do topo de fato guardado (#1465): a campanha mostra "vai a foto aprovada" e, sem ele, pede para escolher.
  # `header_media` pode ter o nome sem o arquivo (só o handle da Meta), por isso não serve para isso.
  def header_file_name(profile)
    profile&.header_file&.attached? ? profile.header_file.filename.to_s : nil
  end

  # O arquivo guardado de cada cartão do carrossel (#1334): a campanha mostra "vai a foto aprovada"; a conversa monta a
  # galeria do modelo (#1716, `CardMedia.listed`).
  def card_media(profile)
    profile ? Whatsapp::Templates::CardMedia.listed(profile) : []
  end

  def profile_for(template)
    WhatsappTemplateProfile.for_inbox(@inbox).find_by(name: template['name'], language: template['language'])
  end

  # O perfil é montado e conferido ANTES de falar com a Meta: perfil inválido não deixa modelo criado lá sem perfil aqui.
  def prepare_profile(template, attrs)
    profile = profile_for(template) || new_profile(template)
    profile.friendly_name = attrs['friendly_name'] if attrs.key?('friendly_name')
    profile.fields = attrs['fields'].to_h if attrs.key?('fields')
    media = attrs['header_media']
    profile.header_media = media.slice('handle', 'file_name', 'content_type', 'byte_size') if media.is_a?(Hash)
    raise Refused.new('invalid_profile', errors: profile.errors.full_messages) unless profile.valid?

    Draft.new(profile, media.is_a?(Hash) ? media_blob(media) : nil, card_blobs(profile, attrs['card_media']))
  end

  # #1334: { posição do cartão => arquivo } do que subiu agora; a campanha do carrossel usa a mesma mídia aprovada.
  # Conferido antes de falar com a Meta. O arquivo que já é deste cartão fica; ligado a outro registro, é recusado.
  def card_blobs(profile, card_media)
    pairs = Array(card_media).grep(Hash).map { |media| card_pair(media) }
    raise Refused, 'media_invalid' unless pairs.map(&:first).uniq.size == pairs.size

    fresh = pairs.to_h.reject { |index, blob| same_card_file?(profile, index, blob) }
    raise Refused, 'media_invalid' if fresh.values.any? { |blob| blob.attachments.exists? }

    fresh
  end

  def card_pair(media)
    [card_index!(media), media_blob(media) || raise(Refused, 'media_invalid')]
  end

  def same_card_file?(profile, index, blob)
    profile.persisted? && profile.card_file(index)&.blob_id == blob.id
  end

  # A Meta aceita de 2 a 10 cartões (SubmitFormat::CARDS).
  def card_index!(media)
    index = Integer(media['card_index'].to_s, exception: false)
    raise Refused, 'media_invalid' unless index&.between?(0, Whatsapp::Templates::SubmitFormat::CARDS.max - 1)

    index
  end

  def new_profile(template)
    WhatsappTemplateProfile.new(account_id: @inbox.account_id, inbox: @inbox, waba_id: @inbox.channel.waba_id,
                                name: template['name'], language: template['language'], created_by: @user)
  end

  def save_profile(draft, template)
    profile = draft.profile
    profile.meta_template_id = template['id'].presence || profile.meta_template_id
    profile.save!
    profile.header_file.attach(draft.blob) if draft.blob
    draft.card_blobs.each { |index, blob| attach_card_file(profile, index, blob) }
    profile
  end

  def attach_card_file(profile, index, blob)
    profile.card_file(index)&.purge_later
    blob.update!(metadata: blob.metadata.merge('card_index' => index))
    profile.card_files.attach(blob)
  end

  # Só arquivo que o upload desta conta gravou.
  def media_blob(media)
    signed_id = media['blob_signed_id'].presence
    return unless signed_id

    blob = ActiveStorage::Blob.find_signed(signed_id)
    raise Refused, 'media_invalid' unless blob && blob.metadata['account_id'].to_s == @inbox.account_id.to_s

    blob
  end
end

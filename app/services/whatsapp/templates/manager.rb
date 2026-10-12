# O que a API de Modelos faz numa caixa do WhatsApp oficial (#1330): lista (lista sincronizada + perfis), cria, edita,
# apaga, duplica e sobe o arquivo de exemplo do topo. A Meta é falada só pelo `MetaClient` (WABA e token da caixa).
#
# Regras:
# - modelo do sistema (`SystemTemplates`) não é criado, alterado nem apagado por aqui; duplicar pode;
# - modelo em uso (`Usage`, inclusive uso que a pessoa não vê) não é apagado nem tem o conteúdo alterado;
# - criar, alterar o conteúdo e duplicar só chegam à Meta com a forma que ela exige (`SubmitFormat`, #1380): o que não
#   passa volta 422 com o código, sem nenhuma chamada à Graph;
# - o estado do Chat2You fica no perfil (`WhatsappTemplateProfile`), que sobrevive ao sync. A lista da caixa só recebe o
#   modelo criado/alterado até o próximo sync trazer a versão da Meta (mesmo caminho do `NoticeTemplates::Creator`).
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

  include Whatsapp::Templates::HeaderMedia

  Draft = Struct.new(:profile, :blob)
  CONTENT_KEYS = %w[category components message_send_ttl_seconds].freeze

  def initialize(inbox:, user:, account_user:, visible_cards:)
    @inbox = inbox
    @user = user
    @account_user = account_user
    @visible_cards = visible_cards
  end

  def list
    profiles = WhatsappTemplateProfile.for_inbox(@inbox).index_by(&:key)
    synced.map { |template| present(template, profiles[WhatsappTemplateProfile.key_for(template['name'], template['language'])]) }
  end

  def create(attrs)
    attrs = attrs.to_h.deep_stringify_keys
    raise Refused, 'system_template' if Whatsapp::Templates::SystemTemplates.system?(attrs['name'])

    check_format!(attrs)
    draft = prepare_profile(attrs, attrs)
    outcome = client.create(attrs)
    raise Refused.new('name_taken', template: outcome.template) unless outcome.created

    record(outcome.template)
    present(outcome.template, save_profile(draft, outcome.template))
  end

  def update(template_id, attrs)
    attrs = attrs.to_h.deep_stringify_keys
    template = protected_template!(template_id, change: true)
    content = attrs.slice(*CONTENT_KEYS)
    check_format!(assume_stored_media(template.slice('category', 'components').merge(content), template)) if content.any?
    draft = prepare_profile(template, attrs)
    if content.any?
      content = with_stored_media(content, template)
      client.update(template['id'], template['name'], content)
      template = record(template.merge(content).merge('status' => 'PENDING'))
    end
    present(template, save_profile(draft, template))
  end

  def destroy(template_id)
    template = protected_template!(template_id)
    client.delete_by_id(template['id'], template['name'])
    profile_for(template)&.destroy!
    forget(template)
    true
  end

  # Cópia com outro nome (modelo do sistema também). Topo com mídia precisa de um arquivo novo na Meta: o handle do pedido
  # ou o arquivo guardado no perfil do original.
  def duplicate(template_id, attrs)
    attrs = attrs.to_h.deep_stringify_keys
    source = find!(template_id)
    # O arquivo do topo sobe de novo logo abaixo; a forma do resto é conferida antes de qualquer chamada à Meta.
    check_format!(source.merge('components' => fill_media(source['components'], STORED_MEDIA)))
    profile = profile_for(source)
    handle = attrs.dig('header_media', 'handle').presence || reupload(profile)
    copy = { 'friendly_name' => attrs['friendly_name'], 'fields' => profile&.fields,
             'header_media' => attrs['header_media'] || profile&.header_media }
    copied = create(duplicate_body(source, attrs, handle).merge(copy.compact))
    share_media(profile, copied['profile_id']) unless attrs.dig('header_media', 'blob_signed_id')
    copied
  end

  # O tipo do arquivo é o que o conteúdo diz (Marcel, o mesmo do ActiveStorage), não o que o navegador declarou.
  def upload(file)
    content_type = Marcel::MimeType.for(file, name: file.original_filename, declared_type: file.content_type)
    file.rewind
    handle = client.upload_media(io: file, file_name: file.original_filename, content_type: content_type)
    file.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: content_type,
                                                  identify: false, metadata: { 'account_id' => @inbox.account_id })
    { handle: handle, blob_signed_id: blob.signed_id, file_name: blob.filename.to_s, content_type: blob.content_type,
      byte_size: blob.byte_size }
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
                   'system_owner' => system_owner(template, profile), 'profile_id' => profile&.id)
  end

  def duplicate_body(source, attrs, handle)
    { 'name' => attrs['name'], 'language' => attrs['language'].presence || source['language'],
      'category' => source['category'], 'parameter_format' => source['parameter_format'],
      'components' => copy_components(source['components'], handle) }.compact
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

    Draft.new(profile, media.is_a?(Hash) ? media_blob(media) : nil)
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
    profile
  end

  # Só arquivo que o upload desta conta gravou.
  def media_blob(media)
    signed_id = media['blob_signed_id'].presence
    return unless signed_id

    blob = ActiveStorage::Blob.find_signed(signed_id)
    raise Refused, 'media_invalid' unless blob && blob.metadata['account_id'].to_s == @inbox.account_id.to_s

    blob
  end

  # A cópia guarda o mesmo arquivo do original (para duplicar de novo sem pedir o arquivo).
  def share_media(source_profile, profile_id)
    return unless profile_id && source_profile&.header_file&.attached?

    WhatsappTemplateProfile.find(profile_id).header_file.attach(source_profile.header_file.blob)
  end

  # Põe (ou troca) o modelo na lista da caixa até o próximo sync trazer a lista da Meta.
  def record(template)
    others = synced.reject { |item| same?(item, template) }
    write_list(others + [template])
    template
  end

  def forget(template)
    write_list(synced.reject { |item| same?(item, template) })
  end

  def same?(item, template)
    item['name'] == template['name'] && item['language'].to_s.casecmp?(template['language'].to_s)
  end

  def write_list(templates)
    @inbox.channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    @inbox.account.update_cache_key('inbox')
  end
end

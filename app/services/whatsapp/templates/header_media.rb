# O arquivo do topo (foto, vídeo ou documento) de um modelo quando ele é alterado ou duplicado (#1380). O handle que a
# Meta deu na criação expira, então nunca é reaproveitado: sobe de novo o arquivo guardado no perfil
# (`WhatsappTemplateProfile#header_file`). Sem arquivo guardado, a pessoa escolhe o arquivo de novo (media_required).
# Incluído no `Whatsapp::Templates::Manager`; usa `client` e `profile_for` dele.
module Whatsapp::Templates::HeaderMedia
  MEDIA_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  # Marca do arquivo que ainda vai subir: a conferência roda antes, sem falar com a Meta, contando com ele.
  STORED_MEDIA = 'stored_media'.freeze

  private

  def reupload(profile)
    return unless profile&.header_file&.attached?

    profile.header_file.open do |file|
      client.upload_media(io: file, file_name: profile.header_file.filename.to_s, content_type: profile.header_file.content_type)
    end
  end

  def copy_components(components, handle)
    Array(components).map do |component|
      component = component.deep_dup
      next component unless media_header?(component)
      raise Whatsapp::Templates::Manager::Refused, 'media_required' if handle.blank?

      component.merge('example' => { 'header_handle' => [handle] })
    end
  end

  # Alterar sem arquivo novo: a tela manda o topo sem handle.
  def assume_stored_media(body, template)
    return body unless media_pending?(body['components']) && profile_for(template)&.header_file&.attached?

    body.merge('components' => fill_media(body['components'], STORED_MEDIA))
  end

  def with_stored_media(content, template)
    return content unless media_pending?(content['components'])

    content.merge('components' => fill_media(content['components'], reupload(profile_for(template))))
  end

  def media_pending?(components)
    Array(components).any? { |component| media_header?(component) && !handle?(component) }
  end

  def fill_media(components, handle)
    Array(components).map do |component|
      next component unless media_header?(component) && !handle?(component)

      component.merge('example' => { 'header_handle' => [handle] })
    end
  end

  def media_header?(component)
    component.is_a?(Hash) && component['type'].to_s.casecmp?('HEADER') && MEDIA_FORMATS.include?(component['format'].to_s.upcase)
  end

  def handle?(component)
    Array(component.dig('example', 'header_handle')).any?(&:present?)
  end
end

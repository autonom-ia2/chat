# O que uma mensagem encaminhada vira no destino (#1702): a lista de pedidos para o Messages::MessageBuilder, o mesmo
# caminho do envio pelo painel. Quase sempre é um pedido só; vários contatos compartilhados viram um cartão cada.
#
# - Texto e arquivos (foto, vídeo, áudio, documento): o mesmo `content` e os anexos pelo `signed_id` do blob que já está
#   guardado. O ActiveStorage liga o mesmo blob ao anexo novo, sem baixar nem subir de novo; e o blob não é apagado
#   enquanto outro anexo o usa (ActiveStorage::Blob recusa o destroy com anexos, e o PurgeJob descarta). Documento
#   continua documento (ConversaCanal::ComoDocumento) e áudio de voz continua de voz.
# - Localização e contato saem como envio rico (`content_attributes.rich_message`, RichMessages::Types::Location e
#   ::Contact), o formato que a caixa de resposta já manda: o que a empresa mandou copia o `rich_message`; o que o
#   cliente mandou é montado de `shared_location` (ou do anexo de localização) e do anexo de contato.
# - Os outros formatos ricos (botões, opções, formulário) não se copiam: vai o texto do corpo, se houver.
class ConversaCanal::CopiaEncaminhada
  RICOS = %w[location contact].freeze
  ARQUIVOS = %w[image audio video file].freeze
  CAMPOS_DA_LOCALIZACAO = %w[latitude longitude name address].freeze
  NOME_MAX = 100

  def initialize(mensagem)
    @mensagem = mensagem
  end

  # -> [{ content:, attachments:, content_attributes:, ... }]; vazio quando não há o que mandar.
  def envios
    @envios ||= montar
  end

  private

  def montar
    return [rico(atributos['rich_message'])] if RICOS.include?(atributos.dig('rich_message', 'type'))

    localizacao = localizacao_recebida
    return [rico(localizacao.merge('type' => 'location'))] if localizacao

    contatos = anexos_do_tipo('contact').filter_map { |anexo| contato(anexo) }
    return contatos.map { |cartao| rico(cartao) } if contatos.any?

    comum
  end

  def atributos
    @atributos ||= @mensagem.content_attributes.to_h.with_indifferent_access
  end

  def anexos_do_tipo(tipo)
    @mensagem.attachments.select { |anexo| anexo.file_type == tipo }
  end

  def rico(payload)
    { content: '', private: false, message_type: 'outgoing', content_attributes: { 'rich_message' => payload.to_h } }
  end

  def localizacao_recebida
    compartilhada = atributos['shared_location']
    return compartilhada.to_h.slice(*CAMPOS_DA_LOCALIZACAO) if compartilhada.respond_to?(:to_h) && compartilhada.present?

    anexo = anexos_do_tipo('location').first
    return if anexo.nil?

    { 'latitude' => anexo.coordinates_lat, 'longitude' => anexo.coordinates_long, 'name' => uma_linha(anexo.fallback_title) }.compact
  end

  # Contato recebido: nome em meta.firstName/lastName e telefone em fallback_title (como o balão lê).
  def contato(anexo)
    meta = anexo.meta.to_h
    telefone = anexo.fallback_title.to_s.strip
    return if telefone.blank?

    telefone = "+#{telefone}" unless telefone.start_with?('+')
    nome = uma_linha([meta['firstName'], meta['lastName']].compact.join(' ')) || telefone
    { 'type' => 'contact', 'name' => nome, 'phone' => telefone, 'wa_id' => telefone.delete('^0-9') }
  end

  def uma_linha(texto)
    texto.to_s.lines.first.to_s.strip.first(NOME_MAX).presence
  end

  def comum
    arquivos = arquivos_guardados
    return [] if texto.blank? && arquivos.empty?

    [{
      content: texto, private: false, message_type: 'outgoing',
      attachments: arquivos.map { |anexo| anexo.file.blob.signed_id },
      document_indexes: arquivos.each_index.select { |posicao| arquivos[posicao].file_type == 'file' },
      is_voice_message: arquivos.any? { |anexo| anexo.meta.to_h['is_voice_message'] == true }
    }]
  end

  # Mandada pelo celular (#1941): o eco antigo do WAHA comum foi gravado com o prefixo do conector; ele não vai junto.
  def texto
    return @mensagem.content unless atributos['external_echo'].present? && @mensagem.content.to_s.start_with?(Waha::EcoDoCelular::PREFIXO)

    Waha::EcoDoCelular.sem_prefixo(@mensagem.content).presence
  end

  def arquivos_guardados
    @mensagem.attachments.select { |anexo| ARQUIVOS.include?(anexo.file_type) && anexo.file.attached? }
  end
end

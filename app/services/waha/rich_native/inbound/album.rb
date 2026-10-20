# `waha_album` (chat#1709, rodada 2): o cabeçalho de álbum ("Mensagem de Álbum Recebida"), que o conector cria antes das
# fotos, { expected_images, expected_videos }. As fotos chegam depois, uma mensagem cada; a pele (#1702,
# agruparAlbuns.js) junta até a quantidade anunciada, então a chave FICA na mensagem, só com as duas contagens:
# - com a flag, o cabeçalho vira atividade escondida (some a bolha vazia, a IA não responde a ele e a conversa não
#   sobe) e leva a chave junto;
# - sem a flag, a mensagem recebida fica como na main e também leva a chave (Waha::RichNative::Inbound.apply_without_flag).
# Só vale o que vem do conector: de qualquer outro usuário a chave sai, como as outras `waha_*` (Inbound.before_create).
# Contagem fora do que o WhatsApp manda (#1831b): cada uma inteira de 0 a MAX e a soma acima de 0; senão a chave não
# é gravada e as fotos aparecem soltas, como a tela (albumDoWaha.js) já trata.
module Waha::RichNative::Inbound::Album
  KEY = 'waha_album'.freeze
  COUNTS = %w[expected_images expected_videos].freeze
  MAX = 100

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    album = counts(data)
    Waha::RichNative::Inbound.hide!(message, 'album', album ? { KEY => album } : {})
  end

  # Sem a flag: a recebida comum só guarda as contagens.
  def keep(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    album = counts(data)
    return if album.nil?

    message.content_attributes = message.content_attributes.to_h.merge(KEY => album)
  end

  # { expected_images, expected_videos }, ou nil quando não é um álbum válido. Contagem ausente ou nula conta 0, como na
  # tela. O conector é JS: 2.0 chega aqui como 2 (JSON.stringify), então só inteiro de verdade passa.
  def counts(data)
    values = data.stringify_keys
    album = COUNTS.index_with { |name| values[name] || 0 }
    return unless album.values.all? { |value| value.is_a?(Integer) && value.between?(0, MAX) } && album.values.sum.positive?

    album
  end
end

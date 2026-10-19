# `waha_album` (chat#1709, rodada 2): o cabeçalho de álbum ("Mensagem de Álbum Recebida"), que o conector cria antes das
# fotos, { expected_images, expected_videos }. As fotos chegam depois, uma mensagem cada; a pele (#1702,
# agruparAlbuns.js) junta até a quantidade anunciada, então a chave FICA na mensagem, só com as duas contagens:
# - com a flag, o cabeçalho vira atividade escondida (some a bolha vazia, a IA não responde a ele e a conversa não
#   sobe) e leva a chave junto;
# - sem a flag, a mensagem recebida fica como na main e também leva a chave (Waha::RichNative::Inbound.apply_without_flag).
# Só vale o que vem do conector: de qualquer outro usuário a chave sai, como as outras `waha_*` (Inbound.before_create).
module Waha::RichNative::Inbound::Album
  KEY = 'waha_album'.freeze
  COUNTS = %w[expected_images expected_videos].freeze

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    Waha::RichNative::Inbound.hide!(message, 'album', KEY => counts(data))
  end

  # Sem a flag: a recebida comum só guarda as contagens.
  def keep(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    message.content_attributes = message.content_attributes.to_h.merge(KEY => counts(data))
  end

  # { expected_images, expected_videos }: inteiro não negativo; o que não for número inteiro conta 0.
  def counts(data)
    values = data.stringify_keys
    COUNTS.index_with { |name| values[name].is_a?(Integer) && values[name].positive? ? values[name] : 0 }
  end
end

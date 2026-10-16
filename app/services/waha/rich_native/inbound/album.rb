# `waha_album` (chat#1709, rodada 2): o cabeçalho de álbum ("Mensagem de Álbum Recebida"), que o conector cria antes das
# fotos, { expected_images, expected_videos }. Com a flag vira atividade escondida: some a bolha vazia, a IA não
# responde ao cabeçalho e a conversa não sobe. As fotos chegam depois, uma mensagem cada, e o painel já as agrupa
# (mensagens seguidas do mesmo remetente). O conector continua criando o cabeçalho para quem não tem a flag.
module Waha::RichNative::Inbound::Album
  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    Waha::RichNative::Inbound.hide!(message, 'album')
  end
end

# A regra única do emoji de uma reação do WhatsApp (#1702 e chat#1709): um emoji só (um grafema: 👍🏽 e ❤️ têm mais de um
# código, mas são um desenho) ou vazio para tirar a reação. Letra, número e sinal do teclado (ASCII: "a", "1", "#") não
# são emoji; o teto de bytes barra o grafema inflado com marcas combinantes. O que não é texto é recusado.
# Quem usa: ConversaCanal::ReacaoDoAtendente (a pele) e Waha::RichNative::Reactions (painel e volta do conector).
module Whatsapp::EmojiDeReacao
  module_function

  def valido?(emoji)
    return false unless emoji.is_a?(String)
    return true if emoji.empty?

    emoji.bytesize <= Whatsapp::ReactionRecorder::MAXIMO_DE_BYTES && !emoji.ascii_only? && emoji.grapheme_clusters.size == 1
  end
end

# O canal de uma caixa nas palavras da ficha de Relacionamentos (#2895): whatsapp, email, instagram, site ou outro. Sai do
# tipo da caixa e de um campo do canal, como em Autonomia::CanaisOcupadosFinder: a caixa de API da WAHA é WhatsApp (a
# maioria das caixas de WhatsApp da plataforma), a Twilio no WhatsApp também, e a página do Facebook com Instagram ligado
# é Instagram. Quem chama já carregou o canal da caixa (preload inbox: :channel).
module Relacionamentos::Ficha::Canal
  DO_TIPO = { 'Channel::Whatsapp' => 'whatsapp', 'Channel::Email' => 'email', 'Channel::Instagram' => 'instagram',
              'Channel::WebWidget' => 'site' }.freeze

  def self.de(caixa)
    return 'whatsapp' if caixa.twilio_whatsapp? || (caixa.api? && caixa.channel.waha_provider?)
    return 'instagram' if caixa.instagram?

    DO_TIPO.fetch(caixa.channel_type, 'outro')
  end
end

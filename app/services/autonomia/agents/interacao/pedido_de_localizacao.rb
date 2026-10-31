# O pedido de localização do agente (#1479 F2): a flag da conta e a regra que vai ao modelo. O formato e a conferência
# do pedido ficam no `Interacao` (tipo `localizacao`); a localização que volta, no `LocalizacaoRecebida`.
module Autonomia::Agents::Interacao::PedidoDeLocalizacao
  FLAG = 'agentes_pedir_localizacao'.freeze
  # A marca da mensagem do pedido (`Interacao.marca`), que vale mesmo quando o formato não saiu.
  MARCA = 'autonomia_pedido_localizacao'.freeze

  INSTRUCAO = <<~TEXTO.strip.freeze
    # Pedir a localização (campo `interacao`, tipo `localizacao`)
    - `localizacao`: só quando a localização do cliente é necessária para o próximo passo (ex.: a unidade mais perto, se o endereço é atendido, onde está o veículo). Nunca por rotina nem "para cadastro".
      `pergunta`: o pedido, curto, que sai junto do botão de enviar a localização (ex.: "Pode me mandar sua localização?"). `reply` traz só o que vem antes dele: NÃO repita o pedido em `reply`. `header`, `botao` e `link`: null; `opcoes`: [].
    - Quando o cliente mandar a localização, ela chega como dado do canal (latitude e longitude). Use para responder; não repita as coordenadas para o cliente.
  TEXTO

  module_function

  # A Fase 2 e a flag da conta.
  def ligado?(account)
    ::Autonomia::Agents::Fase2.ligada?(account) && account.feature_enabled?(FLAG)
  end

  # O turno oferece o pedido: a conta ligada e uma caixa de WhatsApp (oficial, 360dialog, Híbrido ou WAHA), onde o
  # cliente tem como mandar a localização. Nos outros canais o cliente só leria a pergunta.
  def no_turno?(conversation)
    inbox = conversation&.inbox
    inbox.present? && ligado?(conversation.account) && whatsapp?(inbox)
  end

  # O pedido conferido: só o tipo e a pergunta; nil sem pergunta (o botão do WhatsApp precisa de texto).
  def do_modelo(valor)
    pergunta = valor['pergunta'].to_s.strip
    { 'tipo' => 'localizacao', 'pergunta' => pergunta } if pergunta.present?
  end

  # As chaves que a mensagem da interação leva além do formato: o pedido fica marcado mesmo quando o formato não sai
  # (corpo acima do limite da Meta), para a localização que volta ser lida (`LocalizacaoRecebida`).
  def marca(interacao)
    interacao&.dig('tipo') == 'localizacao' ? { MARCA => true } : {}
  end

  def whatsapp?(inbox)
    inbox.channel_type == 'Channel::Whatsapp' || (inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) == true)
  end
end

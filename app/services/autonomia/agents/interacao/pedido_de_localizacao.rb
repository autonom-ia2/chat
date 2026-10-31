# O pedido de localização do agente (#1479 F2): a flag da conta e a regra que vai ao modelo. O formato e a conferência
# do pedido ficam no `Interacao` (tipo `localizacao`); a localização que volta, no `LocalizacaoRecebida`.
module Autonomia::Agents::Interacao::PedidoDeLocalizacao
  FLAG = 'agentes_pedir_localizacao'.freeze

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
end

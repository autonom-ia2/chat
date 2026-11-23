# Para onde vai a pergunta que acabou de chegar (entrega 2 da lista de valor do Guia).
#
# Se a pessoa escreveu enquanto o Guia ainda trabalhava no pedido anterior (`junto_de`), a mensagem entra no
# trabalho em curso (`Pedido.acrescentar`): o Guia a lê na próxima rodada e decide o que fazer — parar, mudar o
# caminho ou seguir. Não sobe um segundo Guia trabalhando ao mesmo tempo, mexendo na mesma conta.
#
# Se não havia trabalho em curso (ou ele já terminou, ou é de outra conversa), a pergunta abre o próprio pedido e
# vai para o `ChatJob`.
module Autonomia::Guide::Encaminhamento
  module_function

  # A conversa é de quem perguntou, na conta dele (`Conversa.de`): é dela que sai o dono do pedido.
  # -> o pedido em curso que vai ler a mensagem, ou nil quando ela abriu um pedido próprio.
  def encaminhar(pedido, conversa:, junto_de:, pergunta:)
    return junto_de if junto?(pedido, conversa, junto_de, pergunta['mensagem'])

    ::Autonomia::Guide::Pedido.abrir(account: conversa.account, user: conversa.user, id: pedido)
    ::Autonomia::Guide::ChatJob.perform_later(pedido, pergunta)
    nil
  end

  # Só o pedido da MESMA conversa: a mensagem de uma conversa não pode ser respondida dentro de outra. Trava
  # ocupada ou Redis fora: a mensagem segue como pergunta comum em vez de dar erro na tela.
  def junto?(pedido, conversa, junto_de, mensagem)
    return false if junto_de.blank?
    return false unless ::Autonomia::Guide::Turno.exists?(pedido_id: junto_de, conversation_id: conversa.id)

    ::Autonomia::Guide::Pedido.acrescentar(junto_de, account: conversa.account, user: conversa.user, nova: pedido,
                                                     mensagem: mensagem) do
      ::Autonomia::Guide::Turno.juntar(pedido, junto_de)
    end
  rescue ::Autonomia::Guide::Pedido::TravaOcupada, Redis::BaseError => e
    Rails.logger.warn("[autonomia][guide][encaminhamento] junto_de=#{junto_de} #{e.class}")
    false
  end
end

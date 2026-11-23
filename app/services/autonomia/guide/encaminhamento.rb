# Para onde vai a pergunta que acabou de chegar (entrega 2 da lista de valor do Guia).
#
# Se a pessoa escreveu enquanto o Guia ainda trabalhava no pedido anterior (`junto_de`), a mensagem entra no
# trabalho em curso (`Pedido.acrescentar`): o Guia a lê na próxima rodada e decide o que fazer — parar, mudar o
# caminho ou seguir. Não sobe um segundo Guia trabalhando ao mesmo tempo, mexendo na mesma conta.
#
# Se não havia trabalho em curso (ou ele já terminou), a pergunta abre o próprio pedido e vai para o `ChatJob`.
module Autonomia::Guide::Encaminhamento
  module_function

  # -> o pedido em curso que vai ler a mensagem, ou nil quando ela abriu um pedido próprio.
  def encaminhar(pedido, account:, user:, junto_de:, pergunta:)
    return junto_de if junto?(pedido, account, user, junto_de, pergunta['mensagem'])

    ::Autonomia::Guide::Pedido.abrir(account: account, user: user, id: pedido)
    ::Autonomia::Guide::ChatJob.perform_later(pedido, pergunta)
    nil
  end

  def junto?(pedido, account, user, junto_de, mensagem)
    junto_de.present? &&
      ::Autonomia::Guide::Pedido.acrescentar(junto_de, account: account, user: user, nova: pedido, mensagem: mensagem)
  end
end

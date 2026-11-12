# O campo de ação que só grava quem pode vê-lo (#2594): o valor de venda do card (#2075, Crm::ValorDeVenda). A tela do
# card já não deixa quem não vê o valor mudá-lo (CardsController#hidden_value_attributes tira o campo do pedido, calado).
# Na automação, o calado viraria um passo que roda e não grava nada: o salvar e o ligar recusam com a frase, e o
# catálogo manda a chave ao editor para ele nem oferecer o campo.
#
# Fechar o card (POST crm/cards/:id/close) fica fora de propósito: ganhar segue aceitando o valor, como na tela.
module Autonomia::Automacao::CampoProtegido
  DO_CARD = { 'value_cents' => ::Crm::ValorDeVenda }.freeze
  TABELA = { 'PATCH crm/cards/:id' => DO_CARD, 'PUT crm/cards/:id' => DO_CARD }.freeze

  module_function

  # A regra do campo (responde `ve?(account_user)` e diz a CHAVE), ou nil.
  def regra(acao, campo) = TABELA.dig(acao.to_s, campo.to_s)

  # Os campos protegidos que o corpo grava e `account_user` não pode ver. O corpo vem plano ou no envelope (`card`).
  def sem_permissao(acao, corpo, account_user)
    campos = TABELA.fetch(acao.to_s, {})
    return [] if campos.empty?

    dentro = corpo.to_h[::Autonomia::Guide::Formatos.para(acao).to_h['envelope']]
    gravados = corpo.to_h.merge(dentro.is_a?(Hash) ? dentro : {})
    campos.select { |campo, regra| gravados.key?(campo) && !regra.ve?(account_user) }.keys
  end
end

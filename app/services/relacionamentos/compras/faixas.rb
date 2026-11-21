# As faixas dos grupos de compra da conta (#3097): quantas compras faz um campeão e até quantos dias depois da última
# ele continua campeão, e depois de quantos dias sem comprar a pessoa passa para "sem comprar" e para o último grupo.
# Ficam em `accounts.settings['grupos_de_compra']`; até alguém ajustar, valem as do padrão (as mesmas da tela,
# gruposDeCompra.js `FAIXAS_PADRAO`).
#
# Mudar as faixas troca o grupo de quem já está na lista, mas não dispara automação: "entrou no grupo" é por venda ou
# pelo tempo (Recalcular com `disparar: false`). Quem pode ajustar é o administrador (o controller confere).
module Relacionamentos::Compras::Faixas
  CHAVE = 'grupos_de_compra'.freeze
  PADRAO = { 'campeao_compras' => 4, 'campeao_dias' => 30, 'em_risco_dias' => 90, 'perdido_dias' => 180 }.freeze
  # Um teto que nenhuma faixa de verdade passa: 10 anos em dias, 1.000 compras.
  MAXIMO = { 'campeao_compras' => 1_000, 'campeao_dias' => 3650, 'em_risco_dias' => 3650, 'perdido_dias' => 3650 }.freeze

  module_function

  def da_conta(account)
    PADRAO.merge(account.settings.to_h.fetch(CHAVE, {}).slice(*PADRAO.keys))
  end

  # Grava as faixas novas e reagrupa a conta sem disparar. Devolve as faixas gravadas. `novas` com número errado
  # levanta Relacionamentos::PedidoInvalido com o motivo (o controller responde 422).
  def gravar(account, novas)
    faixas = conferidas(novas)
    account.update!(settings: account.settings.to_h.merge(CHAVE => faixas))
    Relacionamentos::Compras::RecalcularJob.perform_later(account.id, nil, false)
    faixas
  end

  def conferidas(novas)
    faixas = PADRAO.keys.index_with { |chave| Integer(novas.to_h[chave].to_s, 10, exception: false) }
    fora = faixas.find { |chave, valor| valor.nil? || !valor.between?(1, MAXIMO[chave]) }
    recusar("#{fora.first} inválido") if fora
    recusar('perdido_dias precisa ser maior que em_risco_dias') unless faixas['perdido_dias'] > faixas['em_risco_dias']
    recusar('campeao_dias precisa ser menor que em_risco_dias') unless faixas['campeao_dias'] < faixas['em_risco_dias']
    faixas
  end

  def recusar(mensagem)
    raise Relacionamentos::PedidoInvalido, mensagem
  end
end

# O cartão fidelidade de uma pessoa, como a ficha lê (#3100, SecaoFidelidade): o cartão da conta, quanto ela tem, o
# que vence logo, os últimos movimentos (com o total, para "Ver tudo") e os cupons que chegaram a ela. Sem cartão na
# conta: nil (a ficha não mostra o bloco).
#
# "Vence logo": as entradas com resto que vencem nos próximos 30 dias, na data da primeira e no mesmo dia dela. O valor
# da compra no histórico só vai para quem vê valor de venda (Crm::ValorDeVenda), como as compras da ficha. O código
# vivo de cada cupom só vai `com_codigos` (quem pode usá-lo ou vê o painel Fidelidade, FidelidadeController).
class Fidelidade::DaPessoa
  NO_HISTORICO = 5
  POR_PAGINA = 20
  JANELA_DO_VENCIMENTO = 30.days

  def initialize(account, contato, com_valores:, com_codigos:, agora: Time.current)
    @account = account
    @contato = contato
    @com_valores = com_valores
    @com_codigos = com_codigos
    @agora = agora
    @programa = Fidelidade::Programa.da_conta(account)
  end

  def call
    return unless @programa

    { programa: @programa.para_a_tela, tem: saldo, vencem: vencem,
      historico: movimentos.limit(NO_HISTORICO).map { |item| item.para_a_tela(com_valores: @com_valores) },
      historico_total: todos.count, cupons: cupons }
  end

  # A página `pagina` (a partir de 1) do histórico inteiro, o mais novo antes.
  def movimentos_da_pagina(pagina)
    return { itens: [], total: 0, pagina: pagina } unless @programa

    itens = movimentos.offset((pagina - 1) * POR_PAGINA).limit(POR_PAGINA)
    { itens: itens.map { |item| item.para_a_tela(com_valores: @com_valores) }, total: todos.count, pagina: pagina }
  end

  private

  def saldo
    Fidelidade::Saldo.find_by(programa_id: @programa.id, contact_id: @contato.id)&.saldo || 0
  end

  def todos = Fidelidade::Movimento.da_pessoa(@programa, @contato.id)

  def movimentos = todos.preload(:user).mais_novos_antes

  def vencem
    proximas = todos.com_resto.where(vence_em: @agora..(@agora + JANELA_DO_VENCIMENTO)).order(:vence_em).to_a
    return if proximas.empty?

    primeira = proximas.first.vence_em
    no_dia = proximas.select { |entrada| entrada.vence_em.to_date == primeira.to_date }
    { quantos: no_dia.sum(&:restante), em: primeira.to_i }
  end

  # Só os que chegaram à pessoa (`enviado_em`): o código sorteado num envio que não saiu não existe para ela, como no
  # Conferir e no "Marcar como usado".
  def cupons
    Fidelidade::CupomCodigo.where(account_id: @account.id, contact_id: @contato.id).where.not(enviado_em: nil).preload(:cupom)
                           .order(created_at: :desc).map { |codigo| codigo.para_a_ficha(@agora, com_codigo: @com_codigos) }
  end
end

# O consumo de cotações do mês, para o cartão de "Ajustar renovações" (E8, #2901, decisão D9): do dia 1º até hoje, no
# fuso da conta. Só contagens, sem teto e sem dinheiro: a Medida de cotações da conta (Autonomia::Insurance::Medida, a
# mesma do Super Admin, que conta toda cotação aberta no portal, da Lia e da renovação) e quantas a renovação pediu
# (`proposta_pedida` da história dos seguros).
class Carteira::Cotacao::Consumo
  def initialize(account)
    @account = account
  end

  def call
    fuso = Autonomia::Insurance::Medida.fuso_de(@account)
    hoje = Time.current.in_time_zone(fuso).to_date
    inicio = hoje.beginning_of_month
    medida = Autonomia::Insurance::Medida.new(conta: @account, inicio: inicio.iso8601, fim: hoje.iso8601).call
    { inicio: inicio.iso8601, fim: hoje.iso8601, cotacoes: medida[:cotacoes], seguradorasAcionadas: medida[:seguradoras_acionadas],
      seguradorasComPreco: medida[:seguradoras_com_preco], daRenovacao: da_renovacao(medida[:inicio]..medida[:fim]) }
  end

  private

  def da_renovacao(periodo)
    Carteira::ApoliceEvento.joins(:apolice).where(carteira_apolices: { account_id: @account.id })
                           .where(tipo: Carteira::Cotacao::Cotar::PEDIDA, quando: periodo).count
  end
end

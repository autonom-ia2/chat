# O crédito do mês da equipe em CRM › Números, visão "Equipe" (#1992, F5 do #1871). A regra é a mesma da visão "Só eu"
# (Crm::Numeros::Credito, Decisão 3): a venda e o caso resolvido contam 100% para quem era o responsável no fechamento;
# venda antiga, sem esse registro, conta pelo responsável atual e marca `estimado`. Aqui a conta é por pessoa, só nos
# funis que quem abre enxerga no painel. Fechamento sem pessoa responsável (robô ou ninguém) fica na chave `nil`.
class Crm::Numeros::CreditoDaEquipe < Crm::Numeros::Credito
  def initialize(account:, range:, pipeline_ids:)
    super(account: account, user: nil, range: range)
    @pipeline_ids = pipeline_ids
  end

  # { responsavel_id (ou nil) => { vendas:, valores: { moeda => cents }, resolvidos: } }, `estimado` e os ids ganhos e resolvidos.
  def perform
    por_pessoa = fechados.group_by { |fechado| responsavel_de(fechado) }.transform_values { |lista| somar(lista) }
    {
      por_pessoa: por_pessoa,
      estimado: fechados.any? { |fechado| fechamentos[fechado[:id]].nil? },
      ganhos: fechados.select { |fechado| fechado[:status] == 'won' }.pluck(:id),
      resolvidos: fechados.select { |fechado| fechado[:status] == 'resolved' }.pluck(:id)
    }
  end

  private

  def somar(lista)
    ganhos = lista.select { |fechado| fechado[:status] == 'won' }
    { vendas: ganhos.size, valores: por_moeda(ganhos), resolvidos: lista.count { |fechado| fechado[:status] == 'resolved' } }
  end

  def fechados
    @fechados ||= linhas(Crm::Relacao.cards_do_funil(@account).where(pipeline_id: @pipeline_ids, closed_at: @range))
  end
end

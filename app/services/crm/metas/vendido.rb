# O que cada pessoa fechou num período (#1991, F4 do #1871), com a mesma regra de crédito do topo de "Só eu"
# (Crm::Numeros::Credito, Decisão 3): 100% de quem era o responsável no fechamento; sem registro do fechamento, o dono
# atual. O funil é o de hoje do card: a venda movida de funil conta no funil onde está.
class Crm::Metas::Vendido < Crm::Numeros::Credito
  def initialize(account:, range:)
    super(account: account, user: nil, range: range)
  end

  # Vendas: { [pipeline_id, user_id, moeda] => centavos }
  def por_pessoa
    ganhos = fechados.select { |fechado| fechado[:status] == 'won' }
    funis = Crm::Relacao.cards_do_funil(@account).where(id: ganhos.pluck(:id)).pluck(:id, :pipeline_id).to_h
    ganhos.each_with_object(Hash.new(0)) do |fechado, soma|
      dono = responsavel_de(fechado)
      soma[[funis[fechado[:id]], dono, fechado[:currency]]] += fechado[:value_cents].to_i if dono
    end
  end

  # Quem fechou o quê: { user_id => ['won', 'resolved'] }, para o papel (Crm::Numeros::Papel).
  def status_por_pessoa
    fechados.each_with_object(Hash.new { |hash, chave| hash[chave] = [] }) do |fechado, quem|
      dono = responsavel_de(fechado)
      quem[dono] |= [fechado[:status]] if dono
    end
  end
end

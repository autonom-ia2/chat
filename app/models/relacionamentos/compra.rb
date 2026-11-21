# O resumo das compras de uma pessoa e o grupo de compra dela (#3097, F1 do épico #3095). A compra é o card ganho num
# funil de Vender. Uma linha por pessoa que já comprou; quem nunca comprou não tem linha. Quem grava é
# Relacionamentos::Compras::Recalcular; o formato que as telas leem sai de `para_a_tela`.
#
# Quem apaga: o banco, em cascata, quando a pessoa sai; a exclusão da conta apaga antes do DELETE da conta
# (Autonomia::ExclusaoDaConta).
class Relacionamentos::Compra < ApplicationRecord
  self.table_name = 'relacionamentos_compras'
  CENTAVOS = 100.0

  belongs_to :account
  belongs_to :contact

  # O intervalo médio entre as compras, em dias: da primeira à última, dividido pelos intervalos. Com 1 compra, nil.
  def intervalo_medio_dias
    return if quantas < 2

    (ultima_em - primeira_em) / 1.day / (quantas - 1)
  end

  # Como a ficha e a lista leem: datas em segundos e valores em reais. `com_valores`: quem não vê valor de venda
  # (Crm::ValorDeVenda) recebe as compras sem os totais.
  def para_a_tela(com_valores:, faixas: nil)
    resumo = { quantas: quantas, ultima_em: ultima_em.to_i, intervalo_medio_dias: intervalo_medio_dias, grupo: grupo,
               por_moeda: (com_valores ? valores : nil) }
    faixas ? resumo.merge(faixas: faixas) : resumo
  end

  private

  def valores
    por_moeda.map { |item| { moeda: item['moeda'], total: item['total_cents'] / CENTAVOS, quantas: item['quantas'] } }
  end
end

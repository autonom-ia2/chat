# A medição de uso da carteira de seguros no Super Admin (E9, #2902): por conta, no mês corrente ou no anterior, só
# contagens (Carteira::Medida). O período vem por link (`?periodo=mes_passado`), sem lista de escolha; o que não for um
# dos dois vira o mês corrente. Ler não é frear: a página não liga, desliga nem limita nada.
class SuperAdmin::CarteiraMedidasController < SuperAdmin::ApplicationController
  def show
    @periodo = Carteira::Medida.periodo(params[:periodo])
    medida = Carteira::Medida.por_conta(@periodo)
    @linhas = medida[:linhas]
    @total = medida[:total]
    @contas = Account.where(id: @linhas.pluck(:conta_id)).index_by(&:id)
  end
end

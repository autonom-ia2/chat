# A frase do topo da Lista nova de Relacionamentos (#2894): quantas pessoas há, quantas já são clientes e quantas sumiram
# há 1 a 3 meses, mais as empresas. Empresa é do Enterprise; sem ele não há nenhuma.
class Relacionamentos::Resumo
  def initialize(account)
    @account = account
  end

  def call
    pessoas = Relacionamentos::ConsultaDePessoas.new(@account, {}).contagens
    { total: pessoas['todos'], clientes: pessoas['clientes'], sumiu_1_a_3_meses: pessoas['sumiu_1_a_3_meses'], empresas: empresas }
  end

  private

  def empresas
    { total: 0, sem_conversa_3_meses: 0 }
  end
end

Relacionamentos::Resumo.prepend_mod_with('Relacionamentos::Resumo')

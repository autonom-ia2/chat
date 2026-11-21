# A frase do topo da Lista nova de Relacionamentos (#2894): quantas pessoas há, quantas já são clientes e quantas sumiram
# há 1 a 3 meses, mais as empresas. Empresa é do Enterprise; sem ele não há nenhuma.
# #3097 — e as compras, para a frase da visão por compra: quantas pessoas passaram da hora de voltar, estão sem comprar
# há algum tempo, são campeãs ou já compraram, e quanto elas já compraram por moeda (só com `com_valores`, para quem vê
# valor de venda).
class Relacionamentos::Resumo
  GRUPOS_DA_FRASE = { passou_da_hora: Relacionamentos::Compras::Grupo::PASSOU_DA_HORA,
                      em_risco: Relacionamentos::Compras::Grupo::EM_RISCO,
                      campeoes: Relacionamentos::Compras::Grupo::CAMPEOES }.freeze

  def initialize(account, com_valores: false)
    @account = account
    @com_valores = com_valores
  end

  def call
    consulta = Relacionamentos::ConsultaDePessoas.new(@account, {})
    pessoas = consulta.contagens
    { total: pessoas['todos'], clientes: pessoas['clientes'], sumiu_1_a_3_meses: pessoas['sumiu_1_a_3_meses'], empresas: empresas,
      compras: compras(consulta, pessoas) }
  end

  private

  def compras(consulta, pessoas)
    valores = @com_valores ? consulta.valores_de_compra : {}
    compraram = pessoas['todos'].to_i - pessoas[Relacionamentos::Compras::Grupo::NUNCA].to_i
    GRUPOS_DA_FRASE.transform_values { |grupo| da_frase(pessoas[grupo], valores[grupo]) }
                   .merge(compraram: da_frase(compraram, valores['todos']))
  end

  def da_frase(quantas, valores)
    { pessoas: quantas.to_i, por_moeda: (valores || [] if @com_valores) }.compact
  end

  def empresas
    { total: 0, sem_conversa_3_meses: 0 }
  end
end

Relacionamentos::Resumo.prepend_mod_with('Relacionamentos::Resumo')

# A frase do topo da aba Seguros (E4, #2897): quantos seguros a conta tem, quantos vencem em até 7 dias, quantos estão
# em renovação e, dos que vencem em até 7 dias, quantos já estão em renovação (E5, #2898). O conector da seguradora
# chega na entrega dele (E7): aqui vem desligado, para a tela não mudar de formato quando chegar.
class Carteira::Resumo
  VENCE_7_EM_RENOVACAO = "#{Carteira::Consulta::EM_RENOVACAO} AND carteira_apolices.fim_vigencia <= :em_7_dias".freeze

  def initialize(account)
    @account = account
  end

  def call
    seguros = Carteira::Consulta.new(@account, {}).contagens
    { total: seguros['todos'], vence7: seguros['vence_7_dias'], vence7EmRenovacao: vence_7_em_renovacao,
      emRenovacao: seguros['em_renovacao'], aggerLigado: false }
  end

  private

  def vence_7_em_renovacao
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id).where(VENCE_7_EM_RENOVACAO, hoje: hoje, em_7_dias: hoje + 7).count
  end
end

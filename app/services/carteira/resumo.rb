# A frase do topo da aba Seguros (E4, #2897): quantos seguros a conta tem e quantos vencem em até 7 dias. Os números de
# renovação e o conector da seguradora chegam nas entregas deles (E5 e E7): aqui vêm zerados, para a tela não mudar de
# formato quando chegarem.
class Carteira::Resumo
  def initialize(account)
    @account = account
  end

  def call
    seguros = Carteira::Consulta.new(@account, {}).contagens
    { total: seguros['todos'], vence7: seguros['vence_7_dias'], vence7EmRenovacao: 0, emRenovacao: 0, aggerLigado: false }
  end
end

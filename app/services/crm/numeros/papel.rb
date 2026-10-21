# O papel de uma pessoa em CRM › Números (#1897, extraído no #1991 para a gaveta de metas usar a mesma régua do "Só
# eu"): vende quem fechou venda no mês ou tem card aberto em funil de Vender; atende quem resolveu caso no mês ou tem
# card aberto em funil de Atender. Sem nada disso, decidem os funis que a pessoa enxerga; sem funil, vende.
module Crm::Numeros::Papel
  module_function

  # O bloco devolve os counts_as_sale dos funis que ela enxerga (só é chamado quando precisa).
  def de(vendeu:, atendeu:)
    proprios = []
    proprios << :venda if vendeu
    proprios << :atende if atendeu
    proprios.presence || pelos_funis(yield)
  end

  def pelos_funis(tipos)
    papeis = []
    papeis << :venda if tipos.include?(true)
    papeis << :atende if tipos.include?(false)
    papeis.presence || [:venda]
  end
end

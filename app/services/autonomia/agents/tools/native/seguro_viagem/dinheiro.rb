# O ÚNICO formatador de reais do Seguro Viagem (#3211): a cotação, o PDF, os detalhes e a proposta passam por aqui.
# Nenhum outro `number_to_currency` nesses arquivos: dois formatadores é o jeito de o mesmo preço sair com dois textos.
module Autonomia::Agents::Tools::Native::SeguroViagem::Dinheiro
  module_function

  # `'1480.25'` -> `'R$ 1.480,25'`; `360` -> `'R$ 360,00'`.
  def brl(valor)
    ActiveSupport::NumberHelper.number_to_currency(BigDecimal(valor.to_s), unit: 'R$ ', separator: ',', delimiter: '.',
                                                                           precision: 2)
  end
end

# O que o cupom dá e até quando vale, escritos para a mensagem do cliente (#3100, passo "Mandar cupom"), no idioma da
# conta: "10% de desconto", "R$ 15 de desconto", "uma lavagem grátis"; "01/12" no fuso da conta. A tela diz igual
# (useTextosDaFidelidade#oferta e #data).
module Fidelidade::TextoDoCupom
  CENTAVOS = 100
  REAL = 'BRL'.freeze

  module_function

  def idioma(conta) = conta.locale.presence || I18n.default_locale

  def oferta(cupom, conta)
    locale = idioma(conta)
    case cupom.oferta_tipo
    when Fidelidade::Cupom::PORCENTAGEM then I18n.t('fidelidade.cupom.oferta.porcentagem', n: cupom.oferta_valor, locale: locale)
    when Fidelidade::Cupom::VALOR then I18n.t('fidelidade.cupom.oferta.valor', valor: dinheiro(cupom.oferta_valor, cupom.moeda), locale: locale)
    else cupom.oferta_texto.to_s
    end
  end

  def data(momento, conta)
    momento.in_time_zone(Autonomia::Automacao::Tempo.fuso(conta)).strftime(I18n.t('fidelidade.cupom.data', locale: idioma(conta)))
  end

  # "R$ 15" ou "R$ 15,50"; outra moeda vai com o código dela na frente ("USD 15.50").
  def dinheiro(centavos, moeda)
    valor = centavos.to_i / CENTAVOS.to_f
    casas = (centavos.to_i % CENTAVOS).zero? ? 0 : 2
    formato = moeda.to_s == REAL ? { unit: 'R$', separator: ',', delimiter: '.' } : { unit: moeda.to_s }
    ActiveSupport::NumberHelper.number_to_currency(valor, format: '%u %n', precision: casas, **formato)
  end
end

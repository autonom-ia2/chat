# O VALOR VIRA FRASE — critério 5.5 (valor com tipo, unidade e moeda exatos).
#
# "Porto Seguro: R$ 2.167,00" não diz se são R$ 2.167 no período inteiro ou por mês, e o cliente lê
# pelo que lhe convém. Errar isso para baixo é o lado que fecha venda e vira reclamação depois.
#
# O significado NÃO é decidido aqui: quem deriva é o adapter, olhando o parcelamento que o portal
# devolveu, e manda em `basis`. Aqui só se traduz o que veio — e quando não veio, não se inventa.
class Autonomia::Insurance::PremiumText
  # Colada no item a que pertence, e curta de propósito: é uma linha secundária debaixo de um
  # preço. Era um parágrafo no fim do bloco, que aparecia mesmo valendo para UMA oferta e ficava
  # maior que os próprios preços.
  SEM_BASE = 'a seguradora não informou se é o total ou uma parcela'.freeze

  def initialize(premium)
    @premium = premium.to_h
  end

  # A PRIMEIRA LINHA DO ITEM: só o valor e o que se sabe dele. O parcelamento e a ressalva descem
  # para a linha de baixo, porque tudo na mesma linha é o que fazia o preço competir com a
  # explicação — e quem lê no celular perde os dois.
  def resumo
    parcelas.present? || @premium['basis'] == 'total' ? "#{valor} no total" : valor
  end

  # -> String ou nil. O que vale para ESTE preço, e não para o bloco: parcelamento quando o portal
  # informou, e a ressalva quando ele mandou o número sem dizer do que se trata. Como parágrafo
  # solto no fim, a ressalva aparecia mesmo quando valia para uma opção só, e ficava maior que os
  # preços.
  def detalhe
    return "ou #{parcelas['count']}x de #{money(parcelas['amount'])}" if parcelas.present?

    SEM_BASE if indefinido?
  end

  # true quando o preço saiu sem unidade — é o que dispara o aviso único no fim do bloco.
  def indefinido?
    @premium['basis'] != 'total' && parcelas.blank?
  end

  # SEPARADOR DE MILHAR. Sem ele o portal virava `R$ 2837,70` na tela do cliente — quatro dígitos
  # colados, que é onde a leitura de preço tropeça. `number_with_delimiter` faz a troca dos dois
  # separadores de uma vez; `tr` sozinho não tem como, porque precisa inserir o ponto antes.
  def self.money(amount)
    inteiro, centavos = format('%.2f', amount.to_f).split('.')
    "R$ #{ActiveSupport::NumberHelper.number_to_delimited(inteiro.to_i, delimiter: '.')},#{centavos}"
  end

  private

  def parcelas
    @premium['installments']
  end

  def valor
    money(@premium['amount'])
  end

  def money(amount)
    self.class.money(amount)
  end
end

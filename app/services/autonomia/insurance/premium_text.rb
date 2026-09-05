# O VALOR VIRA FRASE — critério 5.5 (valor com tipo, unidade e moeda exatos).
#
# "Porto Seguro: R$ 2.167,00" não diz se são R$ 2.167 no período inteiro ou por mês, e o cliente lê
# pelo que lhe convém. Errar isso para baixo é o lado que fecha venda e vira reclamação depois.
#
# O significado NÃO é decidido aqui: quem deriva é o adapter, olhando o parcelamento que o portal
# devolveu, e manda em `basis`. Aqui só se traduz o que veio — e quando não veio, não se inventa.
class Autonomia::Insurance::PremiumText
  # Sai UMA vez por bloco de preços, quando algum veio sem como saber se é total ou parcela.
  # Repetida em cada linha ela vira ruído, e ruído é o que faz o cliente parar de ler o aviso.
  SEM_SIGNIFICADO = 'Sobre os valores: a seguradora informou o preço mas não o formato de ' \
                    'pagamento. O total e as parcelas saem na proposta.'.freeze

  def initialize(premium)
    @premium = premium.to_h
  end

  # -> String. Nunca afirma período que o portal não informou.
  def to_s
    return "#{valor} no total (em até #{parcelas['count']}x de #{money(parcelas['amount'])})" if parcelas.present?
    return "#{valor} no total" if @premium['basis'] == 'total'

    valor
  end

  # true quando o preço saiu sem unidade — é o que dispara o aviso único no fim do bloco.
  def indefinido?
    @premium['basis'] != 'total' && parcelas.blank?
  end

  def self.money(amount)
    "R$ #{format('%.2f', amount.to_f).tr('.', ',')}"
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

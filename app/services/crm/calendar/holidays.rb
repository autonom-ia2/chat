# Feriados nacionais do Brasil (#1195, J3-A13), em tabela de código: sem gem nova e sem serviço externo.
#
# Fixos: as datas das leis federais (Lei 662/1949 e alterações, Lei 6.802/1980 para 12/10 e Lei 14.759/2023 para
# 20/11). Móveis, a partir da Páscoa (algoritmo anônimo gregoriano, de Meeus/Jones/Butcher): Carnaval (segunda e
# terça, 48 e 47 dias antes), Sexta-feira Santa (2 dias antes) e Corpus Christi (60 dias depois). Carnaval e Corpus
# Christi são ponto facultativo no calendário federal, mas quase todo comércio fecha: a página trata os dois como
# feriado, e quem atende nesses dias desliga a opção na página.
#
# Feriados estaduais e municipais ficam de fora de propósito: dependem do endereço de quem atende, que não temos.
class Crm::Calendar::Holidays
  FIXED = {
    [1, 1] => 'new_year',
    [4, 21] => 'tiradentes',
    [5, 1] => 'labour_day',
    [9, 7] => 'independence_day',
    [10, 12] => 'our_lady_aparecida',
    [11, 2] => 'all_souls_day',
    [11, 15] => 'republic_day',
    [11, 20] => 'black_consciousness_day',
    [12, 25] => 'christmas'
  }.freeze

  # Dias a partir do domingo de Páscoa.
  MOVABLE = {
    -48 => 'carnival_monday',
    -47 => 'carnival_tuesday',
    -2 => 'good_friday',
    60 => 'corpus_christi'
  }.freeze

  # Chave do feriado da data, ou nil quando é dia comum.
  def self.name_for(date)
    FIXED[[date.month, date.day]] || MOVABLE[(date - easter(date.year)).to_i]
  end

  def self.holiday?(date)
    name_for(date).present?
  end

  # { Date => chave } dos feriados do ano, em ordem de data.
  def self.for_year(year)
    fixed = FIXED.to_h { |(month, day), name| [Date.new(year, month, day), name] }
    sunday = easter(year)
    movable = MOVABLE.transform_keys { |offset| sunday + offset }
    fixed.merge(movable).sort.to_h
  end

  # Domingo de Páscoa no calendário gregoriano.
  def self.easter(year)
    golden = year % 19
    century, year_of_century = year.divmod(100)
    moon = paschal_moon(golden, century)
    weekday = paschal_weekday(century, year_of_century, moon)
    shift = (golden + (11 * moon) + (22 * weekday)) / 451
    month, day = (moon + weekday - (7 * shift) + 114).divmod(31)
    Date.new(year, month, day + 1)
  end

  # Dias da lua cheia pascal depois de 21/3, com as correções de século do calendário gregoriano.
  def self.paschal_moon(golden, century)
    correction = (century + 8) / 25
    ((19 * golden) + century - (century / 4) - ((century - correction + 1) / 3) + 15) % 30
  end

  # Dias da lua cheia até o domingo seguinte.
  def self.paschal_weekday(century, year_of_century, moon)
    (32 + (2 * (century % 4)) + (2 * (year_of_century / 4)) - moon - (year_of_century % 4)) % 7
  end
  private_class_method :paschal_moon, :paschal_weekday
end

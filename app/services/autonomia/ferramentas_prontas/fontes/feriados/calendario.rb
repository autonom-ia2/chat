# O calendário dos feriados nacionais calculado aqui (última reserva, sem rede): as datas fixas da lei (Lei 662/1949,
# Lei 6.802/1980 e, desde 2024, a Lei 14.759/2023) e as móveis pela Páscoa (algoritmo de Meeus/Jones/Butcher).
class Autonomia::FerramentasProntas::Fontes::Feriados::Calendario < Autonomia::FerramentasProntas::Provedor
  NOME = 'calendario'.freeze
  HOST = nil
  FIXOS = [
    [1, 1, 'Confraternização mundial'], [4, 21, 'Tiradentes'], [5, 1, 'Dia do trabalho'],
    [9, 7, 'Independência do Brasil'], [10, 12, 'Nossa Senhora Aparecida'], [11, 2, 'Finados'],
    [11, 15, 'Proclamação da República'], [12, 25, 'Natal']
  ].freeze
  # Dias contados a partir da Páscoa.
  MOVEIS = [[-48, 'Carnaval'], [-47, 'Carnaval'], [-2, 'Sexta-feira Santa'], [0, 'Páscoa'], [60, 'Corpus Christi']].freeze
  CONSCIENCIA_NEGRA = 2024

  def consultar(consulta, params)
    Autonomia::FerramentasProntas::Fontes::Feriados.responder(consulta, params) { |ano| self.class.do_ano(ano.to_i) }
  end

  def self.do_ano(ano)
    fixos = FIXOS.map { |mes, dia, nome| [Date.new(ano, mes, dia), nome] }
    fixos << [Date.new(ano, 11, 20), 'Dia da consciência negra'] if ano >= CONSCIENCIA_NEGRA
    pascoa = pascoa(ano)
    moveis = MOVEIS.map { |dias, nome| [pascoa + dias, nome] }
    (fixos + moveis).sort_by(&:first).map { |data, nome| { 'data' => data.iso8601, 'nome' => nome } }
  end

  def self.pascoa(ano) # rubocop:disable Metrics/AbcSize
    a = ano % 19
    b, c = ano.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = ((19 * a) + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + (2 * e) + (2 * i) - h - k) % 7
    m = (a + (11 * h) + (22 * l)) / 451
    mes, dia = (h + l - (7 * m) + 114).divmod(31)
    Date.new(ano, mes, dia + 1)
  end
end

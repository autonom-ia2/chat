# FERIADOS E DIAS ÚTEIS (#2858, F1): os feriados nacionais de um ano e a contagem de dias úteis entre duas datas.
#   - principal: BrasilAPI; reserva: Nager.Date (só os de alcance nacional, `global`); última reserva: o calendário
#     calculado aqui (datas fixas da lei e as móveis pela Páscoa), que não depende de rede. As três dão o mesmo
#     conjunto de datas (conferido em 10/11/2026 com 2026).
#   - dia útil: segunda a sexta que não é feriado nacional, contando as duas pontas. Carnaval e Corpus Christi entram
#     como feriado, como na lista da BrasilAPI e no calendário bancário. Feriado estadual e municipal não entra: a
#     resposta diz isso, para o agente não prometer prazo errado.
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real"; Nager.Date é aberta e sem chave. Cache de 30 dias por
# ano (o calendário não muda no ano) e de 1 dia na contagem (a data "de" padrão é hoje).
module Autonomia::FerramentasProntas::Fontes::Feriados
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  ANOS = 2000..2100
  MAX_DIAS = 731
  # Até 160 caracteres (`Resposta::MAX_TEXTO`), senão o fim é cortado.
  REGRA = 'Segunda a sexta, menos feriados nacionais (Carnaval e Corpus Christi inclusos), contando as duas datas. ' \
          'Feriados estaduais e municipais não entram.'.freeze

  module_function

  # "2026-11-30" ou "30/11/2026" -> "2026-11-30"; nil fora do formato ou fora de ANOS.
  def data(valor)
    dia = ler_data(valor.to_s.strip)
    dia.iso8601 if dia && ANOS.cover?(dia.year)
  end

  def ler_data(texto)
    Date.iso8601(texto)
  rescue Date::Error
    begin
      Date.strptime(texto, '%d/%m/%Y')
    rescue Date::Error
      nil
    end
  end

  def hoje
    Time.zone.today.iso8601
  end

  # A contagem, com a lista de feriados de cada ano do período (`por_ano`: ano -> [{ 'data', 'nome' }]).
  def dias_uteis(inicio, fim, por_ano)
    anos = Date.iso8601(inicio).year..Date.iso8601(fim).year
    feriados = anos.flat_map { |ano| por_ano.call(ano) }.select { |item| (inicio..fim).cover?(item['data']) }
    datas = feriados.pluck('data')
    uteis = (Date.iso8601(inicio)..Date.iso8601(fim)).count { |dia| util?(dia) && datas.exclude?(dia.iso8601) }
    { 'de' => inicio, 'ate' => fim, 'dias_uteis' => uteis, 'regra' => REGRA,
      'feriados_no_periodo' => feriados.select { |item| util?(Date.iso8601(item['data'])) } }
  end

  def util?(dia)
    !dia.saturday? && !dia.sunday?
  end

  def responder(consulta, params, &por_ano)
    return dias_uteis(params['de'], params['ate'], por_ano) if consulta.nome == 'dias_uteis'

    { 'ano' => params['ano'], 'feriados' => yield(params['ano']), 'observacao' => 'Só os feriados nacionais.' }
  end

  def periodo_invalido(params)
    de = params['de']
    ate = params['ate']
    'ate' if de.nil? || ate.nil? || ate < de || (Date.iso8601(ate) - Date.iso8601(de)) > MAX_DIAS
  end

  ANO = Parametro.new(nome: 'ano', tipo: 'integer', descricao: 'O ano (ex.: 2026). Sem ano: o ano atual.',
                      padrao: -> { Time.zone.today.year }) { |valor| Parametro.inteiro(valor, ANOS) }
  DE = Parametro.new(nome: 'de', descricao: 'A data inicial, AAAA-MM-DD. Sem data: hoje.', padrao: -> { hoje }) { |valor| data(valor) }
  ATE = Parametro.new(nome: 'ate', descricao: 'A data final, AAAA-MM-DD (até dois anos depois da inicial).') { |valor| data(valor) }

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'feriados', slug: 'pronta_feriados', nome: 'Feriados e dias úteis', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'Os feriados nacionais de um ano e a contagem de dias úteis entre duas datas.',
    consultas: [
      Consulta.new(nome: 'feriados', descricao: 'os feriados nacionais de um ano', opcionais: [ANO],
                   provedores: [BrasilApi, Nager, Calendario], validade: 30.days, prazo_por_fonte: 3, prazo_total: 6),
      Consulta.new(nome: 'dias_uteis', descricao: 'quantos dias úteis entre duas datas; pede ate e aceita de',
                   obrigatorios: [ATE], opcionais: [DE], provedores: [BrasilApi, Nager, Calendario], validade: 1.day,
                   prazo_por_fonte: 3, prazo_total: 6, regra: method(:periodo_invalido))
    ],
    limite_diario: 300,
    termos: 'BrasilAPI (uso de pessoa real, sem robô de varredura) e Nager.Date (aberta, sem chave); o calendário ' \
            'calculado aqui é a última reserva. Cache de 30 dias por ano.'
  )
end

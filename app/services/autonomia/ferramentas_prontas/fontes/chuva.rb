# QUANTO CHOVEU (#2858, F4): os milímetros de chuva de um dia, ou de um período curto, numa cidade ou localização.
#   - fonte: o arquivo histórico do Open-Meteo (`archive-api`), a soma diária de precipitação (`precipitation_sum`), no
#     fuso do próprio ponto (`timezone=auto`: o dia do Acre e do Amazonas não é o de Brasília);
#   - é ESTIMATIVA de modelo (reanálise ERA5 e afins, grade de ~10 km), não a medição de um pluviômetro: a resposta diz
#     isso, e o dia de hoje ainda não fechou;
#   - a cidade vira a coordenada da sede do município (`compras_governo/municipios.rb`); a coordenada que o cliente
#     mandou vai arredondada a 2 casas (~1 km: a grade da fonte é maior que isso);
#   - período de até MAX_DIAS dias (acima de 14 dias o Open-Meteo cobra mais de uma chamada), de 1940 até hoje.
# Fonte única, sem reserva (o INMET só entrega os dados das estações com token). Termos: o plano gratuito do Open-Meteo é
# SÓ para uso não comercial (menos de 10.000 chamadas por dia, 5.000 por hora e 600 por minuto); o uso comercial pede
# plano pago, com chave, em `customer-api.open-meteo.com`. Licença dos dados: CC BY 4.0, com atribuição. Cache de 6 horas.
module Autonomia::FerramentasProntas::Fontes::Chuva
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  CASAS = 2
  MAX_DIAS = 14
  INICIO = Date.new(1940, 1, 1)
  ATRIBUICAO = 'Dados do tempo por Open-Meteo.com (CC BY 4.0)'.freeze
  ESTIMATIVA = 'Estimativa de modelo para a região (grade de ~10 km), não a medição de um pluviômetro.'.freeze
  HOJE_ABERTO = 'O dia de hoje ainda não acabou: o valor dele é parcial.'.freeze

  module_function

  def coordenada(valor, limite)
    numero = valor.is_a?(Numeric) ? valor.to_f : Float(valor.to_s.strip, exception: false)
    numero.round(CASAS) if numero&.finite? && numero.abs <= limite
  end

  def data(valor)
    dia = Autonomia::FerramentasProntas::Fontes::Feriados.ler_data(valor.to_s.strip)
    dia.iso8601 if dia && dia >= INICIO
  end

  # [latitude, longitude, rótulo]: a coordenada informada ou a sede do município. nil quando não dá.
  def ponto(params)
    return [params['latitude'], params['longitude'], 'a localização informada'] if params['latitude'] && params['longitude']

    municipio = params['cidade'] && params['uf'] && Municipios.buscar(params['uf'], params['cidade'])
    [municipio.latitude, municipio.longitude, municipio.rotulo] if municipio
  end

  # O lugar e o período (até hoje, no máximo MAX_DIAS dias). -> o nome do parâmetro que não serve, ou nil.
  def regra(params)
    return lugar_que_falta(params) if ponto(params).nil?

    de = Date.iso8601(params['de'])
    ate = Date.iso8601(params['ate'] || params['de'])
    return 'de' if de > Time.zone.today

    'ate' if ate < de || ate > Time.zone.today || (ate - de) >= MAX_DIAS
  end

  def lugar_que_falta(params)
    return 'longitude' if params['latitude']
    return 'latitude' if params['longitude']

    params['cidade'] && params['uf'].nil? ? 'uf' : 'cidade'
  end

  # Os dias da fonte -> o total e cada dia. Dia sem valor (a fonte ainda não tem) fica sem número, fora do total.
  def resposta(rotulo, dias, valores)
    lista = dias.zip(valores).map { |dia, mm| { 'data' => dia, 'mm' => mm.is_a?(Numeric) ? mm.to_f.round(1) : nil } }
    medidos = lista.filter_map { |item| item['mm'] }
    return if medidos.empty?

    observacao = [ESTIMATIVA, (HOJE_ABERTO if dias.include?(Time.zone.today.iso8601))].compact.join(' ')
    { 'local' => rotulo, 'de' => dias.first, 'ate' => dias.last, 'total_mm' => medidos.sum.round(1), 'dias' => lista,
      'observacao' => observacao, 'fonte_dos_dados' => ATRIBUICAO }
  end

  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade (com uf). Sem cidade: latitude e longitude.') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado da cidade.', opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase))
  LATITUDE = Parametro.new(nome: 'latitude', tipo: 'number', descricao: 'A latitude da localização que o cliente mandou.') do |valor|
    coordenada(valor, 90)
  end
  LONGITUDE = Parametro.new(nome: 'longitude', tipo: 'number', descricao: 'A longitude da localização que o cliente mandou.') do |valor|
    coordenada(valor, 180)
  end
  DE = Parametro.new(nome: 'de', descricao: 'O dia, AAAA-MM-DD (ou o primeiro dia do período). Sem data: ontem.',
                     padrao: -> { Time.zone.yesterday.iso8601 }) { |valor| data(valor) }
  ATE = Parametro.new(nome: 'ate', descricao: "O último dia do período, AAAA-MM-DD (até #{MAX_DIAS} dias). Sem data: só o dia de.") do |valor|
    data(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'chuva', slug: 'pronta_chuva', nome: 'Quanto choveu', flag: FLAG,
    descricao: 'Quantos milímetros choveu num dia, ou em poucos dias, numa cidade ou localização (estimativa da região).',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'chuva', descricao: 'os milímetros de chuva de um dia ou período', opcionais: [CIDADE, UF, LATITUDE, LONGITUDE, DE, ATE],
        provedores: [OpenMeteo], validade: 6.hours, prazo_por_fonte: 3, prazo_total: 4, regra: method(:regra)
      )
    ],
    limite_diario: 500,
    termos: 'Open-Meteo, plano gratuito só para uso não comercial (10.000 por dia, 5.000 por hora, 600 por minuto); uso ' \
            'comercial pede plano pago. Dados CC BY 4.0, com atribuição. Sem reserva. Cache de 6 horas.'
  )
end

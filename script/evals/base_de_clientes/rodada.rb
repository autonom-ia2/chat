# Uma rodada da bateria (#1246): cada caso é lido REPETICOES vezes com o Jev nas duas leituras do
# motor — 'classica' (conta sem a flag customer_base, igual ao main) e 'nova' (conta com a flag).
# MOTORES=nova roda só a nova.
class BaseDeClientesEval::Rodada
  CONJUNTOS = {
    'principal' => -> { [BaseDeClientesEval::Casos::Simples, BaseDeClientesEval::Casos::DiaADia, BaseDeClientesEval::Casos::Armadilhas] },
    'controle' => -> { [BaseDeClientesEval::Casos::Controle] }
  }.freeze

  LEITURAS = {
    'classica' => CampaignImports::ContactReading::CLASSIC,
    'nova' => CampaignImports::ContactReading::CUSTOMER_BASE
  }.freeze

  def initialize
    @repeticoes = ENV.fetch('REPETICOES', '1').to_i.clamp(1, 10)
    @filtro = lista('CASOS', '')
    @saida = Pathname.new(ENV['SAIDA'].presence || Rails.root.join('tmp/evals/base_de_clientes', Time.current.strftime('%Y%m%d-%H%M%S')).to_s)
    @cliente = BaseDeClientesEval::ClienteMedido.new(teto: ENV.fetch('TETO_USD', '2').to_f, api_key: ENV.fetch('TYPESAFE_API_KEY'))
    @motores = lista('MOTORES', LEITURAS.keys.join(',')) & LEITURAS.keys
    @resolvedores = LEITURAS.transform_values { |leitura| resolvedor(leitura) }
    @resultados = []
  end

  def executar
    FileUtils.mkdir_p(@saida.join('planilhas'))
    casos.each { |caso| @resultados.concat(rodar_caso(caso)) }
    gravar
  rescue BaseDeClientesEval::TetoAtingido => e
    puts "PAROU NO TETO: #{e.message}"
    gravar
  end

  private

  def lista(variavel, padrao)
    ENV.fetch(variavel, padrao).split(',').map(&:strip).reject(&:empty?)
  end

  def resolvedor(leitura)
    BaseDeClientesEval::ResolvedorMedido.new(TypesafeAi::AudienceSchemaResolver.new(client: @cliente, share_hint: leitura.customer_base?))
  end

  def gravar
    BaseDeClientesEval::Relatorio.new(@resultados, gasto: @cliente.gasto, chamadas: @cliente.chamadas, tokens: @cliente.tokens)
                                 .gravar(@saida)
    puts "Relatório: #{@saida.join('RELATORIO.md')}"
  end

  def casos
    conjunto = ENV.fetch('CONJUNTO', 'principal')
    modulos = CONJUNTOS.fetch(conjunto) { -> { CONJUNTOS.values.flat_map(&:call) } }.call
    todos = modulos.flat_map(&:casos)
    @filtro.empty? ? todos : todos.select { |caso| @filtro.include?(caso.id) }
  end

  def rodar_caso(caso)
    bytes = BaseDeClientesEval::Arquivo.bytes(caso)
    File.binwrite(@saida.join('planilhas', BaseDeClientesEval::Arquivo.nome(caso)), bytes)
    resultados = @motores.flat_map do |motor|
      Array.new(@repeticoes) { |indice| leitura_com_jev(caso, bytes, motor, indice + 1) }
    end
    puts linha_console(caso, resultados)
    resultados
  end

  def leitura_com_jev(caso, bytes, motor, repeticao)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    leitura = ler(caso, bytes, motor)
    rodada = { motor: motor, leitura: LEITURAS.fetch(motor), repeticao: repeticao, jev_bruto: @resolvedores.fetch(motor).ultima,
               segundos: Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio }
    BaseDeClientesEval::Avaliacao.new(caso, leitura, rodada).resultado
  end

  def ler(caso, bytes, motor)
    parsed = CampaignImports::Parser.new(StringIO.new(bytes), filename: BaseDeClientesEval::Arquivo.nome(caso)).perform
    CampaignImports::SpreadsheetReader.new(parsed, ai_resolver: @resolvedores.fetch(motor), jev_enabled: true,
                                                   reading: LEITURAS.fetch(motor)).perform
  rescue CampaignImports::SpreadsheetReader::Error, ArgumentError => e
    e
  end

  def linha_console(caso, resultados)
    veredictos = resultados.group_by { |resultado| resultado[:motor] }.map do |motor, lista|
      "#{motor}: #{lista.pluck(:veredicto).tally.map { |nome, total| "#{nome}×#{total}" }.join(' ')}"
    end.join(' | ')
    format('%<id>-4s %<titulo>-55s %<veredictos>s  gasto US$ %<gasto>.4f',
           id: caso.id, titulo: caso.titulo[0, 55], veredictos: veredictos, gasto: @cliente.gasto)
  end
end

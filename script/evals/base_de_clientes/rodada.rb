# Uma rodada da bateria (#1246): para cada caso, uma leitura sem o Jev (só os apelidos de
# cabeçalho, para comparar) e REPETICOES leituras com o Jev.
class BaseDeClientesEval::Rodada
  CONJUNTOS = {
    'principal' => -> { [BaseDeClientesEval::Casos::Simples, BaseDeClientesEval::Casos::DiaADia, BaseDeClientesEval::Casos::Armadilhas] },
    'controle' => -> { [BaseDeClientesEval::Casos::Controle] }
  }.freeze

  def initialize
    @repeticoes = ENV.fetch('REPETICOES', '1').to_i.clamp(1, 10)
    @filtro = ENV['CASOS'].to_s.split(',').map(&:strip).reject(&:empty?)
    @saida = Pathname.new(ENV['SAIDA'].presence || Rails.root.join('tmp/evals/base_de_clientes', Time.current.strftime('%Y%m%d-%H%M%S')).to_s)
    @cliente = BaseDeClientesEval::ClienteMedido.new(teto: ENV.fetch('TETO_USD', '2').to_f, api_key: ENV.fetch('TYPESAFE_API_KEY'))
    @resolvedor = BaseDeClientesEval::ResolvedorMedido.new(TypesafeAi::AudienceSchemaResolver.new(client: @cliente))
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
    sem_jev = BaseDeClientesEval::Avaliacao.new(caso, ler(caso, bytes, jev: false), { motor: 'sem_jev', repeticao: 0 }).resultado
    com_jev = Array.new(@repeticoes) { |indice| leitura_com_jev(caso, bytes, indice + 1) }
    puts linha_console(caso, com_jev)
    [sem_jev, *com_jev]
  end

  def leitura_com_jev(caso, bytes, repeticao)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    leitura = ler(caso, bytes, jev: true)
    rodada = { motor: 'jev', repeticao: repeticao, jev_bruto: @resolvedor.ultima,
               segundos: Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio }
    BaseDeClientesEval::Avaliacao.new(caso, leitura, rodada).resultado
  end

  def ler(caso, bytes, jev:)
    parsed = CampaignImports::Parser.new(StringIO.new(bytes), filename: BaseDeClientesEval::Arquivo.nome(caso)).perform
    CampaignImports::SpreadsheetReader.new(parsed, ai_resolver: @resolvedor, jev_enabled: jev).perform
  rescue CampaignImports::SpreadsheetReader::Error, ArgumentError => e
    e
  end

  def linha_console(caso, resultados)
    veredictos = resultados.pluck(:veredicto).tally.map { |nome, total| "#{nome}×#{total}" }.join(' ')
    format('%<id>-4s %<titulo>-55s %<veredictos>s  gasto US$ %<gasto>.4f',
           id: caso.id, titulo: caso.titulo[0, 55], veredictos: veredictos, gasto: @cliente.gasto)
  end
end

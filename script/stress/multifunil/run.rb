# Teste de estresse do coração do multifunil (#1140), com IA DE VERDADE (custo real). Nunca roda no CI.
#
# O que faz: para cada conversa sintética de fixtures/conversas.json, monta uma conta nova espelhando a estrutura das
# contas piloto (fixtures/estrutura.json), cria as mensagens do cliente e deixa o sistema decidir: a IA de assunto
# (Crm::Subjects: Jev + revisão pelo modelo maior) e a IA de movimentação (Crm::Ai::Evaluator). Depois confere o
# resultado contra o esperado, escrito antes de rodar. Grava tmp/stress/fase-<FASE>/resultado.json.
#
# Travas: só roda com STRESS_MULTIFUNIL=1, fora de produção, no banco chatwoot_stress e com o adaptador :test do
# ActiveJob (RAILS_ENV=test). Para antes de passar do teto de custo da fase (STRESS_TETO_USD) ou do teto total
# (STRESS_TETO_TOTAL_USD, padrão 2,90), somando o custo que o próprio sistema grava (Crm::AiUsageEvent).
#
# Como rodar: script/stress/multifunil/rodar_no_m2.sh (carrega as chaves sem imprimir e chama este arquivo).
abort('[stress] defina STRESS_MULTIFUNIL=1 (teste com IA paga, nunca no CI)') unless ENV['STRESS_MULTIFUNIL'] == '1'
abort('[stress] proibido em produção') if Rails.env.production? || ENV['CI'].present?
abort('[stress] o banco precisa ser chatwoot_stress') unless ActiveRecord::Base.connection.current_database == 'chatwoot_stress'
abort('[stress] precisa do adaptador :test do ActiveJob') unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)

module Stress; end
%w[relogio bomba mundo espiao retrato conversa conferencia].each { |arquivo| require_relative "lib/#{arquivo}" }
Stress::Espiao.instalar

class Stress::Execucao
  PASTA = File.expand_path(__dir__)
  TETO_TOTAL_PADRAO = 2.90

  def initialize
    @fase = ENV.fetch('STRESS_FASE', 'A')
    @teto_fase = Float(ENV.fetch('STRESS_TETO_USD'))
    @teto_total = Float(ENV.fetch('STRESS_TETO_TOTAL_USD', TETO_TOTAL_PADRAO.to_s))
    @so = ENV['STRESS_SO'].to_s.split(',').map(&:strip).compact_blank
    @segredos = carregar_segredos
    @estrutura = JSON.parse(File.read(File.join(PASTA, 'fixtures/estrutura.json')))
    @conversas = JSON.parse(File.read(File.join(PASTA, 'fixtures/conversas.json')))['conversas']
    @saida = Rails.root.join("tmp/stress/fase-#{@fase}")
  end

  def rodar
    configurar_instalacao
    FileUtils.mkdir_p(@saida)
    @gasto_inicial = gasto_total
    relogio = Stress::Relogio.new(Time.zone.parse('2026-10-19 09:00:00'))
    resultados = []
    selecionadas.each do |dados|
      break if sem_orcamento?(dados, resultados)

      resultados << rodar_uma(dados, relogio)
      gravar(resultados)
    end
    relogio.soltar
    gravar(resultados)
    puts resumo(resultados)
  end

  private

  # Rodada por rodada (todas as conversas da 1ª, depois da 2ª): se o orçamento acabar, as rodadas completas valem.
  # A mesma conversa em várias rodadas mede a variação da IA (o mesmo texto pode ter decisões diferentes).
  def selecionadas
    base = @so.empty? ? @conversas : @conversas.select { |c| @so.include?(c['id']) }
    (1..Integer(ENV.fetch('STRESS_RODADAS', '1'))).flat_map { |rodada| base.map { |c| c.merge('rodada' => rodada) } }
  end

  def rodar_uma(dados, relogio)
    medida = { antes: gasto_total, comeco: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    bomba = Stress::Bomba.new(relogio: relogio, segredos: @segredos.values)
    resultado = Stress::Conversa.new(dados: dados, modelo: modelo(dados['modelo']), relogio: relogio, bomba: bomba).rodar
    checagens = Stress::Conferencia.new(esperado: dados['esperado'], resultado: resultado, erros: bomba.erros).conferir
    linha(dados, resultado.merge(checagens: checagens, descartados: bomba.descartados), medida)
  rescue StandardError => e
    identificacao(dados).merge(passou: false, erro_do_harness: "#{e.class}: #{limpo(e.message)}",
                               custo_usd: (gasto_total - medida[:antes]).round(6))
  end

  def identificacao(dados)
    { id: dados['id'], rodada: dados['rodada'], cenario: dados['cenario'], variacao: dados['variacao'], motivo: dados['motivo'] }
  end

  # O modelo de conta com os funis e os campos por extenso (estrutura.json guarda cada funil uma vez só).
  def modelo(chave)
    base = @estrutura.fetch('modelos').fetch(chave)
    base.merge('funis' => base['funis'].map { |funil| @estrutura.fetch('funis').fetch(funil) },
               'atributos' => @estrutura['atributos'])
  end

  def linha(dados, resultado, medida)
    custo = gasto_total - medida[:antes]
    segundos = Process.clock_gettime(Process::CLOCK_MONOTONIC) - medida[:comeco]
    passou = resultado[:checagens].all? { |c| c[:ok] }
    puts "[stress] #{dados['id']}#r#{dados['rodada']} #{passou ? 'PASSOU' : 'FALHOU'} custo=US$#{custo.round(4)} #{segundos.round}s"
    identificacao(dados).merge(passou: passou, custo_usd: custo.round(6), segundos_reais: segundos.round(1))
                        .merge(resultado.slice(:checagens, :turnos, :final, :descartados))
  end

  # Para ANTES de passar do teto: a próxima conversa é estimada pela mais cara até aqui (no mínimo US$ 0,05).
  def sem_orcamento?(dados, resultados)
    estimativa = [resultados.map { |r| r[:custo_usd].to_f }.max.to_f, 0.05].max
    gasto_fase = gasto_total - @gasto_inicial
    return false if gasto_fase + estimativa <= @teto_fase && gasto_total + estimativa <= @teto_total

    puts "[stress] parando antes de #{dados['id']}: fase US$#{gasto_fase.round(4)}, total US$#{gasto_total.round(4)}"
    true
  end

  def gasto_total
    Crm::AiUsageEvent.sum(:cost_estimate).to_f
  end

  def gravar(resultados)
    File.write(@saida.join('resultado.json'),
               JSON.pretty_generate(fase: @fase, gerado_em: Time.now.utc.iso8601, gasto_fase_usd: (gasto_total - @gasto_inicial).round(6),
                                    gasto_total_usd: gasto_total.round(6), conversas: resultados))
  end

  def resumo(resultados)
    passaram = resultados.count { |r| r[:passou] }
    "[stress] fase #{@fase}: #{passaram}/#{resultados.size} passaram; gasto da fase US$#{(gasto_total - @gasto_inicial).round(4)}"
  end

  # As chaves vêm de um arquivo (KEY=VALOR) que o rodar_no_m2.sh grava com permissão 600 e apaga ao sair. Nunca são
  # impressas: nem aqui, nem nos erros (Bomba#limpo, #limpo).
  def carregar_segredos
    pares = File.readlines(ENV.fetch('STRESS_SEGREDOS_ARQUIVO'), chomp: true).filter_map { |linha| par_de(linha) }
    segredos = pares.to_h.slice('OPENAI_API_KEY', 'TYPESAFE_API_KEY')
    abort('[stress] faltam OPENAI_API_KEY ou TYPESAFE_API_KEY no arquivo de segredos') unless segredos.size == 2 && segredos.values.all?(&:present?)

    segredos
  end

  # "export CHAVE=valor" ou CHAVE="valor" -> [CHAVE, valor]; comentário e linha vazia -> nil.
  def par_de(linha)
    texto = linha.strip.delete_prefix('export ').strip
    return if texto.empty? || texto.start_with?('#') || texto.exclude?('=')

    chave, valor = texto.split('=', 2)
    [chave.strip, valor.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")]
  end

  def configurar_instalacao
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: @segredos['OPENAI_API_KEY'], locked: false)
    InstallationConfig.find_or_initialize_by(name: 'TYPESAFE_JEV_ENABLED').update!(value: 'true', locked: false)
    credencial = AiProviderCredential.find_or_initialize_by(provider: 'typesafe')
    credencial.update!(api_key: @segredos['TYPESAFE_API_KEY'])
  end

  def limpo(texto)
    @segredos.values.reduce(texto.to_s.first(300)) { |acc, segredo| acc.gsub(segredo, '<REDACTED>') }
  end
end

Stress::Execucao.new.rodar

# #1430 (desenho D): a consulta HTTP em segundo plano, nos specs.
#
# A flag `agente_ferramenta_em_segundo_plano` ainda não está no config/features.yml (a Orquestração põe o bit), então
# o spec liga a flag por stub de `feature_enabled?`, só para ela. A espera do turno é dublada pelos dois relógios da
# `ConsultaNoTurno`: `pausar` (o que acontece entre duas leituras) e `agora` (o relógio monotônico).
module ConsultaNoTurnoHelper
  FLAG_DA_CONSULTA = 'agente_ferramenta_em_segundo_plano'.freeze

  # Liga pela leitura de verdade (`feature_enabled?`); o `ligada?` só pula a checagem de que o bit existe no yml.
  def ligar_consulta_em_segundo_plano
    allow_any_instance_of(Account).to receive(:feature_enabled?).and_wrap_original do |original, flag, *resto| # rubocop:disable RSpec/AnyInstance
      flag.to_s == FLAG_DA_CONSULTA || original.call(flag, *resto)
    end
    allow(Autonomia::Agents::Tools::ConsultaNoTurno).to receive(:ligada?) { |conta| conta.feature_enabled?(FLAG_DA_CONSULTA) }
  end

  # O relógio do turno anda `passo` segundos a cada pausa; `durante_a_pausa` roda dentro dela (o job "chegando").
  def relogio_do_turno(passo: 0.25, &durante_a_pausa)
    tempo = [0.0]
    consulta = Autonomia::Agents::Tools::ConsultaNoTurno
    allow(consulta).to receive(:agora) { tempo.first }
    allow(consulta).to receive(:pausar) do |segundos|
      durante_a_pausa&.call
      tempo[0] += [segundos, passo].max
    end
    tempo
  end

  # Roda os HttpAssincronaJob enfileirados até agora. -> quantos rodaram.
  def rodar_consultas
    fila = ActiveJob::Base.queue_adapter.enqueued_jobs
    jobs = fila.select { |job| job[:job] == Autonomia::Agents::Tools::HttpAssincronaJob }
    fila.reject! { |job| jobs.any? { |rodando| rodando.equal?(job) } }
    jobs.each { |job| Autonomia::Agents::Tools::HttpAssincronaJob.new.perform(*job[:args]) }
    jobs.size
  end

  # O sistema de fora responde `corpo` (2xx), guardando as chaves que recebeu. `antes` roda dentro da chamada.
  def sistema_responde(corpo, chaves: [], antes: nil)
    allow(SafeFetch).to receive(:fetch) do |_url, **opcoes, &bloco|
      chaves << opcoes[:headers]['Idempotency-Key']
      antes&.call
      arquivo = Tempfile.new('resposta')
      arquivo.write(corpo)
      arquivo.rewind
      bloco.call(SafeFetch::Result.new(tempfile: arquivo, filename: 'r.json', content_type: 'application/json'))
    end
    chaves
  end
end

RSpec.configure do |config|
  config.include ConsultaNoTurnoHelper
end

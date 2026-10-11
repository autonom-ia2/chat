# O que a rodada do cron de avisos já sabe da WAHA (#1270). Uma rodada (`NoticeDispatchJob#perform`) cria um e o passa
# a cada `Notices::Sender`; com ele, o `Notices::WahaChat` deixa de consultar a WAHA, e o aviso volta para a fila,
# quando:
#
# - o servidor falhou (timeout, sem conexão, 5xx): o servidor WAHA é um só (`Waha::Config.api_url`), então a WAHA
#   inteira fica fora até o fim da rodada;
# - a caixa respondeu fora do formato: só essa caixa fica fora na rodada;
# - as consultas da rodada já somaram LOOKUP_BUDGET segundos: uma WAHA lenta não segura o cron.
#
# Vive só na memória da rodada: a rodada seguinte tenta de novo.
class Crm::BookingV2::Notices::WahaOutage
  LOOKUP_BUDGET = 20

  # clock: segundos de um relógio que só anda para a frente (trocável no teste).
  def initialize(budget: LOOKUP_BUDGET, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @budget = budget
    @clock = clock
    @inbox_ids = Set.new
    @server_down = false
    @spent = 0.0
  end

  def down?(inbox)
    @server_down || @spent >= @budget || @inbox_ids.include?(inbox.id)
  end

  def inbox_down!(inbox)
    @inbox_ids << inbox.id
  end

  def server_down!
    @server_down = true
  end

  # Roda a consulta e soma o tempo dela ao gasto da rodada, também quando ela falha.
  def timed
    started = @clock.call
    yield
  ensure
    @spent += @clock.call - started
  end
end

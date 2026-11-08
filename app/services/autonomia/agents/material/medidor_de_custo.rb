# #1426 (tema 4b) — o custo REAL de uma rodada do autoteste, com teto. Toda chamada de IA grava o consumo
# (Crm::Ai::UsageRecorder) e avisa pelo evento `crm.ai_usage`, com o custo estimado pela tabela de preços. O medidor
# ouve esse evento enquanto a rodada roda, só na thread dela (o aviso é síncrono, na thread de quem chamou a IA), e soma.
# Cada medição tem o próprio ouvinte, preso à thread que a abriu: duas rodadas ao mesmo tempo (duas threads do Sidekiq)
# não somam o custo uma da outra.
#
# Antes de cada chamada, `cabe?(tipo)` compara o gasto até aqui mais a estimativa da próxima (o maior custo já visto
# daquele tipo, ou a estimativa inicial) com o teto: se passar, a rodada PARA ANTES. Modelo sem preço na tabela custa 0
# no evento; aí vale a estimativa do tipo, nunca zero.
class Autonomia::Agents::Material::MedidorDeCusto
  TETO_USD = 2.0
  # Estimativas iniciais, por chamada, com folga (medido no eval do #1426: ver docs/audit).
  ESTIMATIVA_INICIAL = { perguntas: 0.15, resposta: 0.10, juiz: 0.03 }.freeze

  attr_reader :gasto

  def initialize(teto: TETO_USD)
    @teto = teto
    @gasto = 0.0
    @maior = ESTIMATIVA_INICIAL.dup
  end

  # Mede o bloco como uma chamada do `tipo`. Devolve o que o bloco devolver.
  def medir(tipo, &)
    custo = 0.0
    dono = Thread.current
    ouvinte = lambda do |*args|
      payload = args.last
      custo += payload[:cost].to_f if Thread.current.equal?(dono) && payload.is_a?(Hash)
    end
    ActiveSupport::Notifications.subscribed(ouvinte, Crm::Ai::UsageRecorder::EVENT_NAME, &)
  ensure
    somar_ao_gasto(tipo, custo)
  end

  def cabe?(tipo)
    (@gasto + @maior.fetch(tipo)).round(6) <= @teto
  end

  private

  def somar_ao_gasto(tipo, custo)
    real = custo.positive? ? custo : ESTIMATIVA_INICIAL.fetch(tipo)
    @gasto += real
    @maior[tipo] = [@maior.fetch(tipo), real].max
  end
end

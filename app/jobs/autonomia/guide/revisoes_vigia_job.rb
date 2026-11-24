# A cada 5 minutos, retoma a revisão de conversas do Guia (#3158, B8b) que ficou sem batimento: o processo morreu no
# meio de um lote (deploy, falta de memória). O lote seguinte começa na conversa seguinte à última lida.
class Autonomia::Guide::RevisoesVigiaJob < ApplicationJob
  queue_as :scheduled_jobs

  SEM_BATIMENTO = 3.minutes

  def perform
    ::Autonomia::Guide::Revisao.andando
                               .where('batimento_em IS NULL OR batimento_em < ?', SEM_BATIMENTO.ago)
                               .find_each { |revisao| ::Autonomia::Guide::RevisaoJob.perform_later(revisao.id) }
  end
end

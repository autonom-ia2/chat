# #1428 (tema 6, parte 3, entrega B) — roda as perguntas de prova do último ajuste, fora do turno do Construtor: o cartão
# do resultado sai na hora e a prova chega segundos depois. Sem nova tentativa: a prova que falha vira "indisponível"
# (ProvaDoAjuste), e o ajuste que mudou no meio tempo descarta o resultado. Um erro que não é da IA sobe para o rastreio
# uma vez só: a prova não é repetida (gastaria de novo e chegaria depois que a tela desistiu).
class Autonomia::Agents::ProvaDoAjusteJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(thread_id, versao_id)
    thread = Autonomia::Agents::BuildThread.find_by(id: thread_id)
    return if thread.blank? || !Autonomia::Agents::Fase2.ligada?(thread.account)

    Autonomia::Agents::ProvaDoAjuste.new(thread, versao_id).rodar!
  end
end

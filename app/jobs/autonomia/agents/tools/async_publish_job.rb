# Segunda tentativa de PUBLICAR uma entrega assíncrona que chegou enquanto a entrega humanizada
# do turno ainda estava em curso (#313).
#
# Existe para que só haja UM produtor de mensagem por vez naquela conversa: a cadeia de chunks
# do `Operate::ChunkedDeliveryJob` pode postar até 5 mensagens ao longo de 90 segundos, e uma
# cotação entrando no meio dela sai fora de ordem ("encontrei 3 opções" antes de "deixa eu
# consultar") e ainda embaralha a janela de mídia do turno seguinte.
#
# O adiamento é curto e LIMITADO: passado o teto, publica assim mesmo. Fora de ordem é ruim;
# nunca entregar é pior.
class Autonomia::Agents::Tools::AsyncPublishJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

  def perform(run_id, text, deferrals = 0)
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank?

    publisher = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run)
    result = deferrals.to_i >= AsyncConfig::MAX_PUBLISH_DEFERRALS ? publisher.publish!(text) : publisher.publish(text)
    return unless result.deferred?

    self.class.set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
        .perform_later(run_id, text, deferrals.to_i + 1)
  end
end

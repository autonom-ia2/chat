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
#
# DOIS TETOS (rodada 2 da fatia 1 do PDF rápido, 13/09/2026): a cadeia do turno deixa de ser esperada em
# `MAX_PUBLISH_DEFERRALS`, e a entrega de que um texto encadeado depende (`Tools::EntregaEncadeada`), em
# `MAX_DEPENDENCY_DEFERRALS`. Quem chega aqui adiado pelo varredor já começa com a cadeia no teto.
class Autonomia::Agents::Tools::AsyncPublishJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

  # `entrega` é o texto, o arquivo já gravado (`ArquivoGravado`) ou o texto encadeado, na forma
  # serializada que o publicador devolveu em `adiada`. Um job enfileirado antes da rodada 2 pode trazer a
  # entrega de arquivo com a URL; o publicador ainda a reconhece, baixa e grava.
  def perform(run_id, entrega, deferrals = 0)
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank?

    adiamentos = deferrals.to_i
    result = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(
      entrega, wait_for_chain: adiamentos < AsyncConfig::MAX_PUBLISH_DEFERRALS,
               wait_for_dependency: adiamentos < AsyncConfig::MAX_DEPENDENCY_DEFERRALS
    )
    return unless result.deferred?

    self.class.set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
        .perform_later(run_id, result.adiada || entrega, adiamentos + 1)
  end
end

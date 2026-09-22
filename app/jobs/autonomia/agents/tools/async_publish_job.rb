# Segunda tentativa de PUBLICAR uma entrega assíncrona que chegou enquanto a entrega humanizada
# do turno ainda estava em curso (#313).
#
# Existe para que só haja UM produtor de mensagem por vez naquela conversa: a cadeia de chunks
# do `Operate::ChunkedDeliveryJob` pode postar até 5 mensagens ao longo de 90 segundos, e um
# arquivo entrando no meio dela sai fora de ordem e ainda embaralha a janela de mídia do turno seguinte.
#
# O adiamento é curto e LIMITADO: passado o teto (`MAX_PUBLISH_DEFERRALS`, ~3 a 4 min de relógio com a espera do
# poller do Sidekiq), publica assim mesmo. Fora de ordem é ruim; nunca entregar é pior. Quem chega aqui adiado
# pelo varredor já começa no teto.
#
# SÓ ARQUIVO (PR C): o texto encadeado da versão anterior (o fecho que esperava o PDF) e o texto solto que um job
# enfileirado antes do deploy ainda carregue são descartados pelo publicador, registrados. Quem fala depois do
# arquivo é a Lia, no turno do evento (`Tools::Evento`).
class Autonomia::Agents::Tools::AsyncPublishJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

  # `entrega` é o arquivo já gravado (`ArquivoGravado`), na forma serializada que o publicador devolveu em
  # `adiada`. Um job enfileirado antes da rodada 2 pode trazer a entrega de arquivo com a URL; o publicador ainda
  # a reconhece, baixa e grava.
  def perform(run_id, entrega, deferrals = 0)
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank?

    adiamentos = deferrals.to_i
    result = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(
      entrega, wait_for_chain: adiamentos < AsyncConfig::MAX_PUBLISH_DEFERRALS
    )
    return unless result.deferred?

    self.class.set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
        .perform_later(run_id, result.adiada || entrega, adiamentos + 1)
  end
end

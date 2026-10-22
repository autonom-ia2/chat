# Excluir de vez um funil arquivado que ainda tem cards (#2096). Mover ou apagar cada card leva tempo demais para a
# requisição; o controller confere tudo antes e põe aqui.
#
# O serviço confere de novo sob a trava do funil (Crm::Pipelines::Excluidor). Quando algo barra (funil restaurado,
# destino arquivado, reunião que o calendário não cancela, card que o destino recusa), nada é apagado e o desfecho fica
# na Auditoria da conta (Crm::ExclusaoDefinitiva::FALHOU, motivo em código e só ids), além do log. Dois cliques geram
# dois jobs: o segundo espera a trava do primeiro, encontra o funil já apagado e sai sem registrar nada.
class Crm::Pipelines::ExcluirDeVezJob < ApplicationJob
  queue_as :low

  def perform(pipeline_id, actor_id, modo, target_stage_id = nil)
    pipeline = Crm::Pipeline.find_by(id: pipeline_id)
    return if pipeline.blank?

    @pipeline = pipeline
    @actor = User.find_by(id: actor_id)
    excluir(modo, target_stage_id)
  end

  private

  def excluir(modo, target_stage_id)
    target_stage = Crm::Pipelines::Excluidor.etapa_de_destino(@pipeline, target_stage_id) if modo == Crm::Pipelines::Excluidor::MOVER
    return falhou('target_unavailable', target_stage_id: target_stage_id) if modo == Crm::Pipelines::Excluidor::MOVER && target_stage.blank?

    Crm::Pipelines::Excluidor.new(pipeline: @pipeline, actor: @actor, modo: modo, target_stage: target_stage).perform
  rescue Crm::ExclusaoDefinitiva::Mudou => e
    falhou(e.motivo, canceled_meeting_ids: e.canceladas.presence) unless e.motivo == 'already_deleted'
  rescue Crm::Cards::Excluidor::ReuniaoNaoCancelada => e
    falhou('meeting_cancel_failed', meeting_id: e.meeting_id, canceled_meeting_ids: e.canceladas.presence)
  rescue ActiveRecord::RecordInvalid => e
    # Um card que o destino não aceita (ex.: dono que saiu da conta) desfaz a transação inteira. Tentar de novo dá o mesmo
    # erro: registra quem barrou, sem dado do card, e para.
    falhou('card_rejected', record_type: e.record.class.name, record_id: e.record.id, fields: e.record.errors.attribute_names.map(&:to_s))
  end

  def falhou(motivo, **extras)
    Rails.logger.error("[crm][excluir_de_vez] pipeline=#{@pipeline.id} motivo=#{motivo} #{extras.compact.to_json}; nada foi apagado")
    Crm::ExclusaoDefinitiva.falhou!(account: @pipeline.account, user: @actor, alvo: 'funil', motivo: motivo,
                                    pipeline_id: @pipeline.id, **extras)
  end
end

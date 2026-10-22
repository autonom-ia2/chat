# Excluir de vez um funil arquivado que ainda tem cards (#2096). Mover ou apagar cada card leva tempo demais para a
# requisição; o controller confere tudo antes e põe aqui.
# Confere de novo na hora de rodar: o funil pode ter sido restaurado ou o destino arquivado enquanto esperava. Nesses
# casos, e quando o calendário não deixa cancelar uma reunião, nada é apagado e fica o registro no log (só ids).
class Crm::Pipelines::ExcluirDeVezJob < ApplicationJob
  queue_as :low

  def perform(pipeline_id, actor_id, modo, target_stage_id = nil)
    pipeline = Crm::Pipeline.find_by(id: pipeline_id)
    return if pipeline.blank? || !pipeline.archived?

    target_stage = Crm::Pipelines::Excluidor.etapa_de_destino(pipeline, target_stage_id) if modo == Crm::Pipelines::Excluidor::MOVER
    return destino_indisponivel(pipeline_id, target_stage_id) if modo == Crm::Pipelines::Excluidor::MOVER && target_stage.blank?

    Crm::Pipelines::Excluidor.new(pipeline: pipeline, actor: User.find_by(id: actor_id), modo: modo, target_stage: target_stage).perform
  rescue Crm::Cards::Excluidor::ReuniaoNaoCancelada => e
    Rails.logger.error("[crm][excluir_de_vez] pipeline=#{pipeline_id} meeting=#{e.meeting_id} reunião não cancelada; nada foi apagado")
  rescue ActiveRecord::RecordInvalid => e
    # Um card que o destino não aceita (ex.: dono que saiu da conta) desfaz a transação inteira. Tentar de novo dá o mesmo
    # erro: registra quem barrou, sem dado do card, e para.
    Rails.logger.error("[crm][excluir_de_vez] pipeline=#{pipeline_id} #{e.record.class.name}=#{e.record.id} inválido " \
                       "(#{e.record.errors.attribute_names.join(',')}); nada foi apagado")
  end

  private

  def destino_indisponivel(pipeline_id, target_stage_id)
    Rails.logger.error("[crm][excluir_de_vez] pipeline=#{pipeline_id} destino=#{target_stage_id} indisponível; nada foi apagado")
  end
end

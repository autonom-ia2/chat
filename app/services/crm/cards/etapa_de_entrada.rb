# #2501: o pedido da API que manda o card para um funil sem uma etapa desse funil não vira erro. O card entra na etapa de
# entrada do funil, a primeira pela posição (o mesmo critério do Crm::BookingV2::Booker.pipeline_target), e o motivo vai
# para o histórico. Vale para a criação e para o upsert por external_id. Só o funil sem etapa nenhuma não tem resolução.
class Crm::Cards::EtapaDeEntrada
  class FunilSemEtapa < StandardError
    CODE = 'crm.upsert_stage_of_pipeline_required'.freeze
  end

  # O motivo que o histórico mostra (`motivo` na atividade): a etapa não veio no pedido, ou a que veio não é desse funil.
  SEM_ETAPA = 'etapa_nao_veio'.freeze
  ETAPA_DE_OUTRO_FUNIL = 'etapa_de_outro_funil'.freeze

  Resultado = Struct.new(:stage, :motivo)

  # nil quando o pedido não traz funil ou traz uma etapa dele; senão, a etapa de entrada do funil e o motivo.
  def self.para(account:, pipeline_id:, stage_id:)
    return if pipeline_id.blank?

    stage = account.crm_pipeline_stages.find_by(id: stage_id) if stage_id.present?
    return if stage && stage.pipeline_id.to_s == pipeline_id.to_s

    entrada = account.crm_pipelines.find(pipeline_id).stages.order(:position, :id).first
    raise FunilSemEtapa, FunilSemEtapa::CODE if entrada.nil?

    Resultado.new(entrada, stage_id.present? ? ETAPA_DE_OUTRO_FUNIL : SEM_ETAPA)
  end
end

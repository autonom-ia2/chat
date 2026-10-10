# Depois da reunião da página de agendamento nova (#1193, J4-A7): quando o agente marca "Aconteceu", o card pode ir
# para a etapa que o admin escolheu. `ask` mostra a pergunta ("Mover" / "Agora não"); `auto` move sozinho. Sem etapa,
# nada é oferecido. A etapa tem de ser de um funil ativo desta conta.
module Crm::BookingPostMeetingSettings
  extend ActiveSupport::Concern

  POST_MEETING_MODES = %w[ask auto].freeze

  included do
    belongs_to :post_meeting_stage, class_name: 'Crm::PipelineStage', optional: true

    validates :post_meeting_mode, inclusion: { in: POST_MEETING_MODES }
    validate :post_meeting_stage_must_belong_to_account
  end

  # `pipeline_id`: o funil da etapa, para a tela abrir a escolha no funil certo.
  def post_meeting_settings
    { mode: post_meeting_mode, stage_id: post_meeting_stage_id, pipeline_id: post_meeting_stage&.pipeline_id }
  end

  # A etapa configurada, se ainda serve (funil ativo desta conta). Funil arquivado depois de salvar: nada a oferecer.
  def post_meeting_target
    stage = post_meeting_stage
    stage if stage.present? && stage.account_id == account_id && stage.pipeline&.active?
  end

  private

  def post_meeting_stage_must_belong_to_account
    return if post_meeting_stage_id.blank? || !will_save_change_to_post_meeting_stage_id?
    return if usable_post_meeting_stage?(Crm::PipelineStage.find_by(id: post_meeting_stage_id))

    errors.add(:post_meeting_stage_id, 'must be a stage of an active pipeline in this account')
  end

  def usable_post_meeting_stage?(stage)
    pipeline = stage&.pipeline
    pipeline.present? && stage.account_id == account_id && pipeline.account_id == account_id && pipeline.active?
  end
end

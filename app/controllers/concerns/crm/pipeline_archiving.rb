# Arquivar, restaurar e a prévia do arquivamento do funil (#2095), no Api::V1::Accounts::Crm::PipelinesController. A
# regra do último funil ativo e do único principal (Parte A) vale no DELETE como no PATCH: o Crm::Pipelines::Archiver a
# confere sob a mesma trava da conta, e a recusa sai pela mesma resposta (render_archive_blocked).
module Crm::PipelineArchiving
  extend ActiveSupport::Concern

  RESTORE_NOT_ARCHIVED = 'crm.pipeline_restore_not_archived'.freeze

  # Nome próprio: um segundo before_action :fetch_pipeline com outro `only` substituiria o do controller (show, update).
  included do
    before_action :fetch_pipeline_to_archive, only: [:destroy, :restore, :archive_preview]
  end

  # Arquivar: com `move_to_stage_id` (etapa de outro funil ativo que a pessoa vê), os cards abertos vão para lá antes,
  # na mesma transação. Sem ele, ficam no funil e voltam quando ele for restaurado; os retornos marcados deles param.
  def destroy
    result = ::Crm::Pipelines::Archiver.new(pipeline: @pipeline, actor: Current.user, target_stage: archive_target_stage).perform
    @moved_cards_count = result.moved.size
    @stopped_follow_ups_count = result.stopped_follow_ups
    @open_cards_count = @pipeline.cards.open.count
    render :show
  rescue ::Crm::Pipelines::Archiver::InvalidTarget
    render_unprocessable(::Crm::Pipelines::Archiver::INVALID_TARGET)
  rescue ::Crm::Pipelines::Archiver::Blocked => e
    @archive_blocked = e.motivo
    render_archive_blocked
  end

  # Restaurar o funil arquivado: ele volta ao seletor do Kanban com os cards abertos que ficaram nele.
  def restore
    return render_unprocessable(RESTORE_NOT_ARCHIVED) unless @pipeline.archived?

    @pipeline.active!
    @open_cards_count = @pipeline.cards.open.count
    render :show
  end

  # O que a tela mostra antes de arquivar: quantos cards abertos ficam, quais caixas criam card neste funil e, se os
  # cards ficarem no funil, quantos retornos param e quantas reuniões continuam marcadas.
  def archive_preview
    render json: {
      payload: { open_cards_count: @pipeline.cards.open.count, inboxes: linked_inboxes }
        .merge(::Crm::Pipelines::RetornosDosGuardados.new(@pipeline).contagem)
    }
  end

  private

  def fetch_pipeline_to_archive
    fetch_pipeline
  end

  # A etapa para onde vão os cards abertos ao arquivar: de outro funil ativo que a pessoa enxerga. Id que não serve é
  # recusado, nunca ignorado: arquivar sem mover não pode acontecer por engano.
  def archive_target_stage
    stage_id = params[:move_to_stage_id].presence
    return if stage_id.nil?

    visible_active = policy_scope(::Crm::Pipeline).active.where.not(id: @pipeline.id).select(:id)
    stage = Current.account.crm_pipeline_stages.where(pipeline_id: visible_active).find_by(id: stage_id)
    raise ::Crm::Pipelines::Archiver::InvalidTarget, ::Crm::Pipelines::Archiver::INVALID_TARGET if stage.nil?

    stage
  end

  # Funis arquivados (index com `status=archived`): quantos cards abertos voltam ao quadro com cada um.
  def open_cards_counts(pipelines)
    Current.account.crm_cards.open.where(pipeline_id: pipelines.select(:id)).group(:pipeline_id).count
  end

  # As caixas ligadas ao funil; `auto_create_card` diz se a caixa cria card nele sozinha.
  def linked_inboxes
    @pipeline.pipeline_inboxes.includes(:inbox).where.not(inbox_id: nil).order(:id).map do |link|
      { id: link.inbox_id, name: link.inbox&.name, auto_create_card: link.auto_create_card }
    end
  end
end

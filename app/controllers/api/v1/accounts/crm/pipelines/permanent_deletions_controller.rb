# Excluir de vez um funil arquivado (#2096, Parte C). Só administrador, só funil arquivado e com o nome do funil digitado.
# Funil com cards exige a escolha explícita em `cards`: 'move' (com `target_stage_id`, etapa de outro funil ativo) ou
# 'delete' (apaga os cards de vez junto). Sem cards, apaga na hora (200); com cards, vai para um job (202).
class Api::V1::Accounts::Crm::Pipelines::PermanentDeletionsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_pipeline
  before_action :ensure_deletable!

  def create
    cards_count = @pipeline.cards.count
    return excluir_agora if cards_count.zero?
    return render_error('crm.permanent_delete.pipeline_has_cards', cards_count: cards_count) if modo.blank?
    return render_error('crm.permanent_delete.invalid_cards_mode') if ::Crm::Pipelines::Excluidor::MODOS.exclude?(modo)
    return render_error('crm.permanent_delete.invalid_target_stage') if mover? && etapa_de_destino.blank?

    ::Crm::Pipelines::ExcluirDeVezJob.perform_later(@pipeline.id, Current.user.id, modo, etapa_de_destino&.id)
    render json: { payload: { status: 'queued', cards_count: cards_count } }, status: :accepted
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:id])
  end

  def ensure_deletable!
    return render_error('crm.permanent_delete.admin_only', status: :forbidden) unless policy(@pipeline).permanent_delete?
    return render_error('crm.permanent_delete.not_archived') unless @pipeline.archived?

    render_error('crm.permanent_delete.confirmation_mismatch') unless params[:confirmation].to_s.strip == @pipeline.name.strip
  end

  def excluir_agora
    ::Crm::Pipelines::Excluidor.new(pipeline: @pipeline, actor: Current.user).perform
    render json: { payload: { status: 'deleted', cards_count: 0 } }
  end

  def modo
    params[:cards].to_s.presence
  end

  def mover?
    modo == ::Crm::Pipelines::Excluidor::MOVER
  end

  def etapa_de_destino
    return unless mover?

    @etapa_de_destino ||= ::Crm::Pipelines::Excluidor.etapa_de_destino(@pipeline, params[:target_stage_id])
  end

  def render_error(code, status: :unprocessable_entity, **details)
    render json: { error: code }.merge(details), status: status
  end
end

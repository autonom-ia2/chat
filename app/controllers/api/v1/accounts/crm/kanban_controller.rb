class Api::V1::Accounts::Crm::KanbanController < Api::V1::Accounts::Crm::BaseController
  include Crm::FilterParameters

  before_action :validate_crm_filter_parameters, only: :index

  def index
    authorize ::Crm::Card
    pipeline = selected_pipeline
    return render json: { payload: { pipeline: nil, stages: [] } } if pipeline.blank?

    render json: { payload: board_payload(pipeline) }
  end

  private

  def selected_pipeline
    return @selected_pipeline if defined?(@selected_pipeline)

    pipelines = policy_scope(::Crm::Pipeline).active
    return @selected_pipeline = pipelines.find_by(id: params[:pipeline_id]) if params[:pipeline_id].present?

    @selected_pipeline = pipelines.order(:position, :id).first
  end

  def board_payload(pipeline)
    Crm::Kanban::BoardPayloadBuilder.new(
      pipeline: pipeline,
      cards_scope: policy_scope(::Crm::Card),
      context: board_context
    ).perform
  end

  def board_context
    Crm::Kanban::BoardContext.new(
      params: params,
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    )
  end
end

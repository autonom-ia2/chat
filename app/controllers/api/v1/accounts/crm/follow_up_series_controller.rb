# #1460 — a "visão de recorrência": ver a série (regra, próximas datas, o que já foi feito), mudar "esta e as
# próximas", pausar, retomar e encerrar. "Só a próxima" é o PATCH da vez em FollowUpsController.
class Api::V1::Accounts::Crm::FollowUpSeriesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_series

  rescue_from ActiveRecord::RecordInvalid do |exception|
    log_handled_error(exception)
    render json: Crm::FollowUps::RecordInvalidResponse.render(exception), status: :unprocessable_entity
  end
  rescue_from Crm::FollowUps::RecipientParams::Invalid do |exception|
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def show; end

  def update
    @series = Crm::FollowUps::SeriesUpdater.new(series: @series, user: Current.user, attributes: series_params).perform
    render :show
  end

  def pause
    @series = status_service.pause
    render :show
  end

  def resume
    @series = status_service.resume
    render :show
  end

  def finish
    @series = status_service.finish
    render :show
  end

  private

  def fetch_series
    @series = policy_scope(::Crm::FollowUpSeries).includes(:card, :contact, :recipient_team, :created_by).find(params[:id])
    authorize @series, "#{action_name}?".to_sym
  end

  def status_service
    Crm::FollowUps::SeriesStatus.new(series: @series, user: Current.user)
  end

  def series_params
    parameter_set(:follow_up_series).permit(
      :title, :description, :due_at, :timezone, :recipient_mode, :recipient_team_id,
      recipient_user_ids: [], recurrence: Api::V1::Accounts::Crm::FollowUpsController::RECURRENCE_PARAMS
    ).to_h.with_indifferent_access
  end
end

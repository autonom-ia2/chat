class Api::V1::Accounts::Crm::InboxSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_inbox, only: [:update]

  def index
    authorize ::Crm::InboxSetting
    @inbox_settings = policy_scope(::Crm::InboxSetting).includes(:inbox, :default_pipeline, :default_stage).order(:inbox_id)
    @inbox_settings_count = @inbox_settings.count
  end

  def update
    @inbox_setting = Current.account.crm_inbox_settings.find_or_initialize_by(inbox: @inbox)
    authorize @inbox_setting
    pipeline_anterior = @inbox_setting.default_pipeline_id

    ActiveRecord::Base.transaction do
      @inbox_setting.update!(inbox_setting_params)
      sincronizar_vinculo_do_funil(pipeline_anterior)
    end

    render :show
  end

  private

  # O vínculo funil↔caixa sai junto do salvamento: sem isto o CRM fica
  # configurado na caixa e nenhum card nasce (issue #499).
  def sincronizar_vinculo_do_funil(pipeline_anterior)
    ::Crm::InboxSettings::PipelineLinkSyncer.new(
      inbox_setting: @inbox_setting,
      user: Current.user,
      pipeline_trocado: pipeline_anterior.present? && pipeline_anterior != @inbox_setting.default_pipeline_id
    ).perform
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def inbox_setting_params
    parameter_set(:inbox_setting).permit(
      :crm_enabled, :default_pipeline_id, :default_stage_id, :visibility_mode,
      :auto_create_card
    )
  end
end

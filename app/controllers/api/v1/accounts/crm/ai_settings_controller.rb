class Api::V1::Accounts::Crm::AiSettingsController < Api::V1::Accounts::Crm::BaseController
  include DeferInteractiveAi

  before_action :ensure_crm_ai_enabled
  before_action :fetch_pipeline

  def show
    authorize @pipeline, :manage_ai?
    @ai_settings = Crm::Ai::SettingsPresenter.new(pipeline: @pipeline, quem_recebe: params[:quem_recebe].present?).perform
  end

  def update
    authorize @pipeline, :manage_ai?
    @pipeline = Crm::Ai::SettingsUpdater.new(
      pipeline: @pipeline,
      params: ai_settings_params,
      stage_criteria: stage_criteria_params,
      stage_handoff: stage_handoff_params
    ).perform
    @ai_settings = Crm::Ai::SettingsPresenter.new(pipeline: @pipeline.reload).perform
    render :show
  end

  def improve_criteria
    authorize @pipeline, :manage_ai?
    input = params.permit(:stage_index, stages: [:id, :name, :description]).to_h
    raw_input = params.slice(:stages, :stage_index).to_unsafe_h
    return render_unprocessable('invalid_stage_criteria') unless Crm::Ai::StageCriteriaImprover.valid_input?(raw_input)
    return render_unprocessable('invalid_funil') if funil_do_formulario.nil?

    defer_interactive_ai('stage_criteria', {
                           pipeline_id: @pipeline.id, stages: input.fetch('stages'), stage_index: input.fetch('stage_index'),
                           language: I18n.locale.to_s, funil: funil_do_formulario
                         })
  end

  # #1920: raio-x das frases da tela antes de salvar (Crm::Ai::RaioXDasFrases). Mesma validação das etapas do improve.
  def criteria_xray
    authorize @pipeline, :manage_ai?
    raw_input = { 'stages' => params.to_unsafe_h['stages'], 'stage_index' => 0 }
    return render_unprocessable('invalid_stage_criteria') unless Crm::Ai::StageCriteriaImprover.valid_input?(raw_input)

    return render json: { error: 'xray_busy' }, status: :too_many_requests unless Crm::Ai::RaioXDasFrases.vaga?(@pipeline)

    stages = params.permit(stages: [:id, :name, :description]).to_h.fetch('stages')
    defer_interactive_ai('stage_criteria_xray', { pipeline_id: @pipeline.id, stages: stages })
  end

  # #1920: "Melhorar com IA" do "quando usar" do funil (Crm::Ai::WhenToUseImprover).
  def improve_when_to_use
    authorize @pipeline, :manage_ai?
    return render_unprocessable('invalid_funil') if funil_do_formulario.nil?

    defer_interactive_ai('pipeline_when_to_use', {
                           pipeline_id: @pipeline.id, language: I18n.locale.to_s,
                           funil: funil_do_formulario
                         })
  end

  private

  # #1920: o tipo e o "quando usar" que estão no formulário, para a IA que escreve a frase. nil quando o formato é inválido.
  def funil_do_formulario
    return @funil_do_formulario if defined?(@funil_do_formulario)

    @funil_do_formulario = Crm::Ai::ContextoDoFunil.do_formulario(params.permit(funil: %i[counts_as_sale when_to_use])[:funil])
  end

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:pipeline_id])
  end

  def ai_settings_params
    parameter_set(:ai_settings).permit(
      :enabled, :auto_move_enabled, :attribute_extraction_enabled, :score_enabled, :callback_enabled, :callback_mode,
      :stale_hours,
      auto_followup: [
        :enabled, :mode, :max_touches, :tone_instructions,
        { intervals_hours: [], allowed_days: [], quiet_hours: [:start, :end, :tz] }
      ],
      service_reminders: [:progress, :resolved_check, :payment, :progress_after_hours, :resolved_check_after_hours],
      handoff: [
        :enabled, :mode, :selector_mode, :handoff_mode, :trigger, :prefer_online, :pickup_threshold_seconds,
        :escalation_user_id, :pool_type, :pool_id, :renotify_after_seconds, :escalation_action
      ]
    )
  end

  def stage_criteria_params
    parameter_set(:stage_criteria).permit!.to_h
  end

  def stage_handoff_params
    params.fetch(:stage_handoff, {}).permit!.to_h
  end
end

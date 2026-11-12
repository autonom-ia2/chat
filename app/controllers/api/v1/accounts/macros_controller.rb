class Api::V1::Accounts::MacrosController < Api::V1::Accounts::BaseController
  include AttachmentConcern
  include Api::V1::Accounts::Concerns::AutomationExternalActionGuard

  # #2451: a macro com webhook manda a conversa para fora, como a regra automática (#2448).
  WEBHOOK_ACTIONS = %w[send_webhook_event].freeze

  before_action :fetch_macro, only: [:show, :update, :destroy, :execute]
  before_action :check_authorization, only: [:show, :update, :destroy, :execute]
  before_action :check_webhook_action, only: [:create, :update]

  def index
    @macros = Macro.with_visibility(current_user, params)
  end

  def show
    head :not_found if @macro.nil?
  end

  def create
    blobs, actions, error = validate_and_prepare_attachments(params[:actions])
    return render_could_not_create_error(error) if error

    @macro = Current.account.macros.new(macros_with_user.merge(created_by_id: current_user.id))
    @macro.set_visibility(current_user, permitted_params)
    @macro.actions = actions

    return render_could_not_create_error(@macro.errors.messages) unless @macro.valid?

    @macro.save!
    blobs.each { |blob| @macro.files.attach(blob) }
  end

  def update
    blobs, actions, error = validate_and_prepare_attachments(params[:actions], @macro)
    return render_could_not_create_error(error) if error

    ActiveRecord::Base.transaction do
      @macro.assign_attributes(macros_with_user)
      @macro.set_visibility(current_user, permitted_params)
      @macro.actions = actions if params[:actions]
      @macro.save!
      blobs.each { |blob| @macro.files.attach(blob) }
    rescue StandardError => e
      Rails.logger.error e
      render_could_not_create_error(@macro.errors.messages)
    end
  end

  def destroy
    @macro.destroy!
    head :ok
  end

  def execute
    ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)

    head :ok
  end

  private

  def permitted_params
    params.permit(
      :name, :visibility,
      actions: [:action_name, { action_params: [] }]
    )
  end

  def macros_with_user
    permitted_params.merge(updated_by_id: current_user.id)
  end

  def fetch_macro
    @macro = Current.account.macros.find_by(id: params[:id])
  end

  def check_authorization
    authorize(@macro) if @macro.present?
  end

  # Criar ou mudar uma macro que tem ou vai ter webhook pede integration_manage, no critério das regras: as ações de
  # hoje e as do pedido (tirar o webhook também é mexer). Sem ações no pedido, o update mantém as de hoje. O
  # administrador sempre pode; apagar e executar seguem como estão.
  def check_webhook_action
    check_integration_for(Array(@macro&.actions) + action_list(params[:actions]), WEBHOOK_ACTIONS)
  end
end

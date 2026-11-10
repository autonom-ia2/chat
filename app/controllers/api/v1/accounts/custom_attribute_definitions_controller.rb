class Api::V1::Accounts::CustomAttributeDefinitionsController < Api::V1::Accounts::BaseController
  before_action :fetch_custom_attributes_definitions, except: [:create]
  before_action :fetch_custom_attribute_definition, only: [:show, :update, :destroy]
  before_action :check_authorization
  DEFAULT_ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def index; end

  def show; end

  def create
    @custom_attribute_definition = Current.account.custom_attribute_definitions.create!(
      permitted_payload
    )
  end

  def update
    @custom_attribute_definition.update!(permitted_payload)
  end

  # O campo do tipo contato que uma automação ligada lê não é apagado (CampoContatoEmUso): volta o motivo.
  def destroy
    return head :no_content if @custom_attribute_definition.destroy

    render json: { message: @custom_attribute_definition.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def fetch_custom_attributes_definitions
    @custom_attribute_definitions = Current.account.custom_attribute_definitions.with_attribute_model(permitted_params[:attribute_model])
  end

  def fetch_custom_attribute_definition
    @custom_attribute_definition = Current.account.custom_attribute_definitions.find(permitted_params[:id])
  end

  def permitted_payload
    params.require(:custom_attribute_definition).permit(
      :attribute_display_name,
      :attribute_description,
      :attribute_display_type,
      :attribute_key,
      :attribute_model,
      :regex_pattern,
      :regex_cue,
      attribute_values: []
    )
  end

  def permitted_params
    params.permit(:id, :filter_type, :attribute_model)
  end
end

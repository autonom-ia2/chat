# Jogadas salvas da conta (#732; MODO-25, MODO-26, FILTRO-27, PLAT-17). Salvar, editar e excluir exigem
# prospecting_manage (BaseController, pelo verbo); a lista vai para quem vê a prospecção no payload das configurações.
# O modo fica o da hora de salvar: a jogada aparece só na grade desse modo.
class Api::V1::Accounts::Autonomia::Prospecting::SavedPresetsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :fetch_saved_preset, only: [:update, :destroy]

  def create
    preset = ::Autonomia::Prospecting::SavedPreset.create_in_account(
      Current.account, create_params.merge(user: Current.user)
    )
    return render_preset_errors(preset) unless preset.persisted?

    render json: { payload: preset.as_payload }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render_name_taken
  end

  def update
    return render_preset_errors(@saved_preset) unless @saved_preset.update(update_params)

    render json: { payload: @saved_preset.as_payload }
  rescue ActiveRecord::RecordNotUnique
    render_name_taken
  end

  def destroy
    @saved_preset.destroy!
    head :no_content
  end

  private

  def fetch_saved_preset
    @saved_preset = ::Autonomia::Prospecting::SavedPreset.where(account: Current.account).find(params[:id])
  end

  def create_params
    params.require(:saved_preset).permit(:name, :score_mode, filters: {}).to_h.symbolize_keys
  end

  def update_params
    params.require(:saved_preset).permit(:name, filters: {}).to_h.symbolize_keys
  end

  def render_preset_errors(preset)
    render json: { error: preset.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # Duas pessoas salvando o mesmo nome ao mesmo tempo: a validação passa nas duas e o índice segura a segunda.
  def render_name_taken
    render json: { error: I18n.t('autonomia.prospecting.saved_presets.errors.name_taken') }, status: :unprocessable_entity
  end
end

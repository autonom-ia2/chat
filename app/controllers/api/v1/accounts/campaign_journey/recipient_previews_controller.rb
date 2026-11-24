# "Vão receber" of a journey campaign before it exists (#993, PRD §6.4, B8): the exact number of
# people the send reaches and why the others do not, counted once (CampaignJourney::RecipientPreview).
# POST because the variable bindings travel as JSON; nothing is written.
# #3099: with `duas_versoes: { divisao }` (and `grupo_de_controle_pct`, the control group of #3098), the payload also
# has the plan of the test counted here (`duas_versoes`: modo, teste, versao1, versao2, resto, pequeno, minimo), on the
# "Vão receber" without the control group — the same count the send uses (CampaignJourney::DuasVersoes.plano).
# #3101: `melhor_horario: { conhecidos }` — quantos de quem recebe já têm o melhor horário aprendido.
# CAMPAIGN_JOURNEY_ENABLED off → 404; campaign_manage required (CampaignPolicy#create?), otherwise 401.
class Api::V1::Accounts::CampaignJourney::RecipientPreviewsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    # Contact imports (#1006) are never audiences: campaign_flows keeps them out.
    campaign_import = Current.account.campaign_imports.campaign_flows.find(params.require(:campaign_import_id))
    contagem = ::CampaignJourney::RecipientPreview.new(
      campaign_import, channel: params[:channel], variable_bindings: hash_param(:variable_bindings),
                       variable_defaults: hash_param(:variable_defaults), message_body: params[:message_body]
    )
    preview = contagem.perform
    render json: { payload: com_plano(preview).merge('melhor_horario' => melhor_horario(contagem, preview)) }
  rescue ArgumentError => e
    render json: { error: e.message, code: e.message }, status: :unprocessable_entity
  end

  private

  def com_plano(preview)
    return preview if params[:duas_versoes].blank?

    divisao = params.dig(:duas_versoes, :divisao).presence&.to_i || 50
    raise ArgumentError, 'invalid_divisao' unless ::CampaignJourney::DuasVersoes::DIVISOES.include?(divisao)

    preview.merge('duas_versoes' => ::CampaignJourney::DuasVersoes.plano(publico_do_teste(preview['receive']), divisao))
  end

  def melhor_horario(contagem, preview)
    { 'conhecidos' => [::Autonomia::MelhorHorario.conhecidos(Current.account, contagem.alcancaveis), preview['receive']].min }
  end

  # O "Vão receber" sem o grupo de controle (o mesmo arredondamento do sorteio, CampaignJourney::GrupoDeControle).
  def publico_do_teste(recebem)
    pct = params[:grupo_de_controle_pct].to_i
    raise ArgumentError, 'invalid_grupo_de_controle' unless CampaignAudienceLink::GRUPOS_DE_CONTROLE.include?(pct)

    recebem - (recebem * pct / 100)
  end

  def check_authorization
    authorize(Campaign, :create?)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end

  def hash_param(key)
    value = params[key]
    value.respond_to?(:permit!) ? value.permit!.to_h : {}
  end
end

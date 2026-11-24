# #3099: a pessoa escolhe a versão que vai para o resto do público de uma campanha com duas versões.
#
#   POST …/campaign_journey/results/:channel/:id/vencedora  { versao: 1 | 2 }
#
# Vale durante o teste (antecipa a escolha) e depois dele, no "eu escolho". É disparo: precisa de campaign_send
# (CampaignPolicy#send_campaign?, #1898), como criar a campanha. Idempotente: escolher de novo a mesma versão responde
# 200 sem mandar nada; outra versão depois de escolhida, ou campanha cujo público inteiro já recebeu (público pequeno),
# responde 422. Responde o bloco das duas versões do resultado. CAMPAIGN_JOURNEY_ENABLED off → 404.
class Api::V1::Accounts::CampaignJourney::VencedorasController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled

  def create
    authorize(Campaign, :send_campaign?)
    link = CampaignAudienceLink.for_campaign(campaign)
    versoes = ::CampaignJourney::DuasVersoes.new(link)
    raise ActiveRecord::RecordNotFound unless versoes.ativo?
    return render_erro('campaign_journey.invalid_versao') unless versao

    escolheu = versoes.mandar_resto!(versao, por: :voce, user: Current.user)
    return render_erro('campaign_journey.versao_ja_escolhida') unless escolheu || mesma_escolha?(link.reload)

    render json: { payload: resultado(link) }
  end

  private

  def campaign
    ::CampaignJourney::ResultFinder.new(Current.account).find!(params[:channel].to_s, params[:id]).campaign
  end

  def versao
    numero = params[:versao].to_s.to_i
    numero if ::CampaignJourney::DuasVersoes::VERSOES.include?(numero)
  end

  def mesma_escolha?(link)
    link.teste_estado == 'escolhida' && link.teste_vencedora == versao
  end

  def resultado(link)
    ::CampaignJourney::DuasVersoes::Resultado.new(link.reload, account: Current.account)
                                             .payload(user: Current.user, account_user: Current.account_user)
  end

  def render_erro(error)
    render json: { error: error }, status: :unprocessable_entity
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end

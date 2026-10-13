# Conversa aberta na campanha do WhatsApp oficial (#1335). Contrato: docs/campaigns/modelos-whatsapp/conversa-aberta.md.
#   GET  campaign_journey/conversa_aberta?campaign_import_id=&inbox_id=&categoria=MARKETING
#        => { payload: { dentro, fora, fecham_logo, conferido_em, precos: { modelo, escrita }, franquia } }
#   POST campaign_journey/conversa_aberta/escrever  { campaign_import_id, inbox_id, objetivo, resposta, tom, base, melhoria, categoria }
#        => { payload: { status, opcoes: [{ texto }], pergunta, sugestoes } }
# Gate: CAMPAIGN_JOURNEY_ENABLED e a flag `campaign_open_window_text` da conta, no servidor (sem elas, 404). Não depende
# da tela de Modelos. Criar campanha exige campaign_manage (CampaignPolicy#create?). O que a pessoa escreve vai ao
# redator como dado; nada dela vai ao log.
class Api::V1::Accounts::CampaignJourney::ConversaAbertaController < Api::V1::Accounts::BaseController
  before_action :ensure_enabled
  before_action :check_authorization
  before_action :fetch_audience_and_inbox

  def show
    payload = ::CampaignJourney::ConversaAberta::Contagem.new(
      account: Current.account, campaign_import: @campaign_import, inbox: @inbox, categoria: categoria
    ).perform
    render json: { payload: payload }
  end

  def escrever
    resultado = ::CampaignJourney::ConversaAberta::Redacao.new(
      account: Current.account, campaign_import: @campaign_import, categoria: categoria
    ).call(objetivo: params[:objetivo].to_s, resposta: params[:resposta].to_s, tom: params[:tom].to_s,
           base: params[:base].to_s, melhoria: params[:melhoria].to_s)
    render json: { payload: payload_da_redacao(resultado) }
  rescue ::Ai::Redacao::Escrever::Indisponivel
    render json: { error: 'conversa_aberta.ia_indisponivel', code: 'ia_indisponivel' }, status: :service_unavailable
  end

  private

  def ensure_enabled
    return if ::CampaignJourney::Config.enabled? && ::CampaignJourney::ConversaAberta.enabled?(Current.account)

    render json: { error: 'conversa_aberta.disabled', code: 'conversa_aberta_disabled' }, status: :not_found
  end

  def check_authorization
    authorize(Campaign, :create?)
  end

  # Contact imports (#1006) nunca são público. A caixa é da conta e do WhatsApp oficial.
  def fetch_audience_and_inbox
    @campaign_import = Current.account.campaign_imports.campaign_flows.find(params.require(:campaign_import_id))
    @inbox = Current.account.inboxes.find(params.require(:inbox_id))
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'conversa_aberta.caixa_invalida', code: 'caixa_invalida' }, status: :unprocessable_entity
  end

  # Só o texto de cada opção vai para a tela.
  def payload_da_redacao(resultado)
    resultado.slice(:status, :pergunta, :sugestoes).merge(opcoes: resultado[:opcoes].map { |opcao| opcao.slice(:texto) })
  end

  def categoria
    params[:categoria].to_s.upcase.presence
  end
end

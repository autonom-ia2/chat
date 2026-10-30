# IA cuida dos comentários (#2212, B2) de um anúncio. A mesma tela e o mesmo Painel do post (B1,
# SeusPostsCuidadoController); muda o alvo. O contrato está em docs/audit/2026-10-30-2212-contrato-api.md.
#
# GET  meta_ads_connection/cuidados                     → { cuidados: [{ ad_id, care }] }: o estado do cuidado de cada
#      anúncio (só banco), para o selo "Cuidando" no detalhe do anúncio.
# GET  meta_ads_connection/ads/:ad_id/cuidado           → o Painel (Crm::MetaAds::ComentariosIa::Painel).
# GET  meta_ads_connection/ads/:ad_id/resumo            → "O que tem nos comentários" (Resumo; 'reading' enquanto conta).
#      Ver: administrador ou `meta_ads_view`.
# PUT  meta_ads_connection/ads/:ad_id/cuidado           message, para_quem, phrases[], status → o Painel.
# POST meta_ads_connection/ads/:ad_id/cuidado/previa    para_quem → os exemplos do passo "como fica" (Previa).
# POST meta_ads_connection/ads/:ad_id/cuidado/ler_antigos → "Ler e mandar" (uma vez por cuidado ligado).
#      Mudar: administrador ou `meta_ads_manage`.
#
# As guardas das abas de comentários do anúncio (#2196, #2197): flags `meta_ads_gestao`, a dos comentários de ao menos
# uma rede e `meta_ads_comentarios_ia` (404 sem elas: nada aqui chama a Meta); conexão ativa com conta de anúncios;
# anúncio dessa conta (senão 404). As redes do cuidado vêm do criativo (Anuncio): só as com post, flag e caixa na
# conta. Sem nenhuma, 422 `no_post` (o anúncio não aparece numa rede ligada) ou `no_inbox` (falta a caixa). Ler os
# comentários pede ver a caixa de cada rede do anúncio (InboxPolicy#show?): sem ver, 403 `not_inbox_member`, antes de
# ler na Meta.
#
# O texto do dono vai só em `message` e `para_quem`; o dos comentários só na resposta, nunca gravado. Ligar, pausar,
# mudar e "Ler e mandar" ficam na Auditoria da conta, sem texto.
class Api::V1::Accounts::Crm::MetaAdsCuidadoController < Api::V1::Accounts::Crm::BaseController
  AUDIT_ACTION = 'meta_ads_comment_care'.freeze
  FLAGS = ['meta_ads_gestao', Crm::MetaAds::ComentariosIa::Cuidar::FLAG].freeze
  REDE_FLAGS = Crm::MetaAds::ComentariosIa::Anuncio::FLAGS.values.freeze
  STATUS = { 'ad_not_found' => :not_found, 'not_connected' => :not_found, 'not_inbox_member' => :forbidden }.freeze

  before_action :ensure_flags
  before_action :ensure_view
  before_action :ensure_manage, only: [:update, :previa, :ler_antigos]
  before_action :load_connection
  before_action :load_anuncio, except: [:cuidados]

  rescue_from Crm::MetaAds::ComentariosIa::Painel::Error, Crm::MetaAds::AdManagement::Error, with: :render_error

  def cuidados
    estados = Crm::MetaAdsCommentCare.where(account_id: Current.account.id, target_kind: 'ad').pluck(:target_id, :status)
    render json: { cuidados: estados.map { |ad_id, care| { ad_id: ad_id, care: care } } }
  end

  def show
    render json: painel.payload
  end

  def resumo
    render json: Crm::MetaAds::ComentariosIa::Resumo.new(account: Current.account, alvo: alvo, fonte: fonte).call
  end

  def update
    painel.salvar!(message: texto(params[:message], 'message'), para_quem: texto(params[:para_quem], 'para_quem'),
                   phrases: frases(params[:phrases]), status: params[:status].to_s, user: Current.user)
    audit_care!('save')
    render json: painel.payload
  end

  def previa
    para_quem = texto(params[:para_quem], 'para_quem')
    return render_error_code('invalid_para_quem') if para_quem.strip.empty?

    render json: Crm::MetaAds::ComentariosIa::Previa.new(account: Current.account, fonte: fonte, para_quem: para_quem).call
  end

  def ler_antigos
    painel.ler_antigos!
    audit_care!('read_old')
    render json: { queued: true }
  end

  private

  def ensure_flags
    ligado = ->(flag) { Current.account.feature_enabled?(flag) }
    head :not_found unless FLAGS.all?(&ligado) && REDE_FLAGS.any?(&ligado)
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless policy.show?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless policy.update?
  end

  def policy
    @policy ||= Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection)
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render_error_code('not_connected') if @connection&.ad_account_id.blank?
  end

  # O id entra no caminho da Graph: só dígitos (o AdManagement recusa o resto, que vira `ad_not_found`).
  def load_anuncio
    @anuncio = Crm::MetaAds::ComentariosIa::Anuncio.ler(@connection, params[:ad_id].to_s)
    return render_error_code('ad_not_found') if @anuncio.nil?
    return render_error_code(@anuncio.post? ? 'no_inbox' : 'no_post') if @anuncio.redes.empty?

    render_error_code('not_inbox_member') unless @anuncio.redes.values.all? { |rede| Pundit.policy!(pundit_user, rede[:inbox]).show? }
  end

  def painel
    @painel ||= Crm::MetaAds::ComentariosIa::Painel.new(account: Current.account, alvo: alvo, fonte: fonte,
                                                        conversation_access: method(:conversa_visivel?))
  end

  def fonte
    @fonte ||= Crm::MetaAds::ComentariosIa::Fonte.anuncio(@anuncio, alvo['networks'])
  end

  def alvo
    @alvo ||= @anuncio.alvo
  end

  # "Ver conversa" só para quem enxerga a conversa (em caixa com restrição, só as dela).
  def conversa_visivel?(conversation)
    Pundit.policy!(pundit_user, conversation).view?
  end

  # Só texto: lista ou objeto virariam outro texto no `to_s` (#2327).
  def texto(value, campo)
    raise Crm::MetaAds::ComentariosIa::Painel::Error, "invalid_#{campo}" unless value.nil? || value.is_a?(String)

    value.to_s
  end

  def frases(value)
    raise Crm::MetaAds::ComentariosIa::Painel::Error, 'invalid_phrases' unless value.is_a?(Array) && value.all?(String)

    value
  end

  def render_error(error)
    render_error_code(error.code)
  end

  def render_error_code(code)
    render json: { error: code }, status: STATUS.fetch(code, :unprocessable_content)
  end

  def audit_care!(action)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'networks' => alvo['networks'], 'ad_id' => alvo['ad_id'], 'action' => action, 'status' => painel.cuidado&.status }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end

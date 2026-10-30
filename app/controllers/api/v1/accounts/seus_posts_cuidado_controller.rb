# IA cuida dos comentários (#2212, B1) num post do Seus posts. O contrato está em docs/audit/2026-10-30-2212-contrato-api.md.
#
# GET  seus_posts/cuidados                              → { cuidados: [{ post_id, care }] }: o selo "Cuidando" da lista.
# GET  seus_posts/posts/:post_id/cuidado                → o Painel (Crm::MetaAds::ComentariosIa::Painel).
# GET  seus_posts/posts/:post_id/resumo                 → "O que tem nos comentários" (Resumo; 'reading' enquanto conta).
#      Ver: administrador ou `posts_view`.
# PUT  seus_posts/posts/:post_id/cuidado                message, para_quem, phrases[], status → o Painel.
# POST seus_posts/posts/:post_id/cuidado/previa         para_quem → os exemplos do passo "como fica" (Previa).
# POST seus_posts/posts/:post_id/cuidado/ler_antigos    → "Ler e mandar" (uma vez por cuidado ligado).
#      Mudar: administrador ou `posts_manage`.
#
# As mesmas guardas do post (SeusPostsComentariosController): ?perfil=, ver a caixa do perfil e o post ser do perfil,
# mais a flag `meta_ads_comentarios_ia`. O texto do dono vai só em `message` e `para_quem`; o dos comentários só na
# resposta, nunca gravado. Ligar, pausar, mudar e "Ler e mandar" ficam na Auditoria da conta, sem texto.
class Api::V1::Accounts::SeusPostsCuidadoController < Api::V1::Accounts::SeusPostsComentariosController
  AUDIT_ACTION = 'seus_posts_comment_care'.freeze
  FLAGS = (Api::V1::Accounts::SeusPostsComentariosController::FLAGS + [Crm::MetaAds::ComentariosIa::Cuidar::FLAG]).freeze

  skip_before_action :ensure_manage
  before_action :ensure_manage, only: [:update, :previa, :ler_antigos]
  skip_before_action :ensure_ids, :load_post, only: [:cuidados]

  rescue_from Crm::MetaAds::ComentariosIa::Painel::Error, with: :render_error

  def cuidados
    estados = Crm::MetaAdsCommentCare.where(account_id: Current.account.id, target_kind: 'post').pluck(:target_id, :status)
    render json: { cuidados: estados.map { |post_id, care| { post_id: post_id, care: care } } }
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
    head :not_found unless FLAGS.all? { |flag| Current.account.feature_enabled?(flag) }
  end

  def painel
    @painel ||= Crm::MetaAds::ComentariosIa::Painel.new(account: Current.account, alvo: alvo, fonte: fonte,
                                                        conversation_access: method(:conversa_visivel?))
  end

  def fonte
    @fonte ||= Crm::MetaAds::ComentariosIa::Fonte.post(@canal, post_id)
  end

  def alvo
    { 'kind' => 'post', 'perfil' => SeusPosts::Perfil.id_do(@canal), 'post_id' => post_id, 'networks' => [SeusPosts::Perfil.rede(@canal)] }
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

  def audit_care!(action)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'network' => SeusPosts::Perfil.rede(@canal), 'perfil' => SeusPosts::Perfil.id_do(@canal), 'post_id' => post_id,
                         'action' => action, 'status' => painel.cuidado&.status }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end

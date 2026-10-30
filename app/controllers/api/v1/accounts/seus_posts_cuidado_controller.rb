# IA cuida dos comentários (#2212, B1) num post do Seus posts. O contrato está em docs/audit/2026-10-30-2212-contrato-api.md.
#
# GET  seus_posts/cuidados                              → { cuidados: [{ post_id, care, network, results }] }: o selo
#      "Cuidando" e a faixa da lista, só os do perfil (?perfil=).
# PUT  seus_posts/cuidados                              status → "Pausar todos" / "Retomar todos" do perfil; a lista.
# GET  seus_posts/posts/:post_id/cuidado                → o Painel (Crm::MetaAds::ComentariosIa::Painel).
# GET  seus_posts/posts/:post_id/resumo                 → "O que tem nos comentários" (Resumo; 'reading' enquanto conta).
#      Ver: administrador ou `posts_view`.
# PUT  seus_posts/posts/:post_id/cuidado                message, para_quem, phrases[], status → o Painel.
# POST seus_posts/posts/:post_id/cuidado/previa         para_quem → os exemplos do passo "como fica" (Previa).
# POST seus_posts/posts/:post_id/cuidado/ler_antigos    → "Ler e mandar" (uma vez por cuidado ligado).
#      Mudar: administrador ou `posts_manage`.
#
# As mesmas guardas do post (SeusPostsComentariosController): ?perfil=, ver a caixa do perfil e o post ser do perfil
# (inclusive no GET do painel, que o pai pula), mais a flag `meta_ads_comentarios_ia`. A chave de mudar vem antes de
# conferir o post: quem só vê recebe 403 sem chamada à Meta. Prévia e resumo com o Jev fora do ar: 422 `ai_unavailable`.
# O texto do dono vai só em `message` e `para_quem`; o dos comentários só na resposta, nunca gravado. Ligar, pausar,
# mudar e "Ler e mandar" ficam na Auditoria da conta, sem texto.
class Api::V1::Accounts::SeusPostsCuidadoController < Api::V1::Accounts::SeusPostsComentariosController
  AUDIT_ACTION = 'seus_posts_comment_care'.freeze
  AI_UNAVAILABLE = 'ai_unavailable'.freeze
  FLAGS = (Api::V1::Accounts::SeusPostsComentariosController::FLAGS + [Crm::MetaAds::ComentariosIa::Cuidar::FLAG]).freeze

  # O pai confere a chave de mudar em todas as escritas e pula o post no `show`. Aqui as duas voltam na ordem certa: a
  # chave antes de ler o post na Meta, e o post em toda ação de um post (o painel também).
  skip_before_action :ensure_manage, :load_post
  before_action :ensure_manage, only: [:update, :previa, :ler_antigos, :mudar_todos]
  before_action :load_post, except: [:cuidados, :mudar_todos]
  skip_before_action :ensure_ids, only: [:cuidados, :mudar_todos]

  rescue_from Crm::MetaAds::ComentariosIa::Painel::Error, with: :render_error

  def cuidados
    render json: { cuidados: cuidados_do_perfil.map { |care| item_da_lista(care) } }
  end

  def mudar_todos
    status = params[:status].to_s
    return render_error_code('invalid_status') unless Crm::MetaAds::ComentariosIa::Painel::STATUSES.include?(status)

    audit_all!(status, mudar_status!(status))
    cuidados
  end

  def show
    render json: painel.payload
  end

  def resumo
    resultado = Crm::MetaAds::ComentariosIa::Resumo.new(account: Current.account, alvo: alvo, fonte: fonte).call
    return render_error_code(AI_UNAVAILABLE) if resultado[:status] == AI_UNAVAILABLE

    render json: resultado
  end

  def update
    painel.salvar!(message: texto(params[:message], 'message'), para_quem: texto(params[:para_quem], 'para_quem'),
                   phrases: frases(params[:phrases]), status: params[:status].to_s, user: Current.user)
    audit_care!('save')
    render json: painel.payload
  end

  def previa
    para_quem = texto(params[:para_quem], 'para_quem')
    return render_error_code('invalid_para_quem') if para_quem.strip.empty? || para_quem.strip.length > Crm::MetaAdsCommentCare::NOTE_LIMIT

    resultado = Crm::MetaAds::ComentariosIa::Previa.new(account: Current.account, fonte: fonte, para_quem: para_quem).call
    # A tela trata qualquer resposta de erro como "não deu para ler": só a prévia pronta vai como prévia.
    return render_error_code(resultado[:status]) unless resultado[:status] == 'ready'

    render json: resultado
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
    { 'kind' => 'post', 'perfil' => SeusPosts::Perfil.id_do(@canal), 'post_id' => post_id, 'networks' => [SeusPosts::Perfil.rede(@canal)],
      'inbox_id' => @canal.inbox.id }
  end

  def cuidados_do_perfil
    Crm::MetaAdsCommentCare.where(account_id: Current.account.id, target_kind: 'post', inbox_id: @canal.inbox.id).order(:id)
  end

  def item_da_lista(care)
    { post_id: care.target_id, care: care.status, network: care.network,
      results: Crm::MetaAds::ComentariosIa::Painel.resultados(Current.account, care) }
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

  # Tudo de uma vez, numa transação: o status muda sem regravar o resto (um cuidado antigo que não passaria na validação
  # de hoje não trava os outros). Devolve os posts mudados, para a Auditoria depois de mudar.
  def mudar_status!(status)
    Crm::MetaAdsCommentCare.transaction do
      mudados = cuidados_do_perfil.where.not(status: status).lock.pluck(:id, :target_id)
      Crm::MetaAdsCommentCare.where(id: mudados.map(&:first)).update_all(status: status, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      mudados.map(&:last)
    end
  end

  def audit_all!(status, post_ids)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'network' => SeusPosts::Perfil.rede(@canal), 'perfil' => SeusPosts::Perfil.id_do(@canal), 'post_ids' => post_ids,
                         'action' => 'all', 'status' => status }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
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

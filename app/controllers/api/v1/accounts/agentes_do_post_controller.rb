# IA cuida dos comentários em Agentes (#2469, PR 3a do #2436): o cartão de cada post ou anúncio com o cuidado, no
# Instagram e no Facebook (Crm::MetaAds::ComentariosIa::NoAgentes).
#
# GET  agentes_do_post             → { cuidados: [{ id, kind, target_id, perfil, network, status }] }: a lista e a
#      contagem do cabeçalho, só do banco. Só os alvos que quem abre pode ver.
# GET  agentes_do_post/anuncios → { anuncios: [{ id, name, image_url, care, waiting }] }: os anúncios do "Qual post?" ao
#      criar o cuidado (#2479), os da lista de Anúncios dos últimos 30 dias, mais os de fora com comentário esperando
#      (#2519), primeiro os que esperam; só do banco (AnunciosParaCuidar). As guardas são as de ver o cuidado do anúncio;
#      sem a conexão ativa, 404 `not_connected`.
# GET  agentes_do_post/:id         → o cartão e a página: o item, mais legenda, capa, foto, nota, portas[] e
#      comentarios { status, results, no_privado[], esperando[], nao_respondo[] }, lidos na Meta, sem IA. A leitura fica
#      guardada DETALHE_TTL por pessoa (abrir Agentes com muitos posts cuidados não volta à Meta a cada vez, e não gasta o
#      limite dela, que o motor usa na mesma conexão); pausar ou voltar muda o updated_at do cuidado e troca a chave. A
#      versão da chave (v2, #2481) muda quando o detalhe ganha campo novo.
# PUT  agentes_do_post/:id/estado  status ('on' | 'paused') → Pausar e Voltar a cuidar: só o estado (voltar recomeça a
#      contar daqui), sem mexer no que o dono escreveu. Devolve o detalhe.
# POST agentes_do_post/:id/testar  pergunta, network → { status: 'ready', decisao, motivo, escrita? } (#2510): o que o
#      motor faria com o comentário (NoAgentes#testar) e, quando ele manda o privado, o que escreveria. Nada é publicado
#      nem gravado; IA fora do ar é 422 `ai_unavailable`; IA barrada (sem chave, desligada) é 422 com o código dela.
#
# As guardas são as das telas do cuidado de cada alvo, para ninguém ver aqui o que não vê lá:
# - todas: a flag `meta_ads_comentarios_ia` (404 sem ela);
# - post (SeusPostsCuidadoController): a flag `seus_posts` e a dos comentários da rede do post (#2520), ver (`posts_view`) ou mudar
#   (`posts_manage`) e ver a caixa do perfil;
# - anúncio (Crm::MetaAdsCuidadoController): a flag dos comentários de ao menos uma rede (a gestão não, #2520), ver
#   (`meta_ads_view`) ou mudar (`meta_ads_manage`), conexão ativa (sem ela, o anúncio sai da lista e abre com 404) e
#   ver a caixa de TODAS as redes do anúncio.
# Mudar e Testar pedem a chave de mudar do alvo: a mesma de editar o cuidado. A lista mostra só o que a pessoa pode ver;
# o anúncio cuja caixa ela não vê dá 403 `not_inbox_member` ao abrir.
#
# O texto do Testar vai só na resposta, nunca gravado nem no log. Pausar e voltar ficam na Auditoria da conta, sem texto,
# com a ação de cada alvo.
class Api::V1::Accounts::AgentesDoPostController < Api::V1::Accounts::BaseController
  FLAG = Crm::MetaAds::ComentariosIa::Cuidar::FLAG
  POST_FLAGS = %w[seus_posts].freeze
  REDE_FLAGS_POR_REDE = Crm::MetaAds::ComentariosIa::Anuncio::FLAGS
  REDE_FLAGS = REDE_FLAGS_POR_REDE.values.freeze
  AUDIT_ACTION = { 'post' => Api::V1::Accounts::SeusPostsCuidadoController::AUDIT_ACTION,
                   'ad' => Api::V1::Accounts::Crm::MetaAdsCuidadoController::AUDIT_ACTION }.freeze
  PERGUNTA_LIMIT = 1_000
  DETALHE_TTL = 2.minutes
  # A policy de cada alvo, a mesma da tela do cuidado dele.
  POLITICA = { 'post' => :seus_posts, 'ad' => ::Crm::MetaAdsConnection }.freeze
  STATUS = { 'not_found' => :not_found, 'ad_not_found' => :not_found, 'not_connected' => :not_found, 'forbidden' => :forbidden,
             'not_inbox_member' => :forbidden }.freeze

  class Recusa < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  before_action :ensure_flag
  before_action :load_care, except: [:index, :anuncios]
  before_action :ensure_manage, only: [:estado, :testar]
  before_action :load_alvo, except: [:index, :show, :anuncios]

  rescue_from Recusa, Crm::MetaAds::ComentariosIa::Painel::Error, Crm::MetaAds::AdManagement::Error, with: :render_error

  def index
    cares = Crm::MetaAdsCommentCare.where(account_id: Current.account.id).includes(inbox: :channel).order(:id)
    visiveis = cares.select { |care| ve?(care) && (care.target_kind == 'post' || conectado?) }
    render json: { cuidados: visiveis.map { |care| Crm::MetaAds::ComentariosIa::NoAgentes.item(care) } }
  end

  # Só quem veria o cuidado do anúncio: as flags de Anúncios, a chave de ver e a conexão ativa. A caixa de cada rede se
  # confere ao abrir o cuidado (o criativo é que diz as caixas).
  def anuncios
    raise Recusa, 'not_found' unless flags?('ad')
    raise Recusa, 'forbidden' unless policy('ad').show?
    raise Recusa, 'not_connected' unless conectado?

    render json: { anuncios: Crm::MetaAds::ComentariosIa::AnunciosParaCuidar.new(conexao).lista }
  end

  # O detalhe guardado só depois de passar as guardas (Recusa não é guardada). A chave leva a pessoa (os resultados e o
  # "Ver conversa" dependem do que ela vê) e o updated_at do cuidado.
  def show
    lido = Rails.cache.fetch(chave_do_detalhe, expires_in: DETALHE_TTL) do
      load_alvo
      no_agentes.detalhe
    end
    render json: lido.merge(can_manage: manage?)
  end

  def estado
    status = params[:status].to_s
    raise Recusa, 'invalid_status' unless Crm::MetaAdsCommentCare::STATUSES.include?(status)

    mudou = Crm::MetaAdsCommentCare.transaction { mudar_estado!(status) }
    @care.reload
    audit!(status) if mudou
    render json: detalhe
  end

  def testar
    pergunta = params[:pergunta]
    raise Recusa, 'invalid_pergunta' unless pergunta.is_a?(String) && pergunta.strip.length.between?(1, PERGUNTA_LIMIT)

    render json: no_agentes.testar(pergunta: pergunta.strip, network: params[:network].to_s)
  rescue Crm::MetaAds::ComentariosIa::Classificador::Bloqueado => e
    render_error_code(e.code)
  rescue Crm::MetaAds::ComentariosIa::Classificador::Indisponivel
    render_error_code('ai_unavailable')
  end

  private

  def ensure_flag
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  # Ver: as flags do alvo, a chave de ver e, no post, a caixa do perfil (no anúncio, a caixa só sai da Meta: ao abrir).
  def ve?(care)
    return false unless flags?(care.target_kind, care.network) &&
                        policy(care.target_kind).public_send(care.target_kind == 'post' ? :index? : :show?)

    care.target_kind == 'ad' || (care.inbox.present? && SeusPosts::Caixa.new(inbox: care.inbox, viewer: pundit_user).ve?)
  end

  # #2520: a régua de tela, webhook e motor é a mesma: a flag do cuidado (ensure_flag) e a dos comentários da rede do
  # cuidado (as duas valem para o das duas redes, e a lista de anúncios pede uma). A gestão de Anúncios não entra.
  def flags?(kind, network = nil)
    ligada = ->(flag) { Current.account.feature_enabled?(flag) }
    return false unless flags_da_rede(network).any?(&ligada)
    return POST_FLAGS.all?(&ligada) if kind == 'post'

    # O anúncio mora no CRM (#2479): sem ele, as telas do cuidado do anúncio (Crm::BaseController) não abrem.
    ::Crm::Config.enabled?
  end

  # A da rede do cuidado; o das duas redes (e a lista, sem rede) fica com qualquer uma.
  def flags_da_rede(network)
    REDE_FLAGS_POR_REDE.key?(network) ? [REDE_FLAGS_POR_REDE[network]] : REDE_FLAGS
  end

  def policy(kind)
    @policies ||= {}
    @policies[kind] ||= Pundit.policy!(pundit_user, POLITICA.fetch(kind))
  end

  def manage?
    kind = @care.target_kind
    kind == 'post' ? policy(kind).manage? : policy(kind).update?
  end

  def load_care
    @care = Crm::MetaAdsCommentCare.find_by(id: params[:id], account_id: Current.account.id)
    raise Recusa, 'not_found' if @care.nil? || !flags?(@care.target_kind, @care.network)
    raise Recusa, 'forbidden' unless ve?(@care)
  end

  def ensure_manage
    raise Recusa, 'forbidden' unless manage?
  end

  def load_alvo
    @care.target_kind == 'post' ? alvo_do_post : alvo_do_anuncio
  end

  def alvo_do_post
    canal = @care.inbox.channel
    @fonte = Crm::MetaAds::ComentariosIa::Fonte.post(canal, @care.target_id)
    @alvo = { 'kind' => 'post', 'perfil' => SeusPosts::Perfil.id_do(canal), 'post_id' => @care.target_id,
              'networks' => [SeusPosts::Perfil.rede(canal)], 'inbox_id' => @care.inbox_id }
  end

  # O mesmo do Crm::MetaAdsCuidadoController#load_anuncio: o criativo diz as redes e as caixas.
  def alvo_do_anuncio
    anuncio = ler_anuncio
    raise Recusa, anuncio.post? ? 'no_inbox' : 'no_post' if anuncio.redes.empty?
    raise Recusa, 'not_inbox_member' unless anuncio.redes.values.all? { |rede| Pundit.policy!(pundit_user, rede[:inbox]).show? }

    @alvo = anuncio.alvo
    @fonte = Crm::MetaAds::ComentariosIa::Fonte.anuncio(anuncio, @alvo['networks'])
  end

  def conexao
    @conexao ||= ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
  end

  def conectado?
    conexao&.ad_account_id.present?
  end

  def ler_anuncio
    connection = conexao
    raise Recusa, 'not_connected' unless conectado?

    Crm::MetaAds::ComentariosIa::Anuncio.ler(connection, @care.target_id) || raise(Recusa, 'ad_not_found')
  end

  # Só o estado muda, como o "Pausar todos" do Seus posts (SeusPostsCuidadoController#mudar_status!): o que o dono
  # escreveu não é regravado, e um cuidado antigo que não passaria na validação de hoje ainda pausa. Voltar a cuidar só
  # liga o que passa nela (422 `invalid_care`), e recomeça a contar daqui (Painel#religar!).
  # Dentro da transação da action, com a linha travada. true quando mudou (só então vai para a Auditoria).
  def mudar_estado!(status)
    atual = Crm::MetaAdsCommentCare.lock.find(@care.id)
    return false if atual.status == status
    raise Recusa, 'invalid_care' if status == 'on' && !atual.tap { |care| care.status = status }.valid?

    agora = Time.current
    religado = status == 'on' ? { started_at: agora, read_old_at: nil } : {}
    Crm::MetaAdsCommentCare.where(id: atual.id).update_all(status: status, updated_at: agora, **religado) # rubocop:disable Rails/SkipsModelValidations
    Crm::MetaAds::ComentariosIa::AssinarFeedJob.para!(atual.reload) # #2520: voltar a cuidar no Facebook assina o `feed`
    true
  end

  def painel
    @painel ||= Crm::MetaAds::ComentariosIa::Painel.new(account: Current.account, alvo: @alvo, fonte: @fonte,
                                                        conversation_access: method(:conversa_visivel?), viewer: Current.user)
  end

  def no_agentes
    Crm::MetaAds::ComentariosIa::NoAgentes.new(care: @care, fonte: @fonte, painel: painel, no_privado: no_privado)
  end

  # #2481: o grupo "no privado" da gaveta Comentários, com as conversas que a pessoa vê.
  def no_privado
    Crm::MetaAds::ComentariosIa::NoPrivado.new(account: Current.account, care: @care, viewer: Current.user,
                                               conversation_access: method(:conversa_visivel?))
  end

  def detalhe
    no_agentes.detalhe.merge(can_manage: manage?)
  end

  def chave_do_detalhe
    ['agentes_do_post', 'v2', Current.account.id, @care.id, @care.updated_at.to_f, Current.user&.id].join(':')
  end

  # "Ver conversa" só para quem enxerga a conversa (em caixa com restrição, só as dela).
  def conversa_visivel?(conversation)
    Pundit.policy!(pundit_user, conversation).view?
  end

  def audit!(status)
    alvo = @care.target_kind == 'post' ? { 'perfil' => @alvo['perfil'], 'post_id' => @care.target_id } : { 'ad_id' => @care.target_id }
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION.fetch(@care.target_kind),
      audited_changes: alvo.merge('networks' => @alvo['networks'], 'action' => 'save', 'origin' => 'agents', 'status' => status)
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end

  def render_error(error)
    render_error_code(error.code)
  end

  def render_error_code(code)
    render json: { error: code }, status: STATUS.fetch(code, :unprocessable_content)
  end
end

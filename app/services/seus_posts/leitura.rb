# Seus posts (#2302, F1 #2304): o que a página mostra de um perfil.
#
# Perfis são as caixas da conta com Instagram (login do Instagram) ou Página do Facebook que a pessoa vê
# (InboxPolicy#show?, SeusPosts::Caixa); a Página com Instagram ligado continua sendo Página (#2321). Caixa que a pessoa não vê
# nem aparece: nome, posts e números do perfil saem do mesmo lugar que a caixa (revisão final do #2312). O id do
# perfil é do canal ("instagram-12", "facebook-3"). Sem perfil escolhido, o primeiro.
#
# Do perfil escolhido: os números do período com o anterior (Crm::MetaAds::Organico, os mesmos da aba de Anúncios,
# sem os melhores posts), as conversas da caixa no período e no anterior, e os posts (SeusPosts::Posts). Os posts são
# lidos uma vez para os 90 dias e filtrados aqui pelo período. Cada leitura da Meta fica 15 minutos guardada; a última
# boa fica um dia, para servir quando a Meta falhar ou passar do tempo (`stale: true`). Meta fora nos números: o perfil
# vem `unavailable`; só nos posts: os números ficam e os posts vêm `posts_status: 'unavailable'`.
class SeusPosts::Leitura
  DIAS = Crm::MetaAds::Organico::Periodo::DIAS
  CACHE_TTL = 15.minutes
  ULTIMA_BOA_TTL = 1.day
  # Depois de uma falha sem leitura boa guardada, a próxima tentativa espera um pouco (limite de uso da Meta).
  FALHA_TTL = 2.minutes
  SEM_ESPERA = [Meta::AdsGraphClient::Prazo::TEMPO, 'espera'].freeze
  CACHE_VERSION = 'v2'.freeze
  NOME_TTL = 30.days

  class PerfilDesconhecido < StandardError; end

  def initialize(account:, perfil:, days:, viewer:)
    @account = account
    @perfil_id = perfil
    @periodo = Crm::MetaAds::Organico::Periodo.new(days, zona: zona)
    @viewer = viewer
  end

  def perform
    canal = escolhido
    {
      days: @periodo.dias, from: @periodo.de, to: @periodo.ate,
      perfil: canal && perfil(canal),
      perfis: canais.map { |item| { id: id_do(item), network: rede(item), name: Rails.cache.read(chave_do_nome(item)) } }
    }
  end

  private

  # Números e posts dividem o teto de tempo do perfil (SeusPosts::Orcamento).
  def perfil(canal)
    prazo = SeusPosts::Orcamento.prazo
    numeros = ler_numeros(canal, prazo)
    base = { id: id_do(canal), network: rede(canal), inbox_id: canal.inbox.id, **numeros.except(:top_posts) }
    return base unless numeros[:status] == 'ok'

    guardar_nome(canal, numeros)
    base.merge(messages: mensagens(canal.inbox, numeros), **ler_posts(canal, prazo))
  rescue Crm::MetaAds::Organico::Indisponivel => e
    Rails.logger.warn("[SeusPosts] conta=#{@account.id} perfil=#{id_do(canal)} status=unavailable code=#{e.codigo}")
    { id: id_do(canal), network: rede(canal), inbox_id: canal.inbox.id, status: 'unavailable' }
  end

  # As conversas do período e, quando os números se comparam com o anterior, as do anterior.
  def mensagens(inbox, numeros)
    caixa = SeusPosts::Caixa.new(inbox: inbox, viewer: @viewer)
    anterior = caixa.conversas(@periodo.intervalo_anterior) if numeros[:previous]
    { count: caixa.conversas(@periodo.intervalo), previous: anterior }
  end

  # Os posts do período, o normal e se a lista parou no teto de posts lidos.
  def ler_posts(canal, prazo)
    lidos = guardado("posts:#{id_do(canal)}") { SeusPosts::Posts.para(canal, periodo: @periodo, prazo: prazo).perform }
    return { posts_status: lidos[:status], posts: [], normal: nil } unless lidos[:status] == 'ok'

    inicio = @periodo.atual[:since]
    { posts_status: 'ok', posts: lidos[:posts].select { |post| Time.zone.parse(post[:created_time].to_s).to_i >= inicio },
      normal: lidos[:normal], posts_truncated: lidos[:truncated] == true, posts_stale: lidos[:stale] == true }
  rescue Crm::MetaAds::Organico::Indisponivel => e
    Rails.logger.warn("[SeusPosts] conta=#{@account.id} perfil=#{id_do(canal)} posts=unavailable code=#{e.codigo}")
    { posts_status: 'unavailable', posts: [], normal: nil }
  end

  # O nome do perfil na Meta (@usuario do Instagram, nome da Página), para a escolha do perfil no topo sem uma chamada
  # por perfil: fica guardado quando o perfil é lido. Perfil ainda não lido vai sem nome, e a tela diz a rede.
  def guardar_nome(canal, numeros)
    nome = numeros[:username] ? "@#{numeros[:username]}" : numeros[:name]
    Rails.cache.write(chave_do_nome(canal), nome, expires_in: NOME_TTL) if nome.present?
  end

  def chave_do_nome(canal)
    "seus_posts:#{CACHE_VERSION}:#{@account.id}:nome:#{id_do(canal)}"
  end

  def ler_numeros(canal, prazo)
    guardado("numeros:#{id_do(canal)}:#{@periodo.dias}") do
      classe_dos_numeros(canal).new(channel: canal, periodo: @periodo, prazo: prazo).perform
    end
  end

  # Só o que veio ok fica guardado: "Libere…" lê de novo na próxima vez. Meta fora ou passou do tempo: a última leitura
  # boa, marcada `stale`; sem ela, a falha sobe e a próxima tentativa espera FALHA_TTL.
  def guardado(chave)
    chave = "seus_posts:#{CACHE_VERSION}:#{@account.id}:#{chave}"
    lido = Rails.cache.read(chave)
    return lido if lido

    recente_falhou!(chave)
    yield.tap { |dados| guardar(chave, dados) if dados[:status] == 'ok' }
  rescue Crm::MetaAds::Organico::Indisponivel => e
    # Falha da Meta (limite de uso, fora do ar): a próxima tentativa espera, com ou sem cópia antiga para servir. O
    # nosso teto de tempo ('tempo') não é falha da Meta, e 'espera' já é a própria espera.
    Rails.cache.write("#{chave}:falha", true, expires_in: FALHA_TTL) unless SEM_ESPERA.include?(e.codigo)
    ultima = Rails.cache.read("#{chave}:ultima")
    return ultima.merge(stale: true) if ultima

    raise
  end

  def guardar(chave, dados)
    Rails.cache.write(chave, dados, expires_in: CACHE_TTL)
    Rails.cache.write("#{chave}:ultima", dados, expires_in: ULTIMA_BOA_TTL)
  end

  def recente_falhou!(chave)
    raise Crm::MetaAds::Organico::Indisponivel.new('falhou há pouco', codigo: 'espera') if Rails.cache.read("#{chave}:falha")
  end

  def classe_dos_numeros(canal)
    canal.is_a?(Channel::Instagram) ? SeusPosts::NumerosInstagram : SeusPosts::NumerosPagina
  end

  def escolhido
    return canais.first unless @perfil_id

    canais.find { |canal| id_do(canal) == @perfil_id } || raise(PerfilDesconhecido)
  end

  def canais
    @canais ||= (com_caixa(Channel::Instagram.where(account_id: @account.id)) +
                 com_caixa(Channel::FacebookPage.where(account_id: @account.id)))
                .select { |canal| SeusPosts::Caixa.new(inbox: canal.inbox, viewer: @viewer).ve? }
  end

  # Só canal com caixa nesta conta: é a caixa que tem as conversas e que o "Libere o acesso" reautoriza.
  # A Página entra mesmo com instagram_id: o Chatwoot o grava em toda Página com Instagram ligado (#2321).
  def com_caixa(escopo)
    escopo.where(id: Inbox.where(account_id: @account.id, channel_type: escopo.klass.name).select(:channel_id))
          .includes(:inbox).order(:id).to_a
  end

  def id_do(canal)
    "#{rede(canal)}-#{canal.id}"
  end

  def rede(canal)
    canal.is_a?(Channel::Instagram) ? 'instagram' : 'facebook'
  end

  def zona
    (@account.reporting_timezone.present? && ActiveSupport::TimeZone[@account.reporting_timezone]) || Time.zone
  end
end

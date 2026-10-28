# Seus posts (#2302, F1 #2304): o que a página mostra de um perfil, no formato do protótipo aprovado (r15).
#
# Perfis são as caixas da conta com Instagram (login do Instagram) ou Página do Facebook; o Instagram pelo Messenger
# não conta como Página. O id do perfil é do canal ("instagram-12", "facebook-3"), não da caixa: o id da caixa só vai
# para quem a vê (SeusPosts::Caixa). Sem perfil escolhido, o primeiro da conta.
#
# Do perfil escolhido: os números do período com o anterior (Crm::MetaAds::Organico, os mesmos da aba de Anúncios,
# sem os melhores posts) e os posts (SeusPosts::Posts). A leitura da Meta fica 15 minutos guardada por perfil e
# período. Meta fora só no perfil: ele vem `unavailable`, sem derrubar a página.
class SeusPosts::Leitura
  DIAS = Crm::MetaAds::Organico::Periodo::DIAS
  CACHE_TTL = 15.minutes
  CACHE_VERSION = 'v1'.freeze
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

  def perfil(canal)
    numeros = ler_numeros(canal)
    base = { id: id_do(canal), network: rede(canal), **numeros.except(:top_posts) }
    caixa = SeusPosts::Caixa.new(inbox: canal.inbox, viewer: @viewer)
    return bloqueado(base, caixa) unless numeros[:status] == 'ok'

    guardar_nome(canal, numeros)
    posts = ler_posts(canal)
    base.merge(messages: { count: caixa.conversas(@periodo.intervalo), inbox_id: caixa.id_para_quem_age },
               posts_status: posts[:status], posts: posts[:posts] || [], normal: posts[:normal])
  rescue Crm::MetaAds::Organico::Indisponivel => e
    Rails.logger.warn("[SeusPosts] conta=#{@account.id} perfil=#{id_do(canal)} status=unavailable code=#{e.codigo}")
    { id: id_do(canal), network: rede(canal), status: 'unavailable' }
  end

  # "Libere o acesso" reautoriza a caixa. Na Página, o nome que vem é o da caixa: só para quem recebe o id dela.
  def bloqueado(base, caixa)
    inbox_id = caixa.id_para_quem_age
    (inbox_id ? base : base.except(:name)).merge(inbox_id: inbox_id)
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

  def ler_numeros(canal)
    guardado("numeros:#{id_do(canal)}:#{@periodo.dias}") { classe_dos_numeros(canal).new(channel: canal, periodo: @periodo).perform }
  end

  def ler_posts(canal)
    guardado("posts:#{id_do(canal)}:#{@periodo.dias}") { SeusPosts::Posts.para(canal, periodo: @periodo).perform }
  end

  # Só o que veio ok fica guardado: "Libere…" e falha leem de novo na próxima vez.
  def guardado(chave)
    chave = "seus_posts:#{CACHE_VERSION}:#{@account.id}:#{chave}"
    lido = Rails.cache.read(chave)
    return lido if lido

    yield.tap { |dados| Rails.cache.write(chave, dados, expires_in: CACHE_TTL) if dados[:status] == 'ok' }
  end

  def classe_dos_numeros(canal)
    canal.is_a?(Channel::Instagram) ? SeusPosts::NumerosInstagram : SeusPosts::NumerosPagina
  end

  def escolhido
    return canais.first unless @perfil_id

    canais.find { |canal| id_do(canal) == @perfil_id } || raise(PerfilDesconhecido)
  end

  def canais
    @canais ||= com_caixa(Channel::Instagram.where(account_id: @account.id)) +
                com_caixa(Channel::FacebookPage.where(account_id: @account.id, instagram_id: nil))
  end

  # Só canal com caixa nesta conta: é a caixa que tem as conversas e que o "Libere o acesso" reautoriza.
  def com_caixa(escopo)
    escopo.where(id: Inbox.where(account_id: @account.id, channel_type: escopo.klass.name).select(:channel_id)).order(:id).to_a
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

# Seus posts (#2199): o que a aba mostra, no formato que a tela já usa (o mesmo do protótipo aprovado). Uma Página
# do Facebook e um Instagram (login do Instagram) por conta, os primeiros conectados; a Página com Instagram ligado
# continua sendo a Página (#2321). A leitura da Meta fica 15 minutos guardada por lugar e período, para não gastar o limite de
# chamadas a cada troca de aba; as conversas da caixa no período são contadas na hora.
#
# Acesso: SeusPosts::Caixa (contagem de conversas e id da caixa só do que a pessoa vê; parecer da sessão Funções).
class Crm::MetaAds::Organico::Tela
  CACHE_TTL = 15.minutes
  # Muda quando o formato guardado muda, para a leitura antiga não ser servida depois do deploy (v2: sem anúncio).
  CACHE_VERSION = 'v2'.freeze

  # viewer: o pundit_user do controller ({ user:, account:, account_user: }).
  def initialize(account:, days:, viewer:)
    @account = account
    @periodo = Crm::MetaAds::Organico::Periodo.new(days, zona: zona)
    @viewer = viewer
  end

  # Meta fora num lugar só: aquele cartão fica indisponível ("Tentar de novo" só nele). Nos dois, a tela inteira (503).
  def perform
    lugares = { page: lugar(pagina, Crm::MetaAds::Organico::Pagina),
                instagram: lugar(instagram, Crm::MetaAds::Organico::Instagram) }
    raise Crm::MetaAds::Organico::Indisponivel, 'Página e Instagram indisponíveis' if lugares.values.all? { |dados| dados[:status] == 'unavailable' }

    { days: @periodo.dias, from: @periodo.de, to: @periodo.ate, **lugares }
  end

  private

  def lugar(channel, klass)
    return { status: 'not_connected' } unless channel

    inbox = channel.inbox
    dados = ler_meta_do_lugar(channel, klass)
    return dados if dados[:status] == 'unavailable'
    return bloqueado(dados, inbox) unless dados[:status] == 'ok'

    caixa = SeusPosts::Caixa.new(inbox: inbox, viewer: @viewer)
    dados.merge(messages: { count: caixa.conversas(@periodo.intervalo), inbox_id: caixa.id_para_quem_age })
  end

  # "Libere…" reautoriza esta caixa. Na Página, o nome que vai junto é o da caixa: só para quem recebe o id dela.
  def bloqueado(dados, inbox)
    inbox_id = SeusPosts::Caixa.new(inbox: inbox, viewer: @viewer).id_para_quem_age
    (inbox_id ? dados : dados.except(:name)).merge(inbox_id: inbox_id)
  end

  def ler_meta_do_lugar(channel, klass)
    ler_meta(channel, klass)
  rescue Crm::MetaAds::Organico::Indisponivel => e
    # Só o lugar, o status e o código: a mensagem da Meta não vai para o log.
    Rails.logger.warn("[MetaAdsOrganico] conta=#{@account.id} lugar=#{klass.name.demodulize} status=unavailable code=#{e.codigo}")
    { status: 'unavailable' }
  end

  def ler_meta(channel, klass)
    chave = "crm:meta_ads:organico:#{CACHE_VERSION}:#{@account.id}:#{klass.name.demodulize}:#{channel.id}:#{@periodo.dias}"
    guardado = Rails.cache.read(chave)
    return guardado if guardado

    klass.new(channel: channel, periodo: @periodo).perform.tap do |dados|
      Rails.cache.write(chave, dados, expires_in: CACHE_TTL) if dados[:status] == 'ok'
    end
  end

  def zona
    (@account.reporting_timezone.present? && ActiveSupport::TimeZone[@account.reporting_timezone]) || Time.zone
  end

  # Só canal com caixa: é a caixa que tem as conversas e que o "Libere…" reautoriza.
  # Sem filtrar instagram_id: o Chatwoot o grava em toda Página com Instagram ligado, e ela continua sendo a Página (#2321).
  def pagina
    Channel::FacebookPage.joins(:inbox).where(account_id: @account.id).order(:id).first
  end

  def instagram
    Channel::Instagram.joins(:inbox).where(account_id: @account.id).order(:id).first
  end
end

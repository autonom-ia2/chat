# Seus posts (#2199): o que a aba mostra, no formato que a tela já usa (o mesmo do protótipo aprovado). Uma Página
# do Facebook e um Instagram (login do Instagram) por conta, os primeiros conectados; o Instagram pelo Messenger não
# conta como Página. A leitura da Meta fica 15 minutos guardada por lugar e período, para não gastar o limite de
# chamadas a cada troca de aba; as conversas da caixa no período são contadas na hora.
#
# Acesso (parecer da sessão Funções, 27/10; mesma regra do painel de desempenho #2254, "os números são do que a pessoa
# vê"): a contagem de conversas é só das que a pessoa vê (Conversations::PermissionFilterService); quem não vê a caixa
# recebe contagem nula, nunca zero. O id da caixa vai só para quem vê a caixa ou pode reautorizá-la
# (integration_manage).
class Crm::MetaAds::Organico::Tela
  CACHE_TTL = 15.minutes

  # viewer: o pundit_user do controller ({ user:, account:, account_user: }).
  def initialize(account:, days:, viewer:)
    @account = account
    @periodo = Crm::MetaAds::Organico::Periodo.new(days, zona: zona)
    @viewer = viewer
  end

  def perform
    {
      days: @periodo.dias, from: @periodo.de, to: @periodo.ate,
      page: lugar(pagina, Crm::MetaAds::Organico::Pagina),
      instagram: lugar(instagram, Crm::MetaAds::Organico::Instagram)
    }
  end

  private

  def lugar(channel, klass)
    return { status: 'not_connected' } unless channel

    inbox = channel.inbox
    dados = ler_meta(channel, klass)
    # "Libere…" reautoriza esta caixa.
    return dados.merge(inbox_id: inbox_id_para_quem_age(inbox)) unless dados[:status] == 'ok'

    dados.merge(messages: { count: conversas_visiveis(inbox), inbox_id: inbox_id_para_quem_age(inbox) })
  end

  def conversas_visiveis(inbox)
    return unless ve_a_caixa?(inbox)

    Conversations::PermissionFilterService.new(@account.conversations, @viewer[:user], @account, for_reading: true).perform
                                          .where(inbox_id: inbox.id, created_at: @periodo.intervalo).count
  end

  def inbox_id_para_quem_age(inbox)
    inbox.id if ve_a_caixa?(inbox) || @viewer[:account_user]&.permission_granted?('integration_manage')
  end

  def ve_a_caixa?(inbox)
    Pundit.policy!(@viewer, inbox).show?
  end

  def ler_meta(channel, klass)
    chave = "crm:meta_ads:organico:#{@account.id}:#{klass.name.demodulize}:#{channel.id}:#{@periodo.dias}"
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
  def pagina
    Channel::FacebookPage.joins(:inbox).where(account_id: @account.id, instagram_id: nil).order(:id).first
  end

  def instagram
    Channel::Instagram.joins(:inbox).where(account_id: @account.id).order(:id).first
  end
end

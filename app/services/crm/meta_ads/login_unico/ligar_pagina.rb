# Login único (#2338): liga a Página escolhida no passo "Confira a Página" sem um segundo login. É o mesmo resultado do
# "Entrar com o Facebook" da caixa da Página (Api::V1::Accounts::CallbacksController): a Página com caixa nesta conta
# ganha o token novo (como reautorizar); sem caixa, nasce uma, com o nome da Página. Com a caixa ligada, comentários e
# formulários do Facebook e Seus posts usam a Página sem pedir mais nada.
#
# O token da Página sai de Crm::MetaAds::LoginUnico::TokenDaPagina, o ponto que depende do tipo de token do login.
# Quem pode o quê fica com o controller: criar caixa é `inbox_manage`; trocar o token de uma caixa é `integration_manage`.
class Crm::MetaAds::LoginUnico::LigarPagina
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  # O que a caixa da Página usa: mensagens do Messenger e a assinatura do webhook da Página.
  INBOX_PERMISSIONS = %w[pages_messaging pages_manage_metadata].freeze

  def initialize(connection)
    @connection = connection
  end

  # A caixa da Página já existe nesta conta? (o controller decide a permissão por isto)
  def existing(page_id)
    Channel::FacebookPage.find_by(account_id: @connection.account_id, page_id: page_id.to_s)
  end

  # Inbox da Página. Erros: `not_own_token` (modo parceiro), `missing_permissions` (a caixa que já existe perderia o que
  # usa) e os de TokenDaPagina (`page_not_granted`, `reconnect`, `meta_unavailable`).
  def call(page_id)
    raise Error, 'not_own_token' unless @connection.own_token?

    channel = existing(page_id)
    ensure_inbox_permissions! if channel

    tokens = Crm::MetaAds::LoginUnico::TokenDaPagina.new(@connection).call(page_id.to_s)
    raise Error, tokens[:error] if tokens[:error]

    channel ? reauthorize(channel, tokens) : create(page_id.to_s, tokens)
  end

  private

  # A caixa que já funciona só troca de token se este login concedeu o que ela usa. Sem isso, o Messenger dela pararia
  # em silêncio (o login de Anúncios pode ter vindo sem as permissões da caixa). Sem a lista da Meta, não troca às cegas:
  # o acesso vencido pede `reconnect`; a Meta fora, `meta_unavailable`.
  def ensure_inbox_permissions!
    result = Meta::AdsGraphClient.new(access_token: @connection.read_token).permissions
    raise Error, Crm::MetaAds::LoginUnico::TokenDaPagina.failure(result) unless result.ok

    granted = Array(result.data.to_h['data']).filter_map { |row| row['permission'] if row.is_a?(Hash) && row['status'] == 'granted' }
    raise Error, 'missing_permissions' unless (INBOX_PERMISSIONS - granted).empty?
  end

  # Tokens, nome e Instagram num só save; o alerta de reautorização (Redis e evento) sai só depois dele gravado.
  def reauthorize(channel, tokens)
    details = page_details(tokens[:page])
    channel.update!(user_access_token: tokens[:user], page_access_token: tokens[:page], **details.compact)
    channel.reauthorized!
    channel.inbox
  end

  # O avatar entra na fila depois do commit: o job acha a caixa, e um rollback não deixa job órfão.
  def create(page_id, tokens)
    details = page_details(tokens[:page])
    inbox = ActiveRecord::Base.transaction do
      channel = account.facebook_pages.create!(page_id: page_id, user_access_token: tokens[:user], page_access_token: tokens[:page],
                                               **details.compact)
      account.inboxes.create!(name: details[:provider_name].presence || page_id, channel: channel)
    end
    Avatar::AvatarFromUrlJob.perform_later(inbox, "https://graph.facebook.com/#{page_id}/picture?type=large")
    inbox
  end

  # Nome e Instagram da Página. Falhar aqui não impede ligar: a caixa nasce com o id e o nome chega na próxima leitura.
  def page_details(page_token)
    Facebook::PageDetailsService.new(access_token: page_token).perform
  rescue StandardError => e
    Rails.logger.warn("[MetaAdsLoginUnico] page_details #{e.class}")
    {}
  end

  def account
    @account ||= Account.find(@connection.account_id)
  end
end

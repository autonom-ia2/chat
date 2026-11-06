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

  def initialize(connection)
    @connection = connection
  end

  # A caixa da Página já existe nesta conta? (o controller decide a permissão por isto)
  def existing(page_id)
    Channel::FacebookPage.find_by(account_id: @connection.account_id, page_id: page_id.to_s)
  end

  # Inbox da Página. Erros: `not_own_token` (modo parceiro), `page_not_granted` (a Meta não deu o token da Página).
  def call(page_id)
    raise Error, 'not_own_token' unless @connection.own_token?

    tokens = Crm::MetaAds::LoginUnico::TokenDaPagina.new(@connection).call(page_id.to_s)
    raise Error, 'page_not_granted' if tokens.nil?

    channel = existing(page_id)
    channel ? reauthorize(channel, tokens) : create(page_id.to_s, tokens)
  end

  private

  def reauthorize(channel, tokens)
    channel.update!(user_access_token: tokens[:user], page_access_token: tokens[:page])
    sync_details(channel, tokens[:page])
    channel.reauthorized!
    channel.inbox
  end

  def create(page_id, tokens)
    details = page_details(tokens[:page])
    ActiveRecord::Base.transaction do
      channel = account.facebook_pages.create!(page_id: page_id, user_access_token: tokens[:user], page_access_token: tokens[:page])
      channel.update!(details.compact) if details.present?
      inbox = account.inboxes.create!(name: details[:provider_name].presence || page_id, channel: channel)
      Avatar::AvatarFromUrlJob.perform_later(inbox, "https://graph.facebook.com/#{page_id}/picture?type=large")
      inbox
    end
  end

  def sync_details(channel, page_token)
    details = page_details(page_token)
    channel.update!(details.compact) if details.present?
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

# Instagram pelo login único (#2406, flag `instagram_login_unico`): liga o Instagram da Página escolhida com o mesmo
# "Entrar com o Facebook" dos Anúncios, sem o login do Instagram. A caixa é um Channel::Instagram comum, com
# `login: 'facebook'`, o token da Página (Crm::MetaAds::LoginUnico::TokenDaPagina) e o id da Página. Ela fala com
# graph.facebook.com.
#
# A caixa do Instagram que já existe nesta conta, do login do Instagram, troca de login: conversas e contatos ficam. A
# volta é entrar de novo pelo login do Instagram (Instagram::CallbacksController). Quem pode o quê fica com o
# controller: criar caixa é `inbox_manage`; trocar o token de uma caixa é `integration_manage`.
# Escopo, permissões e migração das caixas: docs/crm/instagram-login-unico-2406.md.
class Crm::MetaAds::LoginUnico::LigarInstagram
  # O mínimo para a caixa funcionar: ler o Instagram, o Direct e a inscrição da Página no webhook. Comentários
  # (instagram_manage_comments) e números (instagram_manage_insights) ficam sem ler se faltarem, como hoje.
  PERMISSIONS = %w[instagram_basic instagram_manage_messages pages_manage_metadata].freeze
  # O token da Página do login de empresa não expira; a coluna é obrigatória e não vale para esta caixa.
  NO_EXPIRY = 100.years

  Error = Crm::MetaAds::LoginUnico::LigarPagina::Error

  def initialize(connection)
    @connection = connection
  end

  # A caixa do Instagram desta Página que já existe nesta conta (o controller decide a permissão por isto).
  def existing(page_id)
    instagram = instagram_of(page_id)
    instagram && Channel::Instagram.find_by(account_id: @connection.account_id, instagram_id: instagram['id'])
  end

  # Inbox do Instagram. Erros: `not_own_token` (modo parceiro), `missing_permissions`, `no_instagram` (a Página não
  # tem Instagram ligado) e os de TokenDaPagina (`page_not_granted`, `reconnect`, `meta_unavailable`).
  def call(page_id)
    raise Error, 'not_own_token' unless @connection.own_token?

    ensure_permissions!
    instagram = instagram_of(page_id)
    raise Error, 'no_instagram' if instagram.nil?

    tokens = Crm::MetaAds::LoginUnico::TokenDaPagina.new(@connection).call(page_id.to_s)
    raise Error, tokens[:error] if tokens[:error]

    attributes = { login: 'facebook', page_id: page_id.to_s, access_token: tokens[:page], expires_at: NO_EXPIRY.from_now,
                   provider_name: instagram['username'] }
    channel = Channel::Instagram.find_by(account_id: @connection.account_id, instagram_id: instagram['id'])
    channel ? switch(channel, attributes) : create(instagram, attributes)
  end

  private

  def ensure_permissions!
    result = client.permissions
    raise Error, Crm::MetaAds::LoginUnico::TokenDaPagina.failure(result) unless result.ok

    granted = Array(result.data.to_h['data']).filter_map { |row| row['permission'] if row.is_a?(Hash) && row['status'] == 'granted' }
    raise Error, 'missing_permissions' unless (PERMISSIONS - granted).empty?
  end

  # { 'id', 'username' } do Instagram ligado à Página, entre as Páginas que este login concedeu (me/accounts).
  def instagram_of(page_id)
    @instagram ||= {}
    return @instagram[page_id.to_s] if @instagram.key?(page_id.to_s)

    @instagram[page_id.to_s] = read_instagram(page_id.to_s)
  end

  def read_instagram(page_id)
    result = client.login_pages
    raise Error, Crm::MetaAds::LoginUnico::TokenDaPagina.failure(result) unless result.ok

    page = Array(result.data.to_h['data']).find { |row| row.is_a?(Hash) && row['id'].to_s == page_id }
    raise Error, 'page_not_granted' if page.nil?

    usable_instagram(page['instagram_business_account'])
  end

  def usable_instagram(account)
    account if account.is_a?(Hash) && account['id'].present? && account['username'].present?
  end

  # Mesma caixa, outro login. A inscrição da Página sai depois do save; o alerta de reautorização, também.
  def switch(channel, attributes)
    channel.update!(attributes)
    channel.reauthorized!
    Instagram::PageSubscribeJob.perform_later(channel.id)
    channel.inbox
  end

  # Dois toques ao mesmo tempo: o segundo bate no índice único (instagram_id, account_id) e vira troca na caixa do
  # primeiro.
  def create(instagram, attributes)
    ActiveRecord::Base.transaction do
      channel = Channel::Instagram.create!(account_id: @connection.account_id, instagram_id: instagram['id'].to_s, **attributes)
      Account.find(@connection.account_id).inboxes.create!(name: instagram['username'], channel: channel)
    end
  rescue ActiveRecord::RecordNotUnique
    switch(Channel::Instagram.find_by!(account_id: @connection.account_id, instagram_id: instagram['id'].to_s), attributes)
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end
end

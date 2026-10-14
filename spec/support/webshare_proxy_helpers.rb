# Proxies falsos da Webshare e captura de log para os specs do #1516.
module WebshareProxyHelpers
  def webshare_proxy(id:, address:, **attrs)
    Webshare::Proxy.new(id: id.to_s, address: address, port: attrs.fetch(:port, 6000), username: "user-#{id}",
                        password: attrs.fetch(:password, "senha-#{id}"), valid: attrs.fetch(:valid, true),
                        country_code: attrs.fetch(:country, 'BR'), city_name: attrs.fetch(:city, 'Sao Paulo'))
  end

  def webshare_api_item(proxy_id, address, password: "senha-#{proxy_id}", city: 'Sao Paulo')
    { 'id' => proxy_id.to_s, 'proxy_address' => address, 'port' => 6000, 'username' => "user-#{proxy_id}",
      'password' => password, 'valid' => true, 'country_code' => 'BR', 'city_name' => city }
  end

  # Pool da Webshare com lista falsa (sem HTTP).
  def fake_pool(name, proxies)
    WhatsappProxy::Pool.new(name, client: instance_double(Webshare::Client, configured?: true, proxies: proxies))
  end

  # Sessão WAHA comum (canal API provider=waha) de uma conta.
  def waha_session!(name, account)
    create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => name })
  end

  # Sessão Híbrida (conexão auxiliar de uma caixa Cloud) de uma conta.
  def hybrid_session!(name, account)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false)
    WhatsappHybrid::Connection.create!(account: account, inbox: channel.inbox, session_name: name, status: 'connected')
  end

  def assign_proxy!(session, proxy, account:, pool: 'datacenter', digest: nil)
    WhatsappProxy::Assignment.create!(session_name: session, account_id: account.id, pool: pool, webshare_proxy_id: proxy.id,
                                      proxy_address: proxy.address, proxy_port: proxy.port, assigned_at: 1.day.ago,
                                      credential_digest: digest)
  end

  # O que o motor mostra numa rodada: cada sessão atribuída com o proxy da tabela (credencial da lista, salvo
  # `passwords[sessão]`), mais `extra`. Simula o motor já convergido com a tabela.
  def engine_view(statuses, passwords: {}, extra: [], without_proxy: [])
    WhatsappProxy::Assignment.all.map do |row|
      session = { 'name' => row.session_name, 'status' => statuses.fetch(row.session_name, 'WORKING') }
      next session if row.pending? || without_proxy.include?(row.session_name)

      password = passwords.fetch(row.session_name, "senha-#{row.webshare_proxy_id}")
      proxy = { 'server' => row.server, 'username' => "user-#{row.webshare_proxy_id}", 'password' => password }
      session.merge('config' => { 'proxy' => proxy })
    end + extra
  end

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end

RSpec.configure { |config| config.include WebshareProxyHelpers }

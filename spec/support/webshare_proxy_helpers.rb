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

  # O que o motor mostra numa rodada. `engine` guarda o proxy de cada sessão no motor: na primeira vez que a sessão
  # aparece, é o da tabela naquele momento; depois o motor NÃO acompanha a tabela (reatribuição no meio da rodada não o
  # muda) — só `apply_engine!` (o ApplyJob rodou) ou o teste mudam. `passwords[sessão]` troca a senha que o motor usa.
  def engine_view(statuses, engine:, passwords: {}, extra: [])
    WhatsappProxy::Assignment.all.map do |row|
      engine[row.session_name] = engine_snapshot(row, passwords) unless engine.key?(row.session_name)
      session = { 'name' => row.session_name, 'status' => statuses.fetch(row.session_name, 'WORKING') }
      proxy = engine[row.session_name]
      proxy ? session.merge('config' => { 'proxy' => proxy }) : session
    end + extra
  end

  def engine_snapshot(row, passwords = {})
    return if row.pending?

    { 'server' => row.server, 'username' => "user-#{row.webshare_proxy_id}",
      'password' => passwords.fetch(row.session_name, "senha-#{row.webshare_proxy_id}") }
  end

  # O ApplyJob aplicou a troca: o motor passa a usar o proxy da tabela e a tabela registra a conferência.
  def apply_engine!(engine, session_name)
    row = WhatsappProxy::Assignment.find_by!(session_name: session_name)
    engine[session_name] = engine_snapshot(row)
    row.applied!(Webshare::Proxy.digest_for(engine[session_name]['username'], engine[session_name]['password']))
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

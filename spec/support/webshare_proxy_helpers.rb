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

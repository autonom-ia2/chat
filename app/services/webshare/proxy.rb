# Um proxy do plano da Webshare (#1516). Carrega a credencial só em memória, para o pedido ao motor:
# inspect/to_s/as_json/to_json nunca mostram usuário nem senha.
class Webshare::Proxy
  attr_reader :id, :address, :port, :country_code, :city_name

  def self.from_api(item)
    new(
      id: item['id'].to_s, address: item['proxy_address'].to_s, port: item['port'].to_i,
      username: item['username'].to_s, password: item['password'].to_s,
      valid: item['valid'] == true, country_code: item['country_code'].to_s, city_name: item['city_name'].to_s
    )
  end

  def initialize(id:, address:, port:, username:, password:, valid:, country_code:, city_name:) # rubocop:disable Metrics/ParameterLists
    @id = id
    @address = address
    @port = port
    @username = username
    @password = password
    @valid = valid
    @country_code = country_code
    @city_name = city_name
  end

  def valid?
    @valid && address.present? && port.positive?
  end

  def server
    "#{address}:#{port}"
  end

  # Bloco `config.proxy` da sessão no motor. Único lugar que expõe a credencial.
  def to_session_config
    { server: server, username: @username, password: @password }
  end

  # HMAC de usuário:senha: nota que a Webshare trocou a credencial do mesmo IP sem guardar a credencial.
  def self.digest_for(username, password)
    key = Rails.application.key_generator.generate_key('whatsapp-proxy-credential-digest', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, "#{username}:#{password}")
  end

  def credential_digest
    self.class.digest_for(@username, @password)
  end

  def as_json(*)
    { 'id' => id, 'server' => server, 'valid' => @valid, 'country_code' => country_code, 'city_name' => city_name }
  end

  def to_json(*)
    as_json.to_json(*)
  end

  def inspect
    "#<#{self.class.name} id=#{id} server=#{server} valid=#{@valid} country=#{country_code} city=#{city_name}>"
  end
  alias to_s inspect
end

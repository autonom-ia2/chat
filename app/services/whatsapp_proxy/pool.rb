# Um plano da Webshare visto por esta stack (#1516): isp (Static Residential, Híbrido) ou datacenter (Proxy Server, WAHA).
# Cada stack usa só a sua fatia do plano: WEBSHARE_ISP_PROXY_ADDRESSES / WEBSHARE_DATACENTER_PROXY_ADDRESSES (IPs
# separados por vírgula; vazio = plano inteiro). Candidato a número novo: válido, do Brasil e dentro da fatia — nunca
# outro país, nunca fora da fatia. IP da fatia que sumiu da lista (a Webshare trocou) vira aviso alto no log.
class WhatsappProxy::Pool
  SLICE_ENVS = { 'isp' => 'WEBSHARE_ISP_PROXY_ADDRESSES', 'datacenter' => 'WEBSHARE_DATACENTER_PROXY_ADDRESSES' }.freeze

  attr_reader :name

  def initialize(name, client: Webshare::Client.new(pool: name))
    @name = name.to_s
    @client = client
  end

  def configured?
    @client.configured?
  end

  # Uma busca por instância; avisa quando a fatia aponta para IP que não está mais no plano.
  def proxies
    @proxies ||= @client.proxies.tap { |list| warn_missing_slice(list) }
  end

  def candidates
    proxies.select { |proxy| proxy.valid? && proxy.country_code.casecmp?('BR') && in_slice?(proxy) }
  end

  def slice
    @slice ||= ENV.fetch(SLICE_ENVS.fetch(@name), '').split(',').map(&:strip).compact_blank
  end

  private

  def in_slice?(proxy)
    slice.empty? || slice.include?(proxy.address)
  end

  def warn_missing_slice(list)
    missing = slice - list.map(&:address)
    return if missing.empty?

    Rails.logger.error("[whatsapp_proxy] #{missing.size} IP(s) da fatia #{SLICE_ENVS.fetch(@name)} sumiram do plano " \
                       "#{@name} da Webshare (#{missing.join(', ')}): atualize a fatia desta stack.")
  end
end

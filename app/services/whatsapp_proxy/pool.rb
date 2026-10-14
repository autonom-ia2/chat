# Um plano da Webshare visto por esta stack (#1516): isp (Static Residential, Híbrido) ou datacenter (Proxy Server, WAHA).
# Cada stack usa só a sua fatia do plano: WEBSHARE_ISP_PROXY_ADDRESSES / WEBSHARE_DATACENTER_PROXY_ADDRESSES (IPs
# separados por vírgula). Fatia vazia = nenhum candidato (log de erro): sem ela as duas stacks disputariam o mesmo IP.
# Candidato: válido, do Brasil e dentro da fatia — nunca outro país, nunca fora da fatia. IP da fatia que sumiu da
# lista (a Webshare trocou) vira aviso alto no log.
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
    if slice.empty?
      Rails.logger.error("[whatsapp_proxy] #{SLICE_ENVS.fetch(@name)} vazia: plano #{@name} sem IP para esta stack.")
      return []
    end

    proxies.select { |proxy| proxy.valid? && proxy.country_code.casecmp?('BR') && slice.include?(proxy.address) }
  end

  def slice
    @slice ||= ENV.fetch(SLICE_ENVS.fetch(@name), '').split(',').map(&:strip).compact_blank
  end

  private

  def warn_missing_slice(list)
    missing = slice - list.map(&:address)
    return if missing.empty?

    Rails.logger.error("[whatsapp_proxy] #{missing.size} IP(s) da fatia #{SLICE_ENVS.fetch(@name)} sumiram do plano " \
                       "#{@name} da Webshare (#{missing.join(', ')}): atualize a fatia desta stack.")
  end
end

# Um plano da Webshare visto por esta stack (#1516): isp (Static Residential, Híbrido) ou datacenter (Proxy Server, WAHA).
# Cada stack usa só a sua fatia do plano: WEBSHARE_ISP_PROXY_ADDRESSES / WEBSHARE_DATACENTER_PROXY_ADDRESSES (IPs
# separados por vírgula). Fatia vazia = nenhum candidato (log de erro): sem ela as duas stacks disputariam o mesmo IP.
# Candidato: válido, do Brasil e dentro da fatia — nunca outro país, nunca fora da fatia, nunca reservado para outra
# integração (WEBSHARE_RESERVED_PROXY_ADDRESSES, ex.: o IP do Instagram), nem em quarentena. IP da fatia que sumiu da
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
      WhatsappProxy::Alert.notify!('fatia_vazia', "#{SLICE_ENVS.fetch(@name)} vazia: plano #{@name} sem IP para esta stack",
                                   level: :error, pool: @name)
      return []
    end

    @candidates ||= proxies.select { |proxy| offerable?(proxy) }
  end

  def offerable?(proxy)
    return false unless proxy.valid? && proxy.country_code.casecmp?('BR') && slice.include?(proxy.address)

    quarantined.exclude?(proxy.address) && reserved.exclude?(proxy.address)
  end

  # IPs da Webshare usados por outra integração (não por número de WhatsApp): nunca oferecidos, mesmo na fatia.
  def reserved
    @reserved ||= ENV.fetch('WEBSHARE_RESERVED_PROXY_ADDRESSES', '').split(',').map(&:strip).compact_blank
  end

  # IP em quarentena (derrubou um número) não serve para ninguém por 24 h.
  def quarantined
    @quarantined ||= WhatsappProxy::Quarantine.addresses
  end

  # A próxima consulta relê a quarentena (a reconciliação põe IP em quarentena no meio da rodada).
  def forget_quarantine!
    @quarantined = nil
    @candidates = nil
  end

  def slice
    @slice ||= ENV.fetch(SLICE_ENVS.fetch(@name), '').split(',').map(&:strip).compact_blank
  end

  private

  def warn_missing_slice(list)
    missing = slice - list.map(&:address)
    return if missing.empty?

    WhatsappProxy::Alert.notify!('ip_da_fatia_sumiu',
                                 "#{missing.size} IP(s) da fatia #{SLICE_ENVS.fetch(@name)} sumiram do plano #{@name} " \
                                 "da Webshare (#{missing.join(', ')}): atualize a fatia desta stack",
                                 level: :error, pool: @name, count: missing.size)
  end
end

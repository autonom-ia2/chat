# O proxy de saída de um pedido do SafeFetch (opção `proxy:`, #2942). O pedido sai por ele: o Net::HTTP abre o túnel
# (CONNECT) para o IP que o ssrf_filter já conferiu, e o TLS vai até o site, como sem proxy. A credencial fica só em
# memória: inspect e to_s nunca a mostram.
class SafeFetch::Proxy
  attr_reader :address, :port

  # Pelo https o proxy só abre o túnel (CONNECT) para o IP que o ssrf_filter conferiu. Pelo http ele receberia o NOME do
  # site e resolveria o DNS por conta própria, e o pedido iria a um endereço que ninguém conferiu (SSRF). Então o proxy
  # exige https no endereço e em todo salto. -> o proxy (ou nil, sem proxy).
  def self.checked(proxy, schemes:, uri:)
    return proxy if proxy.nil? || (schemes == %w[https] && uri.scheme == 'https')

    raise ArgumentError, 'proxy: requires schemes: %w[https] and an https url'
  end

  def initialize(address:, port:, user: nil, password: nil)
    @address = address.to_s
    @port = port.to_i
    @user = user
    @password = password
  end

  # As opções do `Net::HTTP.start` (ele chama o `proxy_*=` de cada uma). `proxy_from_env: false`: vale este proxy, nunca o
  # do ambiente (`http_proxy`).
  def http_options
    { proxy_from_env: false, proxy_address: address, proxy_port: port, proxy_user: @user, proxy_pass: @password }
  end

  def inspect
    "#<#{self.class.name} #{address}:#{port}>"
  end
  alias to_s inspect
end

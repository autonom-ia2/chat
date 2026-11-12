# A saída de UM `ClienteHttp` das consultas grátis (#2942): o proxy da conta, lido uma vez (`proxy`), largado quando cai,
# com a credencial relida uma vez quando o túnel é recusado, e a queda contada só depois de a chamada já ter repetido
# pelo IP do servidor (`contar_queda`), para a troca do IP não atrasar a resposta. Até 3 tentativas por chamada: o
# proxy, o proxy com a credencial relida (só no 1º túnel recusado) e o servidor (`Repetir`, que o cliente refaz).
class Autonomia::FerramentasProntas::Saida::DoCliente
  # A chamada repete: pelo mesmo IP com a credencial relida, ou pelo IP do servidor. Nunca sai do `ClienteHttp`.
  class Repetir < StandardError; end

  Falha = Autonomia::FerramentasProntas::Provedor::Falha
  ProxyMorto = Autonomia::FerramentasProntas::Saida::ProxyMorto

  # `ate`: o instante (relógio monotônico) até o qual a ida à Webshare pode durar.
  def initialize(conta:, ate:)
    @conta = conta
    @ate = ate
  end

  # -> o `SafeFetch::Proxy` do IP próprio, ou nil (o IP do servidor).
  def proxy
    return @proxy if defined?(@proxy)

    @proxy = Autonomia::FerramentasProntas::Saida.para(@conta, ate: @ate)
  end

  def deu_certo(proxy)
    ProxyMorto.vivo!(proxy.address) if proxy
  end

  # O erro do `SafeFetch` foi a ligação com o proxy: larga e repete pelo servidor. Senão, segue (é do site).
  def falhou!(erro, proxy)
    largar!(proxy) if proxy && ProxyMorto.ligacao_caiu?(erro)
  end

  # Só o túnel do proxy levanta `Net::HTTPExceptions` (o `CONNECT` respondido com erro). 502 e 504: o site está fora. A
  # 1ª recusa relê a lista da Webshare (a credencial pode ter mudado) e tenta de novo; a recusa com a lista nova é o
  # proxy que caiu.
  def tunel_recusado!(erro, proxy)
    raise Falha, 'falha_de_rede' if proxy.nil?
    raise Falha, 'erro_da_fonte' if ProxyMorto.site_fora?(erro)
    return largar!(proxy) if @credencial_relida

    @credencial_relida = true
    Autonomia::FerramentasProntas::Saida::ListaDaWebshare.esquecer!
    remove_instance_variable(:@proxy)
    raise Repetir
  end

  # Depois da repetição pelo servidor: a queda conta (e pode trocar o IP, se der tempo).
  def contar_queda
    return if @caiu.nil?

    ip = @caiu
    @caiu = nil
    ProxyMorto.caiu!(ip, conta: @conta, ate: @ate)
  end

  private

  # O resto do cliente sai pelo servidor; a queda fica para `contar_queda`.
  def largar!(proxy)
    @proxy = nil
    @caiu = proxy.address
    raise Repetir
  end
end

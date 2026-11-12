# #2942: o IP próprio das consultas grátis, nos specs. A Webshare é sempre dublada (nenhuma chamada real) e os IPs são de
# documentação (RFC 5737), nunca IPs reais do plano.
module ProntasSaidaHelper
  PREFIXO_DA_SAIDA = 'autonomia:prontas:saida'.freeze

  def proxy_da_webshare(id, endereco, valido: true, pais: 'BR')
    Webshare::Proxy.from_api(webshare_api_item(id, endereco).merge('valid' => valido, 'country_code' => pais))
  end

  # A lista do plano datacenter, sem HTTP. Devolve o dublê do cliente, para contar as buscas.
  def webshare_datacenter(lista)
    Autonomia::FerramentasProntas::Saida::ListaDaWebshare.esquecer!
    instance_double(Webshare::Client, proxies: lista).tap do |cliente|
      allow(Webshare::Client).to receive(:new).with(hash_including(pool: :datacenter)).and_return(cliente)
    end
  end

  def webshare_datacenter_fora
    Autonomia::FerramentasProntas::Saida::ListaDaWebshare.esquecer!
    instance_double(Webshare::Client).tap do |cliente|
      allow(cliente).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=503')
      allow(Webshare::Client).to receive(:new).with(hash_including(pool: :datacenter)).and_return(cliente)
    end
  end

  # O que a saída guarda no Redis (alertas, recusas, contador da queda) passaria de um exemplo para o outro.
  def zerar_saida_das_prontas
    chaves = []
    Redis::Alfred.scan_each(match: "#{PREFIXO_DA_SAIDA}:*") { |chave| chaves << chave }
    chaves.each { |chave| Redis::Alfred.delete(chave) }
    Autonomia::FerramentasProntas::Saida::ListaDaWebshare.esquecer!
  end

  def ligar_ip_proprio(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::Saida::FLAG)
  end
end

RSpec.configure do |config|
  config.include ProntasSaidaHelper
end

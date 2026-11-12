# A FATIA DE IPs DAS CONSULTAS GRÁTIS nesta stack (#2942). Duas listas de ambiente, IPs separados por vírgula:
#   - WEBSHARE_LOOKUP_PROXY_ADDRESSES: os IPs do plano datacenter que esta stack usa para as consultas (cada stack tem a
#     sua, sem IP repetido entre elas);
#   - WEBSHARE_RESERVED_PROXY_ADDRESSES: os que o WhatsApp nunca oferece (`WhatsappProxy::Pool#offerable?`).
# Um IP só serve às consultas se estiver nas DUAS. As listas são do ambiente: o código confere e alerta quando um IP da
# fatia não está na reservada (o WhatsApp poderia pegá-lo), e o deixa de fora; ele não escreve ambiente.
# Também fica de fora o IP que algum número de WhatsApp ainda usa (`WhatsappProxy::Assignment`, só leitura).
module Autonomia::FerramentasProntas::Saida::Fatia
  FATIA = 'WEBSHARE_LOOKUP_PROXY_ADDRESSES'.freeze
  RESERVADA = 'WEBSHARE_RESERVED_PROXY_ADDRESSES'.freeze
  PAIS = 'BR'.freeze

  module_function

  def enderecos
    lista(FATIA)
  end

  def reservados
    lista(RESERVADA)
  end

  def configurada?
    enderecos.any?
  end

  # Os IPs da fatia que o WhatsApp ainda pode oferecer. Alerta (uma vez por hora) e devolve a lista.
  def fora_da_reservada
    (enderecos - reservados).tap do |fora|
      next if fora.empty?

      alertar('fora_da_reservada', "#{fora.size} IP(s) de #{FATIA} fora de #{RESERVADA} (#{mascarar(fora)}): ficam de " \
                                   'fora das consultas até entrarem na reservada')
    end
  end

  # O proxy da Webshare que ainda serve a este registro (mesmo IP e porta, válido, na fatia, fora de quarentena e sem
  # número de WhatsApp), ou nil. Dividido com um número, a conta troca de IP: o WhatsApp é dono dele.
  def vivo(registro, lista)
    return if registro.nil?

    proxy = lista.find { |item| registro.mesmo?(item) }
    return unless proxy && serve?(proxy, uteis)
    return if Autonomia::FerramentasProntas::ProxyEmQuarentena.ativa?(proxy.address)

    proxy if no_whatsapp([proxy.address]).empty?
  end

  # Os que servem e estão livres: fora de quarentena, sem número de WhatsApp e fora de `usados` (os das outras contas).
  def livres(lista, usados:)
    na_fatia = uteis
    candidatos = lista.select { |proxy| serve?(proxy, na_fatia) }
    fora = usados + Autonomia::FerramentasProntas::ProxyEmQuarentena.enderecos + no_whatsapp(candidatos.map(&:address))
    candidatos.reject { |proxy| fora.include?(proxy.address) }
  end

  # `uteis`: calculado uma vez por chamada por quem pergunta (a conferência da reservada alerta, e não por proxy).
  def serve?(proxy, uteis)
    proxy.valid? && proxy.country_code.casecmp?(PAIS) && uteis.include?(proxy.address)
  end

  # Na fatia e na reservada.
  def uteis
    enderecos - fora_da_reservada
  end

  # IP da fatia que um número de WhatsApp usa (atribuído antes de entrar na reservada): nunca vai para uma conta.
  def no_whatsapp(enderecos)
    return [] if enderecos.empty?

    WhatsappProxy::Assignment.where(proxy_address: enderecos).distinct.pluck(:proxy_address).tap do |usados|
      next if usados.empty?

      alertar('ip_no_whatsapp', "#{usados.size} IP(s) da fatia das consultas em uso por número de WhatsApp (#{mascarar(usados)})")
    end
  end

  def lista(nome)
    ENV.fetch(nome, '').split(',').map(&:strip).compact_blank.uniq
  end

  # "10.20.30.40" -> "10.20.x.x": dá para achar o IP no painel da Webshare sem expô-lo inteiro no alerta.
  def mascarar(enderecos)
    enderecos.map { |endereco| "#{endereco.split('.').first(2).join('.')}.x.x" }.join(', ')
  end

  def alertar(codigo, mensagem)
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(codigo, mensagem, nivel: :error)
  end
end

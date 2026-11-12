# As recusas (429 e 403) das fontes grátis, por IP de saída (#2942). A queda do proxy é do `Saida::ProxyMorto`. Os IPs da Webshare são
# compartilhados com outros clientes dela: o limite que cada conta tem de fato só se conhece medindo.
#   - telemetria: toda recusa vai ao log estruturado (`[autonomia][pronta][saida] recusa`, com host, status, saída e conta;
#     nunca credencial) e ao contador do dia no Redis (`CHAVE:<dia>`, campo `saida|host|status`, 7 dias), pelo IP do
#     servidor também (`saida=servidor`), para comparar. O proxy que caiu entra como `ip|proxy|morto` (`ProxyMorto`);
#   - quarentena: SEGUIDAS recusas do mesmo host no mesmo IP próprio, sem pausa de JANELA entre elas, põem o IP de molho
#     (`ProxyEmQuarentena`, 6 h, até o teto diário dela), e a conta ganha outro IP na consulta seguinte.
#   - fora da quarentena: o host com a chave configurada (`TetoDoProvedor.por_chave?`), que recusa pela chave e não pelo
#     IP. Hoje nenhuma chave está configurada (decisão do Rodrigo, 12/11): a guarda vale se alguém a puser.
#     Nenhuma fonte grátis do catálogo responde 403 por regra de negócio (conferido em 12/11: os adaptadores não tratam
#     403; o `ClienteHttp` o traduz em `pedido_recusado`), então o 403 dos outros hosts conta.
# A telemetria é cortesia sobre a falha: sem Redis ou sem banco, fica o aviso no log e a consulta segue com o motivo dela.
module Autonomia::FerramentasProntas::Saida::Recusas
  STATUS = [403, 429].freeze
  CHAVE = 'autonomia:prontas:saida:recusas'.freeze
  JANELA = 10.minutes.to_i
  SEGUIDAS = 3
  GUARDA = 7.days.to_i
  SERVIDOR = 'servidor'.freeze
  ERROS = [*Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS, ActiveRecord::ActiveRecordError].freeze

  module_function

  def recusa?(status)
    STATUS.include?(status.to_i)
  end

  # `saida`: o `SafeFetch::Proxy` por onde o pedido saiu, ou nil (IP do servidor).
  def registrar!(host:, status:, saida:, conta:)
    ip = saida&.address
    Rails.logger.warn("[autonomia][pronta][saida] recusa host=#{host} status=#{status} saida=#{ip || SERVIDOR} conta=#{conta}")
    contar_no_dia(ip || SERVIDOR, host, status)
    quarentena!(ip, "#{host} #{status}", host) if molho?(ip, host)
  rescue *ERROS => e
    Rails.logger.warn("[autonomia][pronta][saida] recusa não registrada #{e.class}")
  end

  # O IP próprio passou de SEGUIDAS recusas deste host? O host da cota da chave nunca conta.
  def molho?(ip, host)
    return false if ip.nil? || Autonomia::FerramentasProntas::TetoDoProvedor.por_chave?(host)

    seguidas(ip, host) >= SEGUIDAS
  end

  def contar_no_dia(saida, host, status)
    dia = "#{CHAVE}:#{Time.current.utc.to_date.iso8601}"
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.hincrby(dia, [saida, host, status].join('|'), 1)
        transacao.expire(dia, GUARDA)
      end
    end
  end

  # -> quantas vezes seguidas (sem pausa de JANELA) `host` falhou neste IP.
  def seguidas(ip, host)
    chave = chave_das_seguidas(ip, host)
    respostas = Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.incr(chave)
        transacao.expire(chave, JANELA)
      end
    end
    respostas.first.to_i
  end

  def chave_das_seguidas(ip, host)
    "#{CHAVE}:seguidas:#{ip}:#{host}"
  end

  def quarentena!(ip, motivo, host)
    quarentena = Autonomia::FerramentasProntas::ProxyEmQuarentena
    return avisar_teto unless quarentena.cabe?

    quarentena.por!(ip, motivo)
    Redis::Alfred.delete(chave_das_seguidas(ip, host))
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(
      'ip_em_quarentena', "IP #{Autonomia::FerramentasProntas::Saida::Fatia.mascarar([ip])} de molho por " \
                          "#{quarentena::DURACAO.inspect} (#{SEGUIDAS}x #{motivo})", assunto: ip
    )
  end

  def avisar_teto
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(
      'teto_de_quarentena', "#{Autonomia::FerramentasProntas::ProxyEmQuarentena::TETO_DIARIO} IPs já foram de molho em 24 h: " \
                            'o problema não é IP a IP (a fonte bloqueou a Webshare, ou o teto está alto)', nivel: :error
    )
  end
end

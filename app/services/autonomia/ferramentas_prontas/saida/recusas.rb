# As recusas (429 e 403) das fontes grátis, por IP de saída e host (#2942). Os IPs da Webshare são compartilhados com
# outros clientes dela: o limite que cada conta tem de fato só se conhece medindo.
#   - telemetria: toda recusa vai ao log estruturado (`[autonomia][pronta][saida] recusa`, com host, status, saída e conta;
#     nunca credencial) e ao contador do dia no Redis (`CHAVE:<dia>`, campo `saida|host|status`, 7 dias), pelo IP do
#     servidor também (`saida=servidor`), para comparar;
#   - quarentena: SEGUIDAS recusas do mesmo host no mesmo IP próprio, sem pausa de JANELA entre elas, põem o IP de molho
#     (`ProxyEmQuarentena`, até o teto diário dela), e a conta ganha outro IP na consulta seguinte.
# A telemetria é cortesia sobre a falha: sem Redis ou sem banco, fica o aviso no log e a consulta segue com o motivo dela.
module Autonomia::FerramentasProntas::Saida::Recusas
  STATUS = [403, 429].freeze
  CHAVE = 'autonomia:prontas:saida:recusas'.freeze
  JANELA = 10.minutes.to_i
  SEGUIDAS = 3
  GUARDA = 7.days.to_i
  SERVIDOR = 'servidor'.freeze

  module_function

  def recusa?(status)
    STATUS.include?(status.to_i)
  end

  # `saida`: o `SafeFetch::Proxy` por onde o pedido saiu, ou nil (IP do servidor).
  def registrar!(host:, status:, saida:, conta:)
    ip = saida&.address
    Rails.logger.warn("[autonomia][pronta][saida] recusa host=#{host} status=#{status} saida=#{ip || SERVIDOR} conta=#{conta}")
    seguidas = contar(ip, host, status)
    quarentena!(ip, host, status) if ip && seguidas >= SEGUIDAS
  rescue *Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS, ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][pronta][saida] recusa não registrada #{e.class}")
  end

  # -> quantas recusas deste host neste IP na janela atual (0 pelo IP do servidor, que não vai para quarentena).
  def contar(ip, host, status)
    dia = "#{CHAVE}:#{Time.current.utc.to_date.iso8601}"
    seguidas = "#{CHAVE}:seguidas:#{ip}:#{host}"
    respostas = Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.hincrby(dia, [ip || SERVIDOR, host, status].join('|'), 1)
        transacao.expire(dia, GUARDA)
        next if ip.nil?

        transacao.incr(seguidas)
        transacao.expire(seguidas, JANELA)
      end
    end
    ip ? respostas[2].to_i : 0
  end

  def quarentena!(ip, host, status)
    quarentena = Autonomia::FerramentasProntas::ProxyEmQuarentena
    return avisar_teto unless quarentena.cabe?

    quarentena.por!(ip, "#{host} #{status}")
    Redis::Alfred.delete("#{CHAVE}:seguidas:#{ip}:#{host}")
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(
      'ip_em_quarentena', "IP #{Autonomia::FerramentasProntas::Saida::Fatia.mascarar([ip])} de molho por " \
                          "#{quarentena::DURACAO.inspect} (#{SEGUIDAS} recusas #{status} de #{host})", assunto: ip
    )
  end

  def avisar_teto
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(
      'teto_de_quarentena', "#{Autonomia::FerramentasProntas::ProxyEmQuarentena::TETO_DIARIO} IPs já foram de molho em 24 h: " \
                            'o problema não é IP a IP (a fonte bloqueou a Webshare, ou o teto está alto)', nivel: :error
    )
  end
end

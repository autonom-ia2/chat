# O PROXY QUE CAIU nas consultas grátis (#2942). Segue os padrões do WhatsApp Híbrido (#1516), sem usar as classes dele:
#   - contagem: SEGUIDAS quedas (`proxy_morto`) no mesmo IP dentro de JANELA, zeradas a cada sucesso por ele (`vivo!`);
#   - falha geral: quando mais de FALHA_GERAL dos IPs com conta caem na mesma janela (ao menos MINIMO_GERAL), o problema
#     é a Webshare, não o IP. Ninguém vai para a quarentena, e todas as contas saem pelo servidor por JANELA, com o alerta
#     `webshare_fora`;
#   - troca: no máximo uma por conta a cada UMA_TROCA, com o IP de molho por 24 h (a quarentena de 429/403 é de 6 h). A
#     quarentena é provisória: entra na mesma transação da escolha do IP novo e, sem IP livre, as duas se desfazem. O
#     IP anterior fica só no log; o novo se confirma no primeiro sucesso. Se o IP novo também cair antes de vencer a
#     troca, a conta fica pelo servidor até lá (`no_servidor`), com um alerta por dia;
#   - Redis fora: não conta nem troca. A consulta já saiu pelo servidor (`ClienteHttp`), e fica o aviso.
module Autonomia::FerramentasProntas::Saida::ProxyMorto
  CHAVE = 'autonomia:prontas:saida:proxy'.freeze
  MOTIVO = 'proxy_morto'.freeze
  SEGUIDAS = 3
  JANELA = 20.minutes.to_i
  FALHA_GERAL = 0.3
  MINIMO_GERAL = 2
  UMA_TROCA = 24.hours.to_i
  ERROS_DO_REDIS = Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS
  # Com proxy, a causa destes erros é a ligação com o PROXY (a com o site vai dentro do túnel). O prazo de leitura não
  # entra: com o túnel aberto, é o site que demora.
  CAUSAS = [Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT].freeze
  # O túnel respondido com estes: o proxy não chegou ao site (o site está fora).
  SITE_FORA = [502, 504].freeze

  module_function

  # O proxy não abriu o túnel; a chamada já repetiu pelo IP do servidor.
  def caiu!(ip, conta:)
    Rails.logger.warn("[autonomia][pronta][saida] proxy caiu saida=#{ip} conta=#{conta}: repete pelo IP do servidor")
    Autonomia::FerramentasProntas::Saida::Recusas.contar_no_dia(ip, 'proxy', 'morto')
    Autonomia::FerramentasProntas::Saida.contar_queda(MOTIVO)
    return webshare_fora! if falha_geral?(ip)

    trocar!(ip) if seguidas(ip) >= SEGUIDAS
  rescue *ERROS_DO_REDIS => e
    Rails.logger.warn("[autonomia][pronta][saida] queda do proxy sem Redis (não conta nem troca) #{e.class}")
  rescue ActiveRecord::ActiveRecordError, Webshare::Client::Error, *Autonomia::FerramentasProntas::Saida::ERROS_DE_REDE => e
    Rails.logger.warn("[autonomia][pronta][saida] troca do proxy que caiu não feita #{e.class}")
  end

  # O erro do `SafeFetch` foi a ligação com o proxy? (O prazo total, que é do corpo, não entra.)
  def ligacao_caiu?(erro)
    erro.instance_of?(SafeFetch::FetchError) && CAUSAS.any? { |classe| erro.cause.is_a?(classe) }
  end

  # O túnel recusado (`Net::HTTPExceptions`) foi o site fora?
  def site_fora?(erro)
    SITE_FORA.include?(erro.response&.code.to_i)
  end

  # O pedido pelo IP deu certo: a contagem de quedas dele zera.
  def vivo!(ip)
    Redis::Alfred.delete(chave_das_seguidas(ip))
  rescue *ERROS_DO_REDIS => e
    Rails.logger.debug { "[autonomia][pronta][saida] contagem de quedas sem Redis #{e.class}" }
  end

  # -> o motivo para a conta sair pelo servidor agora (`webshare_fora`, `ip_caiu_de_novo`), ou nil. O Redis fora levanta
  # (a `Saida` manda pelo servidor).
  def bloqueio(conta_id)
    fora, no_servidor = Redis::Alfred.with { |conn| conn.mget(chave_fora, chave_no_servidor(conta_id)) }
    return 'webshare_fora' if fora

    'ip_caiu_de_novo' if no_servidor
  end

  def seguidas(ip)
    chave = chave_das_seguidas(ip)
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.incr(chave)
        transacao.expire(chave, JANELA)
      end
    end.first.to_i
  end

  # Este IP entra no conjunto dos que caíram nesta janela. -> dos IPs que hoje têm conta, os que caíram passam do limite?
  # (O IP que já foi trocado não conta: senão a conta cujo IP novo também cai pareceria uma falha geral.)
  def falha_geral?(ip)
    chave = "#{CHAVE}:caidos:#{Time.now.to_i / JANELA}"
    membros = Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.sadd(chave, ip)
        transacao.smembers(chave)
        transacao.expire(chave, JANELA)
      end
    end[1]
    caidos = Autonomia::FerramentasProntas::ProxyDaConta.where(proxy_address: membros).count
    caidos >= MINIMO_GERAL && caidos > Autonomia::FerramentasProntas::ProxyDaConta.count * FALHA_GERAL
  end

  def webshare_fora!
    Redis::Alfred.set(chave_fora, '1', ex: JANELA)
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!(
      'webshare_fora', "IPs demais caíram na mesma janela: todas as contas pelo IP do servidor por #{JANELA / 60} min, " \
                       'ninguém de molho', nivel: :error
    )
  end

  def trocar!(ip)
    registro = Autonomia::FerramentasProntas::ProxyDaConta.find_by(proxy_address: ip)
    return if registro.nil?
    return ficar_no_servidor!(registro.account_id) if Redis::Alfred.exists?(chave_da_troca(registro.account_id))
    return Autonomia::FerramentasProntas::Saida::Recusas.avisar_teto unless Autonomia::FerramentasProntas::ProxyEmQuarentena.cabe?

    novo = trocar_com_quarentena!(registro.account_id, ip)
    depois_da_troca(registro.account_id, ip, novo)
  rescue Autonomia::FerramentasProntas::Saida::SemIp
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!('sem_ip_para_trocar', "o IP #{mascarar(ip)} caiu e não há IP livre: " \
                                                                               'segue na conta, sem quarentena', assunto: ip)
  end

  # A quarentena e a escolha numa transação só: sem IP livre (`SemIp`), as duas se desfazem.
  def trocar_com_quarentena!(conta_id, ip)
    lista = Autonomia::FerramentasProntas::Saida::ListaDaWebshare.proxies
    quarentena = Autonomia::FerramentasProntas::ProxyEmQuarentena
    Autonomia::FerramentasProntas::ProxyDaConta.exclusivamente do
      quarentena.por!(ip, MOTIVO, duracao: quarentena::DURACAO_PROXY_MORTO)
      Autonomia::FerramentasProntas::Saida.trocar!(conta_id, lista)
    end
  end

  def depois_da_troca(conta_id, ip, novo)
    Redis::Alfred.set(chave_da_troca(conta_id), '1', ex: UMA_TROCA)
    Redis::Alfred.delete(chave_das_seguidas(ip))
    Rails.logger.warn("[autonomia][pronta][saida] conta=#{conta_id} trocou de IP (proxy_morto) anterior=#{ip} novo=#{novo.address}")
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!('ip_em_quarentena', "IP #{mascarar(ip)} de molho por 24 h (#{SEGUIDAS}x " \
                                                                             "#{MOTIVO}); a conta ganhou outro", assunto: ip)
  end

  # O IP novo também caiu antes de vencer a troca: a conta fica pelo servidor até lá.
  def ficar_no_servidor!(conta_id)
    restante = Redis::Alfred.ttl(chave_da_troca(conta_id)).to_i
    Redis::Alfred.set(chave_no_servidor(conta_id), '1', ex: restante.positive? ? restante : UMA_TROCA)
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!('conta_no_servidor', "conta #{conta_id}: o IP novo também caiu; consultas " \
                                                                              'pelo IP do servidor até vencer a troca do dia',
                                                         assunto: conta_id, janela: 1.day)
  end

  def mascarar(ip)
    Autonomia::FerramentasProntas::Saida::Fatia.mascarar([ip])
  end

  def chave_das_seguidas(ip) = "#{CHAVE}:seguidas:#{ip}"
  def chave_fora = "#{CHAVE}:webshare_fora"
  def chave_da_troca(conta_id) = "#{CHAVE}:troca:#{conta_id}"
  def chave_no_servidor(conta_id) = "#{CHAVE}:no_servidor:#{conta_id}"
end

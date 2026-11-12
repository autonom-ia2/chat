# A SAÍDA DAS CONSULTAS GRÁTIS DE UMA CONTA (#2942, parte do #2858). As fontes públicas (ViaCEP, BrasilAPI, parallelum,
# AwesomeAPI...) limitam por IP; pelo IP do servidor, o limite delas é dividido por todas as contas. Com a flag, cada
# conta sai por um IP próprio da Webshare (plano datacenter), só nessas consultas. O Premium (BigDataCorp) tem cliente
# próprio e não passa por aqui; o WhatsApp (#1516) também não.
#
#   - flag desligada, ou chamada sem conta: o IP do servidor, como sempre;
#   - a conta ganha o IP na 1ª consulta que sai para a rede (o cache não chega ao `ClienteHttp`), sob a trava própria
#     (`ProxyDaConta.exclusivamente`), entre os da fatia que servem (`Saida::Fatia`: na fatia desta stack E na lista
#     reservada, vivos na Webshare, fora de quarentena, sem número de WhatsApp) e que nenhuma outra conta tem;
#   - o IP da conta que sumiu da Webshare, saiu da fatia ou foi para a quarentena é trocado na consulta seguinte (e pela
#     `ReconciliarSaidasJob`, a cada 10 minutos);
#   - a credencial vem da Webshare na hora (`Saida::ListaDaWebshare`, só na memória do processo, poucos minutos);
#   - sem IP próprio (Webshare fora, fatia vazia, nenhum IP livre): a consulta sai pelo IP do servidor, como antes da
#     flag, e o cliente recebe a resposta; fica o aviso no log, o alerta e o contador do dia (`CONTADOR`). Decisão do
#     Rodrigo, 12/11/2026.
module Autonomia::FerramentasProntas::Saida
  FLAG = 'agente_ferramentas_prontas_ip_proprio'.freeze
  CONTADOR = 'autonomia:prontas:saida:sem_ip'.freeze
  ERROS_DO_REDIS = Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS

  # Não há IP próprio para dar à conta agora. `message` é um motivo curto do código.
  class SemIp < StandardError; end

  module_function

  # -> o `SafeFetch::Proxy` da conta (com a credencial, só em memória), ou nil para sair pelo IP do servidor.
  def para(conta_id)
    return if conta_id.nil? || !ligada?(conta_id)

    credencial(garantir(conta_id.to_i))
  rescue Webshare::Client::Error, SemIp => e
    sem_ip_proprio(conta_id, e)
  end

  def ligada?(conta_id)
    Account.find_by(id: conta_id)&.feature_enabled?(FLAG) || false
  end

  # -> o `Webshare::Proxy` da conta: o que ela já tem, se ainda serve; senão um novo, sob a trava.
  def garantir(conta_id)
    lista = Autonomia::FerramentasProntas::Saida::ListaDaWebshare.proxies
    atual = Autonomia::FerramentasProntas::ProxyDaConta.find_by(account_id: conta_id)
    Autonomia::FerramentasProntas::Saida::Fatia.vivo(atual, lista) || trocar!(conta_id, lista)
  end

  # Sob a trava, a da conta é relida (outra consulta pode ter escolhido antes) e, se não serve, ganha o primeiro IP livre.
  def trocar!(conta_id, lista)
    Autonomia::FerramentasProntas::ProxyDaConta.exclusivamente do
      atual = Autonomia::FerramentasProntas::ProxyDaConta.find_by(account_id: conta_id)
      Autonomia::FerramentasProntas::Saida::Fatia.vivo(atual, lista) ||
        atribuir!(atual || Autonomia::FerramentasProntas::ProxyDaConta.new(account_id: conta_id), lista)
    end
  end

  def atribuir!(registro, lista)
    usados = Autonomia::FerramentasProntas::ProxyDaConta.where.not(account_id: registro.account_id).pluck(:proxy_address)
    livre = Autonomia::FerramentasProntas::Saida::Fatia.livres(lista, usados: usados).first
    raise SemIp, 'nenhum_ip_livre' if livre.nil?

    troca = registro.persisted?
    registro.update!(proxy_address: livre.address, proxy_port: livre.port, webshare_proxy_id: livre.id, assigned_at: Time.current)
    Rails.logger.info("[autonomia][pronta][saida] conta=#{registro.account_id} proxy=#{livre.id} #{troca ? 'trocou de IP' : 'ganhou IP'}")
    livre
  end

  def credencial(proxy)
    acesso = proxy.to_session_config
    SafeFetch::Proxy.new(address: proxy.address, port: proxy.port, user: acesso[:username], password: acesso[:password])
  end

  # Sem IP próprio: o IP do servidor (nil). O motivo vem só do código (`SemIp`) ou das mensagens do `Webshare::Client`,
  # que nunca levam a chave.
  def sem_ip_proprio(conta_id, erro)
    motivo = erro.is_a?(SemIp) ? erro.message : 'webshare_indisponivel'
    Rails.logger.warn("[autonomia][pronta][saida] sem IP próprio, sai pelo IP do servidor conta=#{conta_id} motivo=#{motivo} " \
                      "(#{erro.message})")
    contar_queda(motivo)
    Autonomia::FerramentasProntas::Saida::Alerta.avisar!('sem_ip_proprio', "consulta pelo IP do servidor (#{motivo})", assunto: motivo)
    nil
  end

  # Quantas consultas saíram pelo IP do servidor por falta de IP próprio, por motivo e por dia.
  def contar_queda(motivo)
    chave = "#{CONTADOR}:#{Time.current.utc.to_date.iso8601}"
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.hincrby(chave, motivo, 1)
        transacao.expire(chave, 3.days.to_i)
      end
    end
  rescue *ERROS_DO_REDIS => e
    Rails.logger.warn("[autonomia][pronta][saida] contador sem Redis #{e.class}")
  end
end

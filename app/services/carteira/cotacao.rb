# A cotação da renovação (E8, #2901): quando o card de renovação nasce, o seguro passa por estas peças, nesta ordem.
# - Carteira::Cotacao::Gatilho: o card que ACABOU de nascer enfileira o começo, se o portão está aberto;
# - Carteira::Cotacao::ComecarJob: trava a vigência (uma vez só) e manda o "Algo mudou?" (Carteira::Cotacao::AlgoMudou);
# - Carteira::CotacaoRespostaListener e Carteira::Cotacao::Resposta: a resposta pelo botão; sem resposta em
#   DIAS_SEM_RESPOSTA, Carteira::Cotacao::SemRespostaJob segue com o que está na apólice;
# - Carteira::Cotacao::Cotar (CotarJob): monta a entrada (Entrada), confere de graça e cota no Agger com o Agente de
#   Cotação; Carteira::Cotacao::AcompanharJob lê o resultado, guarda a proposta como nota privada e, no modo `sozinho`,
#   manda (Carteira::Cotacao::Proposta);
# - Carteira::Cotacao::Aviso: o que precisa de alguém da equipe vira atividade e tarefa no card.
#
# O portão de tudo: a conta tem a carteira (Carteira::Acesso), a chave da cotação (Liberada) e escolheu quem cota. Sem
# isso nada daqui roda, e a renovação é a da E5.
module Carteira::Cotacao
  DIAS_SEM_RESPOSTA = 3
  # A marca das mensagens que a cotação manda ao cliente (`content_attributes`), com a apólice e a etapa.
  MARCA = 'carteira_renovacao'.freeze
  ETAPA_ALGO_MUDOU = 'algo_mudou'.freeze
  ETAPA_O_QUE_MUDOU = 'o_que_mudou'.freeze
  ETAPA_PROPOSTA = 'proposta'.freeze
  ETAPA_PROPOSTA_GUARDADA = 'proposta_guardada'.freeze
  # Os payloads dos botões do "Algo mudou?" (Whatsapp::Templates::Finalidades::RenovacaoAlgoMudou) e o que cada um diz.
  NADA_MUDOU = 'nada_mudou'.freeze
  MUDOU = 'mudou'.freeze
  RESPOSTAS = { 'renovacao_nada_mudou' => NADA_MUDOU, 'renovacao_mudou' => MUDOU }.freeze
  # O Guia não manda a proposta ao cliente por ninguém: só o clique na tela.
  SO_NA_TELA_DO_GUIA = { 'POST relacionamentos/seguros/:id/enviar_proposta' => 'seguro_proposta' }.freeze

  module_function

  # A conta tem a carteira, a chave da cotação e escolheu quem cota.
  def aberta?(account, config)
    config.present? && config.quem_cota != Carteira::RenovacaoConfig::NINGUEM && Carteira::Acesso.liberada?(account) &&
      Carteira::Cotacao::Liberada.para?(account)
  end

  # O seguro e os ajustes da conta para um job da cotação: só com a mesma vigência em que o job nasceu e o portão aberto.
  # -> [apolice, config] ou nil.
  def da_vigencia(apolice_id, vigencia)
    apolice = Carteira::Apolice.find_by(id: apolice_id)
    return if apolice.nil? || apolice.fim_vigencia.iso8601 != vigencia

    config = Carteira::RenovacaoConfig.find_by(account_id: apolice.account_id)
    [apolice, config] if aberta?(apolice.account, config)
  end

  # O Agente de Cotação da conta (a Lia), ou nil. É com ele que o robô cota (o ToolRun pede o agente).
  def agente(account)
    Autonomia::Agents::Agent.kept.find_by(account: account, agent_type: 'insurance_quote')
  end

  # A Lia está ligada nesta caixa (para responder quando o segurado escrever).
  def lia_na_caixa?(agente, inbox_id)
    agente.present? && inbox_id.present? && Autonomia::Agents::AgentInbox.kept.exists?(autonomia_agent_id: agente.id, inbox_id: inbox_id)
  end

  # A caixa entrega toda conversa nova a alguém da equipe (a distribuição automática, a antiga e a nova, que só rodam com
  # `enable_auto_assignment`). A Lia não responde conversa que está com alguém.
  def caixa_distribui?(inbox)
    inbox.present? && inbox.enable_auto_assignment?
  end

  # O passo da história desta vigência, ou nil.
  def passo(apolice, tipo)
    apolice.eventos.where(tipo: tipo).where("valores->>'vigencia' = ?", apolice.fim_vigencia.iso8601).order(:quando, :id).last
  end

  # O segurado respondeu "Mudou algo" nesta vigência: o robô não cota (quem cuida é a equipe, ou a Lia).
  def mudou?(apolice)
    passo(apolice, 'respondeu_algo_mudou')&.valores.to_h['resposta'] == MUDOU
  end

  # Um passo da história nesta vigência. Os valores vêm num hash (`registrar(a, tipo, { motivo: x })`) ou soltos
  # (`registrar(a, tipo, motivo: x)`): no Ruby 3 as chaves soltas chegam como keywords, e as duas formas se juntam aqui.
  def registrar(apolice, tipo, valores = {}, user: nil, **mais)
    dados = { vigencia: apolice.fim_vigencia.iso8601 }.merge(valores.to_h.symbolize_keys, mais)
    apolice.eventos.create!(tipo: tipo, quando: Time.current, user: user, valores: dados)
  end

  # A marca de uma mensagem: { 'apolice_id' =>, 'etapa' => } ou {}.
  def marca_de(mensagem)
    atributos = mensagem&.content_attributes
    atributos = JSON.parse(atributos) if atributos.is_a?(String)
    marca = atributos.is_a?(Hash) ? atributos.with_indifferent_access[MARCA] : nil
    marca.is_a?(Hash) ? marca.stringify_keys : {}
  rescue JSON::ParserError
    {}
  end
end

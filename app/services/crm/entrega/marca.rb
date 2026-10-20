# A marca de "o motor de entrega cuida desta conversa" (#1454). Fica nos atributos adicionais da conversa, gravada sob a
# trava dela, enquanto o motor (Crm::Entrega) segura a conversa até alguém ficar online ou espera o convidado pegar.
#
# Com a marca:
#   - o rodízio nativo (V1 e V2, OSS e Enterprise) pula a conversa: nunca duas atribuições, nem uma por cima da regra;
#   - o HandoffDrainJob tenta de novo a cada 2 minutos (segurando) ou limpa o convite vencido.
# A marca sai quando uma pessoa é atribuída, quando a conversa é resolvida ou quando alguém a entrega de novo a um robô
# (ConversationBotHandoff#end_bot_handoff_wait). Adiada, a conversa guarda a marca e volta à fila quando reabre.
module Crm::Entrega::Marca
  CHAVE = 'crm_entrega'.freeze
  SEGURANDO = 'segurando'.freeze
  CONVITE = 'convite'.freeze
  # Conversas que o rodízio nativo pode pegar.
  AUSENTE_SQL = "(conversations.additional_attributes ->> '#{CHAVE}') IS NULL".freeze
  PRESENTE_SQL = "(conversations.additional_attributes ->> '#{CHAVE}') IS NOT NULL".freeze
  # O motivo da IA do CRM guardado na marca, no mesmo tamanho do "reason" do classificador.
  RAZAO_MAX = 300
  # A releitura da IA do CRM em curso (#1975): saem juntas quando ela termina.
  RELEITURA_EM_CURSO = %w[revalidando_desde reenfileirado_em].freeze

  module_function

  def presente?(conversation)
    dados(conversation).present?
  end

  def dados(conversation)
    atributos = conversation.additional_attributes
    valor = atributos.is_a?(Hash) ? atributos[CHAVE] : nil
    valor.is_a?(Hash) ? valor : nil
  end

  # Só na memória: quem chama grava (sob a trava). `motivo`: por que a conversa precisa de alguém (a origem);
  # `falha`: por que ainda não foi entregue. `desde` e `avisado_em` sobrevivem às novas tentativas, para medir a espera
  # e avisar uma vez só; `tentado_em` é da fila (HandoffDrainJob).
  # `detalhes`: `sugestao` (o nome que a IA sugeriu, para a próxima tentativa), `dono` (a pessoa a quem a entrega é
  # dirigida, R13 do #1150: a próxima tentativa segue esperando por ela), `ate` (o fim do convite), `convidado` (quem
  # foi convidado) e `venceram` (ids de quem deixou um convite desta espera vencer, #1694; sobrevive às novas
  # tentativas, como `desde`). `decidido_em`: com `venceram`, quando a regra decidiu por último (a fila espaça a espera sem ninguém); sem
  # ele, a marca não muda a cada tentativa. `card`: o card cuja regra vale, quando o pedido foi ligado a um assunto que
  # não é o foco (#1693). `razao`: o motivo que a IA do CRM deu ao pedir a pessoa (#1975), que vai junto na entrega pela
  # fila. `revalidado_ate`: a última mensagem que a reavaliação da fila leu (Crm::Ai::RevalidacaoNaFila; 0 se não havia
  # nenhuma); sobrevive às novas tentativas, para a fila não pagar outra reavaliação sem mensagem nova. A releitura em
  # curso (RELEITURA_EM_CURSO) não sobrevive: uma marca regravada pede outra releitura, e o job antigo vira nada.
  def marcar(conversation, modo:, motivo:, falha: nil, **detalhes)
    anterior = dados(conversation) || {}
    valor = {
      'modo' => modo,
      'motivo' => motivo.to_s,
      'falha' => falha.presence,
      'desde' => desde_para(anterior, modo),
      'avisado_em' => anterior['avisado_em'].presence,
      'tentado_em' => anterior['tentado_em'].presence,
      'dono_id' => detalhes[:dono]&.id,
      'ate' => detalhes[:ate]&.iso8601,
      'convidado_id' => detalhes[:convidado]&.id,
      'card_id' => detalhes[:card]&.id
    }.merge(vencimentos(anterior, detalhes[:venceram]), pedido(anterior, detalhes)).compact
    conversation.additional_attributes = (conversation.additional_attributes || {}).merge(CHAVE => valor)
  end

  # Quem deixou vencer (sobrevive às tentativas) e, com isso, quando a regra decidiu por último.
  def vencimentos(anterior, venceram)
    venceram = (venceram || anterior['venceram']).presence
    { 'venceram' => venceram, 'decidido_em' => venceram && Time.current.iso8601 }
  end

  # O que a IA do CRM pediu: o nome sugerido, o motivo e a última mensagem que a fila releu (#1975); esta sobrevive às
  # tentativas.
  def pedido(anterior, detalhes)
    { 'sugestao' => detalhes[:sugestao].presence, 'razao' => detalhes[:razao].to_s.first(RAZAO_MAX).presence,
      'revalidado_ate' => anterior['revalidado_ate'].presence }
  end

  # O prazo do convite conta do CONVITE: virar convite recomeça a contagem; o resto (inclusive convite → segurando)
  # mantém o começo da espera.
  def desde_para(anterior, modo)
    return Time.current.iso8601 if modo == CONVITE && anterior['modo'] != CONVITE

    anterior['desde'].presence || Time.current.iso8601
  end

  # O card cuja regra vale (#1693), da conta da conversa; a Entrega confere se ele segue aberto nela.
  def card(conversation)
    id = dados(conversation)&.dig('card_id')
    conversation.account.crm_cards.find_by(id: id) if id.present?
  end

  # A releitura da fila (#1975, Crm::Ai::RevalidacaoNaFila) terminou com o pedido de pé, ou falhou: guarda a última
  # mensagem lida, o motivo novo (qual problema ficou aberto) e se falhou, e a releitura em curso sai. Só na memória:
  # quem chama grava, sob a trava.
  def revalidada!(conversation, ate:, razao:, falhou: false)
    valor = (dados(conversation) || {}).except(*RELEITURA_EM_CURSO).merge('revalidado_ate' => ate)
    valor['razao'] = razao.to_s.first(RAZAO_MAX) if razao.present?
    valor['revalidacao_falhou'] = true if falhou
    conversation.additional_attributes = conversation.additional_attributes.merge(CHAVE => valor)
  end

  # A releitura em curso (#1975): quando o job foi enfileirado (`revalidando_desde`, também a chave que o job confere)
  # e, se a fila voltou a enfileirar um job que parecia perdido, quando (`reenfileirado_em`).
  def revalidando!(conversation, campo, quando)
    valor = (dados(conversation) || {}).merge(campo => quando)
    conversation.additional_attributes = conversation.additional_attributes.merge(CHAVE => valor)
  end

  def sem_releitura!(conversation)
    valor = (dados(conversation) || {}).except(*RELEITURA_EM_CURSO)
    conversation.additional_attributes = conversation.additional_attributes.merge(CHAVE => valor)
  end

  def tirar(conversation)
    return unless conversation.additional_attributes.is_a?(Hash)

    conversation.additional_attributes = conversation.additional_attributes.except(CHAVE)
  end

  # Há quanto tempo o motor segura ou convida esta conversa.
  def desde(conversation)
    Time.zone.parse(dados(conversation)&.dig('desde').to_s)
  rescue ArgumentError
    nil
  end

  # Marca o aviso de "não conseguimos chamar ninguém" (na memória), para ele sair uma vez só.
  def avisado!(conversation)
    valor = (dados(conversation) || {}).merge('avisado_em' => Time.current.iso8601)
    conversation.additional_attributes = conversation.additional_attributes.merge(CHAVE => valor)
  end

  # Um convite esperando a convidada pegar, ainda no prazo.
  def convite_aberto?(conversation)
    dados(conversation)&.dig('modo') == CONVITE && !convite_vencido?(conversation)
  end

  def convite_vencido?(conversation, agora: Time.current)
    valor = dados(conversation)
    return false unless valor && valor['modo'] == CONVITE

    ate = Time.zone.parse(valor['ate'].to_s)
    ate.nil? || ate <= agora
  rescue ArgumentError
    true
  end
end

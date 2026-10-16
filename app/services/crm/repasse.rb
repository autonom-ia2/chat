# Decisão "a" do Rodrigo (#1606, 15/10): o assunto da conversa mudou depois que uma PESSOA a recebeu, e ela não cuida do
# funil novo. Nada troca sozinho: a conversa fica com ela, e só ela vê a sugestão "O assunto virou X. Quer passar para a
# equipe de X?" (CrmRepasseDoAssunto.vue).
#
#   Crm::Repasse.sugerir!(conversation)          -> grava ou apaga a sugestão (a marca na conversa); true se mudou
#   Crm::Repasse.para(conversation, user)       -> { card_id:, pipeline_name: } para quem está com a conversa, ou nil
#   Crm::Repasse.passar!(conversation, user, card_id)  -> a pessoa sai e o motor de entrega (Crm::Entrega) escolhe pela
#                                                         Atribuição do funil novo; a passagem vai pelo listener, motivo
#                                                         'assunto'
#   Crm::Repasse.manter!(conversation, user, card_id)  -> apaga a sugestão e não repete para o mesmo assunto (card)
#
# A marca fica em additional_attributes (sem coluna nova em tabela do Chatwoot): o card, o funil e a pessoa para quem a
# sugestão vale. Sugestão de outra pessoa (a conversa mudou de mãos) não vale e sai na próxima leitura do assunto.
# "A equipe de X" é quem cuida do funil do card (Crm::Entrega::QuemCuida, a fila do motor de entrega): sem ninguém além da
# pessoa, não há para quem passar e nada é sugerido.
#
# Só a TROCA de assunto com uma pessoa já no nome gera o aviso (decisão de produto, 15/10). Atribuir uma pessoa a uma
# conversa cujo assunto já é de outro funil não gera aviso: não há gatilho na atribuição, de propósito. Conversa
# resolvida ou adiada perde o aviso (Crm::ConversationObserverListener#conversation_status_changed).
module Crm::Repasse
  CHAVE = 'crm_repasse'.freeze
  DISPENSADOS = 'crm_repasse_dispensados'.freeze
  # Quantos assuntos dispensados a conversa lembra (os mais recentes).
  MAX_DISPENSADOS = 20
  MOTIVO = 'assunto'.freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  module_function

  # Sob a trava do CardSyncer (conversa e contato), com tudo relido. Devolve true quando a marca mudou (para avisar a
  # tela em tempo real).
  def sugerir!(conversation)
    mudou = false
    Crm::Conversations::SyncLock.new(account: conversation.account, conversation: conversation).perform do
      desejada = marca_desejada(conversation)
      next if desejada == conversation.additional_attributes.to_h[CHAVE]

      gravar_marca(conversation, desejada)
      mudou = true
    end
    Crm::Subjects::Notifier.notify(conversation) if mudou
    mudou
  end

  def para(conversation, user)
    marca = valida(conversation, user)
    return if marca.nil?

    card = Crm::Card.find_by(account_id: conversation.account_id, id: marca['card_id'])
    return if card.nil?

    { card_id: card.id, pipeline_name: card.pipeline&.name, equipe_online: equipe_online?(conversation, card, user) }
  end

  # Alguém da equipe do funil, além da pessoa, está online agora? Sem ninguém, "Passar" deixa a conversa esperando (como a
  # triagem), e a tela avisa antes (decisão 2a do Rodrigo, 15/10). true/false; nil quando a presença está fora do ar
  # (desconhecido): a tela não diz "ninguém online" sem saber. Só a falha de leitura da presença (Redis ou o pool dele)
  # vira nil; qualquer outro erro sobe.
  def equipe_online?(conversation, card, user)
    return true if agente_na_regra?(conversation, card)

    equipe = Crm::Entrega::QuemCuida.new(conversation: conversation, card: card).pessoas.map(&:id) - [user.id]
    online = presenca(conversation)
    online.nil? ? nil : equipe.intersect?(online.to_a)
  end

  def presenca(conversation)
    Crm::Entrega::Presenca.online_ids(conversation.account_id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    Rails.logger.warn("[crm][repasse] presença indisponível conversa=#{conversation.id} #{e.class}")
    nil
  end

  # A conversa mudou de mãos: o aviso era da pessoa de antes e sai (a atribuição não gera aviso novo, de propósito).
  def limpar_se_mudou_de_mao!(conversation)
    marca = conversation.additional_attributes.to_h[CHAVE]
    limpar!(conversation) if marca.present? && marca['user_id'] != conversation.assignee_id
  end

  # Tira o aviso (conversa resolvida ou adiada, ou que mudou de mãos). Sem marca, nada grava.
  def limpar!(conversation)
    return if conversation.additional_attributes.to_h[CHAVE].blank?

    Crm::Conversations::SyncLock.new(account: conversation.account, conversation: conversation).perform do
      gravar_marca(conversation, nil)
    end
    Crm::Subjects::Notifier.notify(conversation)
  end

  def passar!(conversation, user, card_id)
    Crm::Conversations::SyncLock.new(account: conversation.account, conversation: conversation).perform do
      conferir!(conversation, user, card_id)
      gravar_marca(conversation, nil)
      # A marca sai antes, numa gravação que não troca o atendente. Depois, como na saída da triagem, a passagem é uma
      # gravação só (sai a pessoa, entra quem a Entrega escolheu, ou a marca de espera), dentro do
      # Crm::Passagens.com_motivo('assunto') do próprio bot_handoff!; o listener grava a passagem.
      conversation.bot_handoff!(dispatch_event: false, motivo: MOTIVO, release_assignee: true)
    end
    Crm::Subjects::Notifier.notify(conversation)
  end

  def manter!(conversation, user, card_id)
    Crm::Conversations::SyncLock.new(account: conversation.account, conversation: conversation).perform do
      conferir!(conversation, user, card_id)
      dispensados = (Array(conversation.additional_attributes.to_h[DISPENSADOS]) + [card_id.to_i]).uniq.last(MAX_DISPENSADOS)
      conversation.additional_attributes = conversation.additional_attributes.to_h.except(CHAVE).merge(DISPENSADOS => dispensados)
      conversation.save!
    end
    Crm::Subjects::Notifier.notify(conversation)
  end

  # A marca que a conversa deveria ter agora: a do assunto atual, se a pessoa no nome não cuida dele e há equipe.
  def marca_desejada(conversation)
    return unless conversation.open? || conversation.pending?

    pessoa = pessoa_no_nome(conversation)
    card = Crm::Assunto.funil_atual(conversation)
    return unless pessoa && card && sugerivel?(conversation, card, pessoa)

    mesma_marca(conversation, card, pessoa) ||
      { 'card_id' => card.id, 'pipeline_id' => card.pipeline_id, 'user_id' => pessoa.id, 'em' => Time.current.iso8601 }
  end

  def sugerivel?(conversation, card, pessoa)
    !dispensado?(conversation, card) && passa_para_outra_equipe?(conversation, card, pessoa)
  end

  # A sugestão já gravada para o mesmo card e a mesma pessoa fica como está (sem novo aviso).
  def mesma_marca(conversation, card, pessoa)
    atual = conversation.additional_attributes.to_h[CHAVE]
    atual if atual && atual['card_id'] == card.id && atual['user_id'] == pessoa.id
  end

  # A pessoa não está na equipe do funil do card, e a equipe tem mais alguém para receber.
  def passa_para_outra_equipe?(conversation, card, pessoa)
    equipe = Crm::Entrega::QuemCuida.new(conversation: conversation, card: card).pessoas
    return false if equipe.include?(pessoa)

    equipe.any? || agente_na_regra?(conversation, card)
  end

  # A Atribuição do funil aponta um agente de IA que pode receber agora (#1620, a mesma leitura do motor de entrega,
  # Crm::Entrega::ParaIa.alvo): conta como "tem quem receba". Quem passa é a pessoa, então não há robô a excluir.
  def agente_na_regra?(conversation, card)
    settings = Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)
    return false unless settings[:enabled]

    Crm::Entrega::ParaIa.alvo(conversation: conversation, settings: settings, sugestao: nil, quem_passa: nil).present?
  end

  def pessoa_no_nome(conversation)
    return if conversation.assignee_id.blank?

    conversation.account.users.find_by(id: conversation.assignee_id)
  end

  def dispensado?(conversation, card)
    Array(conversation.additional_attributes.to_h[DISPENSADOS]).include?(card.id)
  end

  # A marca vale só para quem está com a conversa, com ela em andamento (aberta ou pendente: passar reabriria uma resolvida
  # ou adiada) e enquanto o card dela for o assunto atual.
  def valida(conversation, user)
    marca = conversation.additional_attributes.to_h[CHAVE]
    return unless marca.present? && dela_e_em_andamento?(conversation, marca, user)

    marca if Crm::Assunto.funil_atual(conversation)&.id == marca['card_id']
  end

  def dela_e_em_andamento?(conversation, marca, user)
    user.present? && marca['user_id'] == user.id && conversation.assignee_id == user.id &&
      (conversation.open? || conversation.pending?)
  end

  def conferir!(conversation, user, card_id)
    marca = valida(conversation, user)
    raise Error, 'repasse_nao_e_seu' if conversation.assignee_id != user&.id
    raise Error, 'repasse_mudou' if marca.nil? || marca['card_id'] != card_id.to_i
  end

  def gravar_marca(conversation, marca)
    atributos = conversation.additional_attributes.to_h.except(CHAVE)
    conversation.additional_attributes = marca ? atributos.merge(CHAVE => marca) : atributos
    conversation.save! if conversation.changed?
  end
end

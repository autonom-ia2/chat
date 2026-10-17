# QUEM ESCREVEU CADA MENSAGEM (#1601, W1). Calculado pelo código, a partir do banco, nunca pelo modelo:
#
#   Crm::Memoria::Origem.classificar(message, config:) -> Resultado   # só leitura, sem efeito
#   Crm::Memoria::Origem.gravar!(message)                -> Crm::MensagemOrigem
#   Crm::Memoria::Origem.para(message)                   -> Crm::MensagemOrigem (lê; sem linha, calcula e grava)
#
# Reaproveita os predicados puros do PessoaDaEquipe (da_pessoa?, envio_automatico?, eco_do_celular?), sem o gate
# `aplica?` (Fase 2 dos Agentes): a autoria vale para toda conta com a memória ligada. Acrescenta só o que lá não existe:
# o robô de fora com login de pessoa (Crm::MemoriaConfig#usuarios_robo_ids), a duplicata da sincronização e a
# mensagem sem conteúdo.
#
# `foi_ao_cliente`: saída (ou template do canal) que não é nota privada e não falhou no envio. A mensagem do cliente é
# `false`: ela veio dele, não foi a ele.
#
# Duplicata: o mesmo `source_id` do provedor numa mensagem anterior da conversa; ou, sem ele, o mesmo lado (cliente ou
# nós) com o mesmo `conteudo_hash` em até 120 s, SEM mensagem do outro lado no meio (o 2º "sim" depois de uma pergunta
# nossa é resposta, não duplicata). Nota privada não conta como "outro lado".
#
# Mensagem ENCAMINHADA (`content_attributes.forwarded`, #1702b): a pessoa que encaminhou é a autora (pessoa_painel),
# com `encaminhada: true`. Não cumpre a tarefa de retomar e não é prova de fato (pode ser fala de outro cliente).
#
# D1 (decisão do Rodrigo, 16/10/2026): a mensagem que o provedor grava como "This message is unavailable" é
# indisponível e sem conteúdo, por igualdade exata com o texto do provedor (não é fala de pessoa; nada de lista de
# palavras).
module Crm::Memoria::Origem
  VERSAO = 1
  TEXTO_INDISPONIVEL = 'This message is unavailable'.freeze
  MARCAS_INDISPONIVEL = %w[is_unsupported view_once_unavailable].freeze
  JANELA_DUPLICATA = 120.seconds
  # Quantas mensagens anteriores olhar atrás de uma duplicata (dentro da janela de 120 s).
  LIMITE_DUPLICATA = 20

  Resultado = Data.define(:autor_tipo, :autor_ref_type, :autor_ref_id, :foi_ao_cliente, :duplicata_de_message_id,
                          :indisponivel, :sem_conteudo, :encaminhada, :conteudo_hash, :regra)

  module_function

  def classificar(message, config:)
    autor, ref, regra = autor_de(message, config)
    indisponivel = indisponivel?(message)
    sem_conteudo = indisponivel || sem_conteudo?(message)
    hash = conteudo_hash(message)
    Resultado.new(
      autor_tipo: autor, autor_ref_type: ref&.first, autor_ref_id: ref&.last, foi_ao_cliente: foi_ao_cliente?(message),
      duplicata_de_message_id: sem_conteudo ? nil : duplicata_de(message, hash), indisponivel: indisponivel,
      sem_conteudo: sem_conteudo, encaminhada: encaminhada?(message), conteudo_hash: hash, regra: regra
    )
  end

  # Grava (ou regrava) a autoria. A linha corrigida por uma pessoa não é tocada: a correção vence a do código. Sob a
  # trava da linha: a correção que chega entre a leitura e a gravação não é sobrescrita. Duas gravações da mesma
  # mensagem nova ao mesmo tempo (criada e logo mudada): a segunda esbarra no índice único e classifica de novo, sobre a
  # linha da primeira.
  def gravar!(message, config: nil, tentativa: 1)
    conversation = message.conversation
    return if conversation&.contact_id.blank?

    config ||= Crm::Memoria.config(message.account)
    Crm::MensagemOrigem.transaction(requires_new: true) { gravar_sob_trava(message, conversation, config) }
  rescue ActiveRecord::RecordNotUnique
    raise if tentativa > 1

    gravar!(message, config: config, tentativa: tentativa + 1)
  end

  def gravar_sob_trava(message, conversation, config)
    linha = Crm::MensagemOrigem.lock.find_by(message_id: message.id) || Crm::MensagemOrigem.new(message_id: message.id)
    return linha if linha.corrigido_por_user_id.present?

    linha.assign_attributes(atributos(message, conversation, config))
    linha.save!
    linha
  end

  def atributos(message, conversation, config)
    ActiveRecord::Associations::Preloader.new(records: [message], associations: { attachments: { file_attachment: :blob } }).call
    classificar(message, config: config).to_h.merge(account_id: message.account_id, conversation_id: conversation.id,
                                                    contact_id: conversation.contact_id, classificador_versao: VERSAO)
  end

  def para(message)
    Crm::MensagemOrigem.find_by(message_id: message.id) || gravar!(message)
  end

  # -> [autor_tipo, [ref_type, ref_id] | nil, regra]
  def autor_de(message, config)
    return ['sistema', nil, 'atividade'] if message.activity?
    return ['cliente', ref(message), 'entrada'] if message.incoming?
    return ['sistema', nil, 'template'] if message.template?

    case message.sender_type
    when 'User' then autor_pessoa(message, config)
    when 'AgentBot' then autor_robo(message)
    when nil, '' then autor_sem_remetente(message)
    else ['desconhecido', ref(message), 'remetente_desconhecido']
    end
  end

  def autor_pessoa(message, config)
    return ['robo_externo', ref(message), 'robo_declarado'] if config.robo?(message.sender_id)
    return ['follow_up_nosso', ref(message), 'follow_up'] if message.content_attributes.to_h['crm_follow_up_id'].present?
    return ['sistema', ref(message), 'envio_automatico'] if pessoa_da_equipe.envio_automatico?(message)

    ['pessoa_painel', ref(message), message.private? ? 'nota' : 'pessoa']
  end

  # O espelho de um agente nosso (AgentInbox) é a nossa IA; qualquer outro robô é de fora (n8n, integração).
  def autor_robo(message)
    nosso = Autonomia::Agents::AgentInbox.exists?(account_id: message.account_id, agent_bot_id: message.sender_id)
    nosso ? ['ia_nossa', ref(message), 'ia_nossa'] : ['robo_externo', ref(message), 'robo_externo']
  end

  def autor_sem_remetente(message)
    return ['pessoa_celular', nil, 'eco_celular'] if pessoa_da_equipe.eco_do_celular?(message)

    ['sistema', nil, 'saida_sem_remetente']
  end

  def ref(message)
    [message.sender_type, message.sender_id] if message.sender_type.present? && message.sender_id.present?
  end

  def foi_ao_cliente?(message)
    (message.outgoing? || message.template?) && !message.private? && !message.failed?
  end

  def encaminhada?(message)
    message.content_attributes.to_h['forwarded'].present?
  end

  # Igualdade exata com o texto do provedor (D1), ou a marca estrutural do canal: a bolha "abra no celular"
  # (`is_unsupported`) e a visualização única que não dá para abrir (`view_once_unavailable`), #1709.
  def indisponivel?(message)
    atributos = message.content_attributes.to_h
    message.content.to_s == TEXTO_INDISPONIVEL || MARCAS_INDISPONIVEL.any? { |marca| atributos[marca].present? }
  end

  # Sem texto, e nenhum anexo com conteúdo: arquivo, link externo (mídia do Instagram/Facebook), localização, título
  # (cartão de link, contato), transcrição ou legenda.
  def sem_conteudo?(message)
    return false if message.content.to_s.strip.present?

    message.attachments.none? { |attachment| anexo_com_conteudo?(attachment) }
  end

  def anexo_com_conteudo?(attachment)
    meta = attachment.meta.to_h
    attachment.file.attached? || attachment.external_url.present? || attachment.file_type.to_s == 'location' ||
      attachment.fallback_title.present? || meta['transcribed_text'].present? || meta['ai_caption'].present?
  end

  # sha256 do texto (sem espaços nas pontas, minúsculo) e dos anexos (o checksum do arquivo; sem arquivo, o id).
  def conteudo_hash(message)
    anexos = message.attachments.map { |attachment| attachment.file.attached? ? attachment.file.blob.checksum : "a#{attachment.id}" }
    Digest::SHA256.hexdigest([message.content.to_s.strip.downcase, *anexos.sort].join("\u0000"))
  end

  def duplicata_de(message, hash)
    return if message.private? || message.activity?

    mesmo_source_id(message) || mesmo_conteudo(message, hash)
  end

  def mesmo_source_id(message)
    return if message.source_id.blank?

    Message.where(conversation_id: message.conversation_id, source_id: message.source_id)
           .where(id: ...message.id).minimum(:id)
  end

  # Da mais nova para a mais antiga, dentro da janela: para na primeira mensagem do outro lado.
  def mesmo_conteudo(message, hash)
    anteriores(message).each do |anterior|
      break unless anterior.incoming? == message.incoming?
      return anterior.id if conteudo_hash(anterior) == hash
    end
    nil
  end

  def anteriores(message)
    Message.where(conversation_id: message.conversation_id, private: false)
           .where.not(message_type: :activity)
           .where(id: ...message.id, created_at: (message.created_at - JANELA_DUPLICATA)..)
           .includes(attachments: { file_attachment: :blob })
           .reorder(id: :desc).limit(LIMITE_DUPLICATA)
  end

  def pessoa_da_equipe
    Autonomia::Agents::Operate::PessoaDaEquipe
  end
end

# QUEM ESCREVEU UMA MENSAGEM, para a memória das IAs (#1601). Função pura, calculada na hora a partir da própria
# mensagem, nunca pelo modelo e sem tabela (a main já grava o eco do celular, o robô com o token dele e não repete
# source_id: o que faltava era só ler isso do mesmo jeito em todo lugar):
#
#   Crm::Memoria::Origem.classificar(message) -> Resultado   # autor_tipo, foi_ao_cliente, descartavel?, ...
#
# Reaproveita os predicados puros do PessoaDaEquipe (envio_automatico?, eco_do_celular?), sem o gate `aplica?` (Fase 2
# dos Agentes).
#
# `foi_ao_cliente`: saída (ou template do canal) que não é nota privada e não falhou no envio. A mensagem do cliente é
# `false`: ela veio dele, não foi a ele.
#
# Duplicata: o mesmo `source_id` numa mensagem anterior da conversa; ou o mesmo lado com o mesmo conteúdo em até 120 s,
# SEM mensagem do outro lado no meio (o 2º "sim" depois de uma pergunta nossa é resposta, não duplicata).
#
# Mensagem ENCAMINHADA (`content_attributes.forwarded`, #1702b): conta como resposta da pessoa (decisão do Rodrigo,
# 17/10), mas não é prova de fato (pode ser fala de outro cliente).
#
# E-MAIL DE OUTRO ENDEREÇO (#1807, flag `email_autoria`): `email_autoria` diz se o e-mail recebido veio de outra pessoa
# em cópia, da equipe ou de resposta automática (Crm::Email::Autoria); nil quando é do cliente (ou não é e-mail). A
# mensagem continua valendo como prova do pedido e da conversa, mas não de dado pessoal do cliente (`prova_de_contato?`).
#
# Sem conteúdo (D1, pela marca estrutural, nunca pelo texto, que é traduzido pela língua da conta): a bolha "abra no
# celular" (`is_unsupported`, incoming_message_base_service.rb), a visualização única que não abre
# (`view_once_unavailable`), o marcador de mídia do histórico importado (`is_history_media_placeholder`) e a mensagem
# sem texto nem anexo com conteúdo.
module Crm::Memoria::Origem
  MARCAS_INDISPONIVEL = %w[is_unsupported view_once_unavailable is_history_media_placeholder].freeze
  PESSOAS = %w[pessoa_painel pessoa_celular].freeze
  JANELA_DUPLICATA = 120.seconds
  # Quantas mensagens anteriores olhar atrás de uma duplicata (dentro da janela de 120 s).
  LIMITE_DUPLICATA = 20

  Resultado = Data.define(:autor_tipo, :autor_ref_type, :autor_ref_id, :foi_ao_cliente, :duplicata_de_message_id,
                          :indisponivel, :sem_conteudo, :encaminhada, :conteudo_hash, :regra, :email_autoria) do
    # Não vale como prova de fato: duplicata, indisponível, sem conteúdo ou encaminhada.
    def descartavel?
      duplicata_de_message_id.present? || indisponivel || sem_conteudo || encaminhada
    end

    # Uma pessoa da equipe respondeu ao cliente de verdade (painel ou celular, pública, não falhou; a encaminhada conta).
    # Prova dado pessoal do cliente (grupo "contato"): só o que o cliente escreveu do endereço dele.
    def prova_de_contato?
      email_autoria.nil?
    end

    def resposta_da_pessoa?
      PESSOAS.include?(autor_tipo) && foi_ao_cliente
    end
  end

  module_function

  # autoria: o Crm::Email::Autoria de quem chama (um por avaliação, para não reler o contato a cada mensagem).
  def classificar(message, autoria: nil)
    autor, ref, regra = autor_de(message)
    indisponivel = indisponivel?(message)
    sem_conteudo = indisponivel || sem_conteudo?(message)
    hash = conteudo_hash(message)
    Resultado.new(
      autor_tipo: autor, autor_ref_type: ref&.first, autor_ref_id: ref&.last, foi_ao_cliente: foi_ao_cliente?(message),
      duplicata_de_message_id: sem_conteudo ? nil : duplicata_de(message, hash), indisponivel: indisponivel,
      sem_conteudo: sem_conteudo, encaminhada: encaminhada?(message), conteudo_hash: hash, regra: regra,
      email_autoria: (autoria || Crm::Email::Autoria.new(message.account)).de(message)&.tipo
    )
  end

  # -> [autor_tipo, [ref_type, ref_id] | nil, regra]
  def autor_de(message)
    return ['sistema', nil, 'atividade'] if message.activity?
    return ['cliente', ref(message), 'entrada'] if message.incoming?
    return ['sistema', nil, 'template'] if message.template?

    case message.sender_type
    when 'User' then autor_pessoa(message)
    when 'AgentBot' then autor_robo(message)
    when nil, '' then autor_sem_remetente(message)
    else ['desconhecido', ref(message), 'remetente_desconhecido']
    end
  end

  def autor_pessoa(message)
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

  def indisponivel?(message)
    atributos = message.content_attributes.to_h
    MARCAS_INDISPONIVEL.any? { |marca| atributos[marca].present? }
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

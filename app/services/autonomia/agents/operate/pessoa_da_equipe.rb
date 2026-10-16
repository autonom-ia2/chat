# Uma PESSOA da equipe escreveu ao cliente sem se atribuir (#1669). Pela decisão de 13/10 a IA segue na conversa, com o
# robô no nome, até alguém clicar em "Atribuir a mim". Duas coisas mudam, só com a Fase 2 ligada:
#
# (a) No histórico que vai ao modelo, a mensagem da pessoa chega MARCADA como dela, num item de papel `user` com a
#     moldura "[Ana, da equipe, escreveu ao cliente. ...]". Antes ela ia como `assistant`, e a IA lia o que a Ana
#     escreveu como se fosse dela. Por que `user` e não `assistant` com prefixo: o item `assistant` é a voz do próprio
#     modelo, e um prefixo ali é o exemplo mais forte de como ele "fala" — é o caminho mais curto para ele imitar a
#     marca na resposta. No `user` a marca é dado de entrada, como o contexto e os documentos (PromptParts), e o que
#     o modelo escreveu continua sem marca nenhuma. `developer` daria ao texto da pessoa autoridade de instrução.
# (b) Se a pessoa respondeu publicamente DEPOIS da mensagem do cliente que o turno vai responder, a IA não responde
#     aquela mensagem (silêncio `pessoa_respondeu`). A IA não sai da conversa: a próxima mensagem do cliente, mais
#     nova que a resposta da pessoa, volta a ser dela.
#
# ECO DO CELULAR (decisão do Rodrigo, opção c): no WhatsApp (caixa Híbrida ou de coexistência), o que a equipe manda
# pelo app do celular volta como eco (`external_echo`, sem remetente). Entra no histórico com a moldura da equipe, sem
# nome ("[Alguém da equipe, pelo celular, escreveu ao cliente. ...]"), e NÃO cala a IA (só pessoa com remetente cala).
# O eco da PRÓPRIA mensagem da IA na caixa Híbrida é reconciliado na bolha que já existe
# (WhatsappHybrid::EchoReconcilerExtension): a bolha segue do robô e sem `external_echo`, então segue `assistant`.
# Efeito conhecido da corrida: se o eco chega antes de a bolha da IA ter o id físico, o reconciliador não a acha e o eco
# vira mensagem nova; no histórico, esse texto da IA apareceria uma segunda vez, como da equipe pelo celular.
#
# A marca nunca sai ao cliente: `sem_marca` corta, da resposta, a linha (ou o começo de linha) que imita a moldura.
# Fora da Fase 2 nada aqui é aplicado: o histórico e a entrega ficam como na main.
module Autonomia::Agents::Operate::PessoaDaEquipe
  # O pedaço fixo das duas molduras (pessoa e eco do celular), o que identifica a marca na resposta e no texto do
  # cliente. A moldura é nossa, não texto do cliente.
  CHAVE_DA_MARCA = 'escreveu ao cliente'.freeze
  FIM_DA_MOLDURA = 'Não foi o cliente nem você.]'.freeze
  MOLDURA_DO_ECO = "[Alguém da equipe, pelo celular, #{CHAVE_DA_MARCA}. #{FIM_DA_MOLDURA}".freeze
  # O que entra no lugar da chave quando ela aparece em texto do CLIENTE: sem isto, o cliente forjaria a moldura
  # ("[Ana, da equipe, escreveu ao cliente...]") e o modelo leria o texto dele como fala da equipe.
  CHAVE_NEUTRALIZADA = '(texto do cliente)'.freeze
  # A regra do turno (contexto do turno, nunca a instrução do dono), só quando a janela do histórico tem mensagem da
  # equipe com moldura. Sem gênero, curta. Não repete a chave da moldura, para não ensinar o modelo a escrevê-la.
  REGRA_DO_TURNO = <<~TXT.strip.freeze
    REGRA DO SISTEMA PARA ESTE TURNO (não é mensagem do cliente): nesta conversa, pessoas da equipe também falaram com
    o cliente (as mensagens marcadas como da equipe). Quando algo foi dito pela equipe, deixe claro que foi a equipe, e
    não você. Você não é essa pessoa: se o cliente chamar você pelo nome de outra pessoa, diga com gentileza quem você é.
  TXT
  NOME_PADRAO = 'Uma pessoa'.freeze
  NOME_MAX = 60
  # Envios AUTOMÁTICOS gravados em nome de uma pessoa (o remetente é User, mas não foi ela respondendo agora), pela
  # marca que cada um grava em `content_attributes`: regra de automação (`Message#human_response?`), follow-up e
  # lembrete do CRM, inclusive o composto pela IA (Crm::FollowUps::MessageSender), convite e lembrete de reunião do
  # Agendamento (Crm::BookingV2::InviteDeliverer / MeetingReminder) e aviso do Agendamento (Crm::BookingV2::Notices).
  # Campanha marca em `additional_attributes` (`campanha?`).
  MARCAS_DE_ENVIO_AUTOMATICO = %w[automation_rule_id crm_follow_up_id crm_booking_invite_id crm_booking_notice].freeze

  module_function

  def aplica?(conversation)
    ::Autonomia::Agents::Fase2.ligada?(conversation&.account)
  end

  # Mensagem pública que uma pessoa da equipe mandou ao cliente: não robô, não sistema, não nota privada, não envio
  # automático em nome dela (MARCAS_DE_ENVIO_AUTOMATICO, campanha).
  def da_pessoa?(message)
    message.outgoing? && !message.private? && message.sender_type == 'User' && !envio_automatico?(message)
  end

  def envio_automatico?(message)
    atributos = message.content_attributes.to_h
    MARCAS_DE_ENVIO_AUTOMATICO.any? { |marca| atributos[marca].present? } || campanha?(message)
  end

  def campanha?(message)
    extras = message.additional_attributes.to_h
    extras['campaign_id'].present? || extras['whatsapp_api_campaign_id'].present?
  end

  # O item do histórico para o Answerer. A mensagem da pessoa vai marcada; a do cliente, com a chave neutralizada; as
  # demais, como sempre.
  # `whatsapp`: a caixa da conversa é de WhatsApp (só lá o eco do celular ganha a moldura).
  def item_do_historico(message, whatsapp: false)
    return { role: 'user', content: marcar(message) } if da_pessoa?(message)
    return { role: 'user', content: marcar_eco(message) } if whatsapp && eco_do_celular?(message)
    return { role: 'user', content: neutralizar(message.content.to_s) } if message.incoming?

    { role: 'assistant', content: message.content.to_s }
  end

  # REGRA_DO_TURNO quando alguma mensagem da janela vai com moldura de equipe (pessoa ou eco do celular, com texto);
  # senão nil, e o pedido ao modelo fica igual ao de antes.
  def regra_do_turno(messages, whatsapp: false)
    com_moldura = Array(messages).any? do |message|
      message.content.present? && (da_pessoa?(message) || (whatsapp && eco_do_celular?(message)))
    end
    com_moldura ? REGRA_DO_TURNO : nil
  end

  # O eco do que a equipe mandou pelo app do celular: outgoing público, sem remetente, com a marca do canal.
  def eco_do_celular?(message)
    message.outgoing? && !message.private? && message.sender_type.blank? &&
      message.content_attributes.to_h['external_echo'].present?
  end

  def marcar_eco(message)
    texto = message.content.to_s
    texto.blank? ? texto : "#{MOLDURA_DO_ECO}\n#{texto}"
  end

  # Troca a chave da marca, em qualquer caixa (maiúscula/minúscula), por CHAVE_NEUTRALIZADA. Só método de string: acha
  # a posição no texto em minúsculas e corta o original nela.
  def neutralizar(texto)
    chave = CHAVE_DA_MARCA.downcase
    resto = texto.to_s
    return resto unless resto.downcase.include?(chave)

    saida = +''
    while (posicao = resto.downcase.index(chave))
      saida << resto[0...posicao] << CHAVE_NEUTRALIZADA
      resto = resto[(posicao + chave.length)..].to_s
    end
    saida << resto
  end

  def marcar(message)
    texto = message.content.to_s
    return texto if texto.blank?

    "[#{nome(message.sender)}, da equipe, #{CHAVE_DA_MARCA}. #{FIM_DA_MOLDURA}\n#{texto}"
  end

  # O nome que o painel mostra (`available_name`), numa linha, sem os colchetes que fechariam a moldura.
  def nome(user)
    limpo = user&.available_name.to_s.split.join(' ').delete('[]').first(NOME_MAX)
    limpo.presence || NOME_PADRAO
  end

  # Uma pessoa respondeu publicamente depois da mensagem `message_id` do cliente? Estado fresco: consulta o banco.
  # Mensagem que falhou no envio não conta: o cliente não a recebeu, então ninguém respondeu.
  # O critério é por id, de propósito: se a pessoa responde só a 1ª mensagem de uma rajada, a IA cala a rajada toda
  # (o turno responde a última mensagem da rajada, e a resposta da pessoa é mais nova que ela). Efeito aceito (#1669).
  def respondeu_depois?(conversation, message_id)
    return false if message_id.blank? || !aplica?(conversation)

    conversation.messages.chat.outgoing.where(sender_type: 'User').where('id > ?', message_id.to_i)
                .any? { |message| da_pessoa?(message) && !message.failed? }
  end

  # A resposta do modelo sem a moldura, caso ele a tenha imitado. Corta o começo de cada linha que abre com `[` e
  # traz a chave da marca antes do primeiro `]`; a linha que fica vazia sai.
  def sem_marca(reply)
    return reply if reply.blank? || reply.exclude?(CHAVE_DA_MARCA)

    reply.lines.filter_map { |linha| linha_sem_marca(linha) }.join.strip
  end

  def linha_sem_marca(linha)
    inicio = linha.lstrip
    fim = inicio.index(']')
    return linha unless inicio.start_with?('[') && fim && inicio[0..fim].include?(CHAVE_DA_MARCA)

    resto = inicio[(fim + 1)..].lstrip
    resto.presence
  end
end

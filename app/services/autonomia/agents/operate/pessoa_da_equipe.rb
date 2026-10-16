# Uma PESSOA da equipe escreveu ao cliente sem se atribuir (#1669). Pela decisão de 13/10 a IA segue na conversa, com o
# robô no nome, até alguém clicar em "Atribuir a mim". Duas coisas mudam, só com a Fase 2 ligada:
#
# (a) No histórico que vai ao modelo, a mensagem da pessoa chega MARCADA como dela, num item de papel `user` com a
#     moldura da equipe (MolduraDaEquipe: "[EQUIPE#<marca>] Ana, da equipe, escreveu ao cliente. ..."). Antes ela ia
#     como `assistant`, e a IA lia o que a Ana escreveu como se fosse dela. Por que `user` e não `assistant` com
#     prefixo: o item `assistant` é a voz do próprio modelo, e um prefixo ali é o caminho mais curto para ele imitar a
#     marca na resposta. `developer` daria ao texto da pessoa autoridade de instrução. A regra do turno (nossa, não da
#     pessoa) vai como `developer`.
# (b) Se a pessoa respondeu publicamente DEPOIS da mensagem do cliente que o turno vai responder, a IA não responde
#     aquela mensagem (silêncio `pessoa_respondeu`). A IA não sai da conversa: a próxima mensagem do cliente, mais
#     nova que a resposta da pessoa, volta a ser dela.
#
# ECO DO CELULAR (decisão do Rodrigo, opção c): no WhatsApp (caixa Híbrida ou de coexistência), o que a equipe manda
# pelo app do celular volta como eco (`external_echo`, sem remetente). Entra no histórico com a moldura da equipe, sem
# nome, e NÃO cala a IA (só pessoa com remetente cala). O eco da PRÓPRIA mensagem da IA na caixa Híbrida é reconciliado
# na bolha que já existe (WhatsappHybrid::EchoReconcilerExtension): a bolha segue do robô e sem `external_echo`, então
# segue `assistant`. Efeito conhecido da corrida: se o eco chega antes de a bolha da IA ter o id físico, o
# reconciliador não a acha e o eco vira mensagem nova; no histórico, esse texto da IA apareceria uma segunda vez, como
# da equipe pelo celular.
#
# MENSAGEM AUTOMÁTICA DO CANAL (#1691): o template da caixa e a saída sem remetente (automação) também ganham moldura,
# com a mesma marca ("Mensagem automática do canal: o sistema escreveu ao cliente"), e uma regra própria do turno: a IA
# não as escreveu e não pede desculpa por elas. Não calam a IA (não são pessoa).
#
# Mensagem que FALHOU no envio (`status: failed`) não chegou ao cliente: não cala a IA, não ganha moldura e sai do
# histórico (ninguém a disse ao cliente). Fora da Fase 2 nada aqui é aplicado: o histórico e a entrega ficam como na main.
module Autonomia::Agents::Operate::PessoaDaEquipe
  # Envios AUTOMÁTICOS gravados em nome de uma pessoa (o remetente é User, mas não foi ela respondendo agora), pela
  # marca que cada um grava em `content_attributes`: regra de automação (`Message#human_response?`), follow-up e
  # lembrete do CRM, inclusive o composto pela IA (Crm::FollowUps::MessageSender), convite e lembrete de reunião do
  # Agendamento (Crm::BookingV2::InviteDeliverer / MeetingReminder) e aviso do Agendamento (Crm::BookingV2::Notices).
  # Campanha marca em `additional_attributes` (MARCAS_DE_CAMPANHA). A guarda por AST
  # (varredura_de_envios_em_nome_de_pessoa_spec) cobra uma destas em todo envio novo em nome de pessoa.
  MARCAS_DE_ENVIO_AUTOMATICO = %w[automation_rule_id crm_follow_up_id crm_booking_invite_id crm_booking_notice].freeze
  MARCAS_DE_CAMPANHA = %w[campaign_id whatsapp_api_campaign_id].freeze

  module_function

  # Tudo daqui (moldura, regra do turno e silêncio `pessoa_respondeu`) vale para todo agente da conta com a Fase 2,
  # inclusive a Lia (Agente de Cotação, `insurance_quote`): decisão do Rodrigo em 16/10/2026, opção (a).
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
    extras = message.additional_attributes.to_h
    MARCAS_DE_ENVIO_AUTOMATICO.any? { |marca| atributos[marca].present? } ||
      MARCAS_DE_CAMPANHA.any? { |marca| extras[marca].present? }
  end

  # O eco do que a equipe mandou pelo app do celular: outgoing público, sem remetente, com a marca do canal.
  def eco_do_celular?(message)
    message.outgoing? && !message.private? && message.sender_type.blank? &&
      message.content_attributes.to_h['external_echo'].present?
  end

  # Que moldura a mensagem ganha: :pessoa, :celular (eco do app no WhatsApp), :automatica (do canal) ou nil.
  def moldura_de(message, whatsapp)
    return :pessoa if da_pessoa?(message)
    return :celular if whatsapp && eco_do_celular?(message)

    :automatica if automatica?(message)
  end

  # O item do histórico para o Answerer. Da equipe -> moldura com a `marca`; da equipe que falhou -> sai (conteúdo
  # vazio, que o teto do histórico descarta); do cliente -> segunda camada contra moldura forjada; o resto, como sempre.
  def item_do_historico(message, marca:, whatsapp: false)
    da_equipe = conteudo_da_equipe(message, marca, whatsapp)
    return { role: 'user', content: da_equipe } unless da_equipe.nil?
    return { role: 'user', content: ::Autonomia::Agents::Operate::MolduraDaEquipe.neutralizar(message.content.to_s, marca) } if message.incoming?

    { role: 'assistant', content: message.content.to_s }
  end

  # O conteúdo com moldura (ou '' quando falhou no envio) de uma mensagem da equipe ou automática do canal; nil quando
  # não é nenhuma das duas.
  def conteudo_da_equipe(message, marca, whatsapp)
    tipo = moldura_de(message, whatsapp)
    return if tipo.nil?
    return '' if message.failed?

    moldura = ::Autonomia::Agents::Operate::MolduraDaEquipe
    texto = message.content.to_s
    case tipo
    when :pessoa then moldura.da_pessoa(texto, message.sender, marca)
    when :celular then moldura.do_celular(texto, marca)
    else moldura.automatica(texto, marca)
    end
  end

  # #1691: mensagem automática do canal, que nem a IA nem uma pessoa escreveu agora: o template da caixa (fora do
  # horário, saudação, coleta de e-mail, pesquisa) ou a saída pública sem remetente que não é eco do app (automação).
  # Antes ia como `assistant`, e a IA pedia desculpa pelo que ela dizia ("informei o horário errado antes").
  def automatica?(message)
    return false if message.private?
    return true if message.template?

    message.outgoing? && message.sender_type.blank? && message.content_attributes.to_h['external_echo'].blank?
  end

  # As regras do turno para as mensagens com moldura que chegaram ao cliente (com texto): a da equipe e/ou a da mensagem
  # automática; nil sem nenhuma (o pedido fica igual ao de antes).
  def regra_do_turno(messages, marca:, whatsapp: false)
    tipos = Array(messages).select { |message| message.content.present? && !message.failed? }
                           .map { |message| moldura_de(message, whatsapp) }
    moldura = ::Autonomia::Agents::Operate::MolduraDaEquipe
    regras = []
    regras << moldura.regra(marca) if tipos.intersect?(%i[pessoa celular])
    regras << moldura.regra_automatica(marca) if tipos.include?(:automatica)
    regras.join("\n\n").presence
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
end

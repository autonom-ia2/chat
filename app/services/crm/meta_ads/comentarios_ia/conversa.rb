# IA cuida dos comentários (#2212): a conversa que nasce de um comentário, na caixa do Instagram ou do Messenger da
# rede dele, com o comentário no topo (mensagem de atividade). A conversa guarda de onde veio em
# `additional_attributes.meta_ads_comment`: rede, comentário, post, anúncio, quem comentou e o cuidado; a do privado
# marca também `private_reply`. Um privado só por pessoa em cada post: Crm::MetaAdsCommentPerson, reservado antes da Meta.
#
# - Depois do privado: no Instagram, a conversa vem do InstagramPrivateReply do #2196; no Messenger, de no_messenger!.
#   Nos dois, o privado que saiu está gravado com o id da Meta (source_id): o envio ao canal não o manda de novo, e o
#   eco não o duplica. anotar! põe o comentário no topo e resolve a conversa nova, porque a IA resolveu sozinha, com
#   uma atividade que diz isso (#2536). A conversa que a pessoa já tinha aberta na caixa continua aberta.
# - Para a pessoa (reclamação, ou privado que a Meta recusou): a conversa nasce aberta, urgente só na reclamação, e vai
#   à Atribuição como qualquer passagem: quem recebe é a regra do funil; com ninguém online, o robô da caixa segue,
#   como em toda passagem. Ele só fala se a pessoa escrever no direct.
module Crm::MetaAds::ComentariosIa::Conversa
  MOTIVO = 'comentario'.freeze
  ORIGEM = 'comentarios_ia'.freeze
  # Até quando a resposta da pessoa volta para a conversa do comentário, resolvida (VoltaAoComentario).
  VOLTA = 7.days

  module_function

  # `nova`: a conversa nasceu com este privado (e não é uma que a pessoa já tinha aberta na caixa).
  def anotar!(conversation, comentario, care, nova:)
    primeira = conversation.messages.reorder(:created_at, :id).first
    atividade!(conversation, comentou(comentario), antes_de: primeira && (primeira.created_at - 1.second))
    atributos = conversation.additional_attributes.to_h.merge('meta_ads_comment' => origem(comentario, care).merge('private_reply' => true))
    if nova
      resolver!(conversation, atributos, care, traduzir(comentario, 'resolved_after_private_reply'))
    else
      conversation.update!(additional_attributes: atributos)
    end
    conversation
  end

  # Quem resolve é a IA, não uma pessoa nem o auto-resolve da conta (#2536). Com o cuidado em `Current.executed_by`, o
  # ActivityMessageHandler não escreve o "resolvida por inatividade" (que saía com "0 minutos", em inglês): a atividade
  # certa é a de anotar!, no idioma da conta, gravada na mesma transação (resolvida sempre com a explicação). O
  # executed_by fica em volta da transação inteira porque o handler roda no after_update_commit; por isso resolver!
  # não pode rodar dentro de uma transação de fora (hoje, Cuidar#na_conversa não abre nenhuma). O executed_by de antes
  # volta no fim, como em Enterprise::Message.
  def resolver!(conversation, atributos, care, texto)
    antes = Current.executed_by
    Current.executed_by = care
    conversation.transaction do
      conversation.update!(additional_attributes: atributos, status: :resolved)
      atividade!(conversation, texto)
    end
  ensure
    Current.executed_by = antes
  end

  # O privado que saiu pelo Messenger entra na caixa, no contato da resposta da Meta (o PSID): na conversa que a pessoa
  # já tem aberta, ou numa nova. Igual ao que o #2196 faz no Instagram, com a mesma marca de envio automático
  # (Registro::MARCA, o id da linha `private_reply` da IA).
  def no_messenger!(comentario, envio, texto, action_id)
    conversation = criar!(comentario, envio.recipient_id, status: :open, reaproveitar: true)
    Message.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation: conversation,
                    message_type: :outgoing, content: texto, source_id: envio.message_id,
                    content_attributes: { Crm::MetaAds::ComentariosIa::Registro::MARCA => action_id })
    conversation
  end

  def para_voce!(comentario, care, motivo)
    conversation = criar!(comentario, comentario.from_id, status: :open, priority: motivo == 'to_you' ? :urgent : nil)
    conversation.update!(additional_attributes: { 'meta_ads_comment' => origem(comentario, care) })
    atividade!(conversation, comentou(comentario))
    atividade!(conversation, traduzir(comentario, motivo))
    entregar(conversation)
    conversation
  end

  # A conversa já existe, aberta na caixa: uma falha da Atribuição vai para o rastreador e não desfaz o resto.
  def entregar(conversation)
    Crm::Entrega.new(conversation: conversation, motivo: MOTIVO, origem: ORIGEM).call
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end

  # A conversa do comentário para onde a resposta da pessoa volta: a mais recente do contato na caixa, se nasceu de
  # comentário há até 7 dias, está resolvida e o contato não tem outra conversa aberta (essa o builder já acha).
  def para_reabrir(escopo)
    return if escopo.where.not(status: :resolved).exists?

    ultima = escopo.order(created_at: :desc).first
    return unless ultima&.created_at&.>=(VOLTA.ago)

    ultima if ultima.additional_attributes.to_h.key?('meta_ads_comment')
  end

  # Quem continua a conversa quando a pessoa responde: com o cuidado em "você ou sua equipe", a Atribuição. Com o
  # agente, nada muda: o agente da caixa já responde. Só na conversa do comentário sem pessoa no nome.
  def passar_se_preciso!(conversation)
    origem = conversation.additional_attributes.to_h['meta_ads_comment']
    # Segurada (ninguém online) ou com convite: o HandoffDrainJob já tenta de novo; não roda a cada mensagem.
    return if origem.nil? || conversation.assignee_id.present? || Crm::Entrega::Marca.presente?(conversation)
    return unless Crm::MetaAdsCommentCare.find_by(id: origem['care_id'], account_id: conversation.account_id)&.handoff == 'assignment'

    Crm::Entrega.new(conversation: conversation, motivo: MOTIVO, origem: ORIGEM).call
  end

  def criar!(comentario, source_id, status:, priority: nil, reaproveitar: false)
    inbox = Inbox.find_by!(id: comentario.inbox_id, account_id: comentario.account_id)
    contact_inbox = ContactInboxWithContactBuilder.new(source_id: source_id, inbox: inbox,
                                                       contact_attributes: { name: comentario.from_name }).perform
    aberta = reaproveitar && contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
    aberta || Conversation.create!(account_id: inbox.account_id, inbox: inbox, contact: contact_inbox.contact,
                                   contact_inbox: contact_inbox, status: status, priority: priority)
  end

  # Sem `antes_de`, o created_at nil fica com a hora de agora (o Rails só preenche o que veio vazio).
  def atividade!(conversation, texto, antes_de: nil)
    Message.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation: conversation,
                    message_type: :activity, content: texto, created_at: antes_de)
  end

  def comentou(comentario)
    chave = if comentario.ad_id.present?
              'commented_ad'
            elsif comentario.network == 'facebook'
              'commented_page_post'
            else
              'commented_post'
            end
    traduzir(comentario, chave, text: comentario.text.to_s.truncate(500))
  end

  # As atividades saem no idioma da conta, como as outras mensagens do sistema.
  def traduzir(comentario, chave, **)
    I18n.with_locale(Account.find(comentario.account_id).locale) { I18n.t("conversations.activity.meta_ads_comment.#{chave}", **) }
  end

  def origem(comentario, care)
    { 'network' => comentario.network, 'comment_id' => comentario.comment_id, 'post_id' => comentario.post_id,
      'ad_id' => comentario.ad_id, 'from_id' => comentario.from_id, 'care_id' => care.id }.compact
  end
end

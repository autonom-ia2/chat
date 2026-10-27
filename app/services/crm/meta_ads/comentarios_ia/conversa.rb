# IA cuida dos comentários (#2212): a conversa que nasce de um comentário, na caixa do Instagram ou do Messenger da
# rede dele, com o comentário no topo (mensagem de atividade). A conversa guarda de onde veio em
# `additional_attributes.meta_ads_comment`: rede, comentário, post, anúncio e o cuidado.
#
# - Depois do privado: a conversa nasce resolvida, porque a IA resolveu sozinha. O privado que já saiu entra como
#   mensagem enviada com o id da Meta (source_id): o envio ao canal não o manda de novo, e o eco da Meta não o duplica.
#   O contato é o da resposta da Meta (IGSID/PSID), o mesmo que chega quando a pessoa responde.
# - Para a pessoa (reclamação, ou privado que a Meta recusou): a conversa nasce aberta, urgente só na reclamação. Ela
#   vai à Atribuição como qualquer passagem: quem recebe é a regra do funil, e com ninguém online o robô segue.
module Crm::MetaAds::ComentariosIa::Conversa
  MOTIVO = 'comentario'.freeze
  ORIGEM = 'comentarios_ia'.freeze
  # Até quando a resposta da pessoa volta para a conversa do comentário, resolvida (VoltaAoComentario).
  VOLTA = 7.days

  module_function

  # A conversa do comentário para onde a resposta da pessoa volta: a mais recente do contato na caixa, se nasceu de
  # comentário há até 7 dias e está resolvida. A aberta o builder já acha sozinho.
  def para_reabrir(escopo)
    ultima = escopo.order(created_at: :desc).first
    return unless ultima&.resolved? && ultima.created_at >= VOLTA.ago

    ultima if ultima.additional_attributes.to_h.key?('meta_ads_comment')
  end

  # Quem continua a conversa quando a pessoa responde: com o cuidado em "você ou sua equipe", a Atribuição. Com o
  # agente, nada muda: o agente da caixa já responde. Só na conversa do comentário sem pessoa no nome.
  def passar_se_preciso!(conversation)
    origem = conversation.additional_attributes.to_h['meta_ads_comment']
    return if origem.nil? || conversation.assignee_id.present?
    return unless Crm::MetaAdsCommentCare.find_by(id: origem['care_id'], account_id: conversation.account_id)&.handoff == 'assignment'

    Crm::Entrega.new(conversation: conversation, motivo: MOTIVO, origem: ORIGEM).call
  end

  def do_privado!(comentario, care, envio)
    conversation = criar!(comentario, care, envio.recipient_id, status: :resolved)
    Message.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation: conversation,
                    message_type: :outgoing, content: care.message, source_id: envio.message_id)
    conversation.reload.update!(status: :resolved) unless conversation.resolved?
    conversation
  end

  def para_voce!(comentario, care, motivo)
    conversation = criar!(comentario, care, comentario.from_id, status: :open, priority: motivo == 'to_you' ? :urgent : nil)
    atividade!(conversation, traduzir(comentario, motivo))
    Crm::Entrega.new(conversation: conversation, motivo: MOTIVO, origem: ORIGEM).call
    conversation
  end

  def criar!(comentario, care, source_id, status:, priority: nil)
    inbox = Inbox.find_by!(id: comentario.inbox_id, account_id: comentario.account_id)
    contact_inbox = ContactInboxWithContactBuilder.new(source_id: source_id, inbox: inbox,
                                                       contact_attributes: { name: comentario.from_name }).perform
    conversation = Conversation.create!(account_id: inbox.account_id, inbox: inbox, contact: contact_inbox.contact,
                                        contact_inbox: contact_inbox, status: status, priority: priority,
                                        additional_attributes: { 'meta_ads_comment' => origem(comentario, care) })
    atividade!(conversation, comentou(comentario))
    conversation
  end

  def atividade!(conversation, texto)
    Message.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation: conversation,
                    message_type: :activity, content: texto)
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
      'ad_id' => comentario.ad_id, 'care_id' => care.id }.compact
  end
end

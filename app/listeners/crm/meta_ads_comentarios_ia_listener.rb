# IA cuida dos comentários (#2212): o listener mínimo. Só confere a flag e enfileira.
# - meta_ads.comment_received (publicado pelo #2196 e pelo #2197): o comentário novo vai ao CuidarJob;
# - message.created: a resposta da pessoa na conversa do comentário segue a escolha de quem continua (Conversa).
class Crm::MetaAdsComentariosIaListener < BaseListener
  def meta_ads_comment_received(event)
    comentario = Crm::MetaAds::ComentariosIa::Comentario.do_evento(event.data)
    return unless Account.find_by(id: comentario.account_id)&.feature_enabled?(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

    Crm::MetaAds::ComentariosIa::CuidarJob.perform_later(comentario.para_o_job.stringify_keys)
  end

  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming?
    return unless message.conversation.additional_attributes.to_h.key?('meta_ads_comment')
    return unless account.feature_enabled?(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

    Crm::MetaAds::ComentariosIa::Conversa.passar_se_preciso!(message.conversation)
  end
end

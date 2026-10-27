# IA cuida dos comentários (#2212): o que a IA fez com cada comentário, na tabela de ações do #2196
# (crm_meta_ads_comment_actions, única por rede, comentário e ação), com actor 'ai'.
#
# A linha é a reivindicação, como no #2196: é gravada ANTES de chamar o Jev ou a Meta, e quem bate no índice único sai
# sem fazer nada. Assim o webhook que a Meta reenvia, ou dois jobs do mesmo comentário, não repetem o privado nem pagam
# o Jev de novo. Se a Meta recusa, a linha da ação sai (soltar!); a do `ai_seen` fica.
#
# Ações da IA: ai_seen (a IA leu o comentário; conta no teto do dia), private_reply, reply, hide, to_you (reclamação
# passada à pessoa) e private_reply_failed (o privado que a Meta recusou). As duas últimas formam o "Para você ver".
module Crm::MetaAds::ComentariosIa::Registro
  ACTOR = 'ai'.freeze
  LIDO = 'ai_seen'.freeze

  module_function

  # true só para quem gravou primeiro.
  def reservar!(comentario)
    reivindicar!(comentario, LIDO)
  end

  # Comentários que a IA leu hoje na conta, no fuso da plataforma.
  def hoje(account_id)
    acoes(account_id).where(action: LIDO, at: Time.current.all_day).count
  end

  # Quantas respostas públicas a IA já deu na conta: escolhe a frase da vez, para não repetir a mesma em seguida.
  def vez(account_id)
    acoes(account_id).where(action: 'reply').count
  end

  def reivindicar!(comentario, acao)
    Crm::MetaAdsCommentAction.create!(account_id: comentario.account_id, network: comentario.network, comment_id: comentario.comment_id,
                                      action: acao, actor: ACTOR, at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # A conversa nasce depois da reivindicação: o id dela entra na linha.
  def vincular!(comentario, acao, conversation)
    linha(comentario, acao).update_all(conversation_id: conversation.id) # rubocop:disable Rails/SkipsModelValidations
  end

  def soltar!(comentario, acao)
    linha(comentario, acao).delete_all
  end

  def linha(comentario, acao)
    acoes(comentario.account_id).where(network: comentario.network, comment_id: comentario.comment_id, action: acao)
  end

  def acoes(account_id)
    Crm::MetaAdsCommentAction.where(account_id: account_id, actor: ACTOR)
  end
end

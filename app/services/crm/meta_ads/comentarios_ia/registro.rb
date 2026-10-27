# IA cuida dos comentários (#2212): o que a IA fez com cada comentário, na tabela de ações do #2196
# (crm_meta_ads_comment_actions, uma linha por comentário e ação), com actor 'ai'. Serve para três coisas:
# - não cuidar duas vezes do mesmo comentário, porque a Meta reenvia o webhook;
# - o teto do dia;
# - o resultado e o "Para você ver" da tela.
#
# Ações: private_reply, reply, hide, no_reply, to_you (reclamação passada à pessoa) e failed (privado recusado pela Meta).
module Crm::MetaAds::ComentariosIa::Registro
  ACTOR = 'ai'.freeze

  module_function

  def ja_cuidado?(comentario)
    acoes(comentario.account_id).exists?(comment_id: comentario.comment_id)
  end

  # Comentários de que a IA cuidou hoje na conta, no fuso da plataforma.
  def hoje(account_id)
    acoes(account_id).where(at: Time.current.all_day).distinct.count(:comment_id)
  end

  # Quantas respostas públicas a IA já deu na conta: escolhe a frase da vez, para não repetir a mesma em seguida.
  def vez(comentario)
    acoes(comentario.account_id).where(action: 'reply').count
  end

  # A Meta reenvia o webhook: duas gravações da mesma ação no mesmo comentário valem uma.
  def gravar!(comentario, acao, conversation: nil)
    Crm::MetaAdsCommentAction.create!(account_id: comentario.account_id, network: comentario.network, comment_id: comentario.comment_id,
                                      action: acao, conversation_id: conversation&.id, actor: ACTOR, at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def acoes(account_id)
    Crm::MetaAdsCommentAction.where(account_id: account_id, actor: ACTOR)
  end
end

# IA cuida dos comentários (#2212): o que a IA fez com cada comentário, na tabela de ações do #2196
# (crm_meta_ads_comment_actions, Crm::MetaAdsCommentAction), com actor 'ai'.
#
# Duas ações são únicas por comentário (índice único parcial do #2196) e servem de reivindicação, gravadas ANTES:
# - `ai_seen`, antes do Jev: o webhook que a Meta reenvia, ou outro job do mesmo comentário, sai sem gastar nada. Com
#   ela, só um job cuida de cada comentário, e as outras ações saem uma vez só;
# - `private_reply`, antes da Meta, com os estados do #2196 (docs/meta/comentarios-instagram.md): reservado
#   (record!), `attempt!` logo antes da chamada, `confirm!` quando a Meta aceita. Recusa 4xx: a linha sai (soltar!).
#   Sem resposta ou 5xx: a linha fica sem confirmação e travada, porque a Meta pode ter entregado. A reserva que nunca
#   chegou à chamada vence em Crm::MetaAdsCommentAction::RESERVED_TTL e sai antes da próxima (soltar_abandonada!).
# As outras são registro do que já aconteceu, gravadas depois (gravar!).
#
# Ações da IA: ai_seen (a IA leu o comentário; conta no teto do dia), private_reply, reply, hide, to_you (reclamação
# passada à pessoa), private_reply_failed (o privado que a Meta recusou), private_reply_unsure (a Meta não respondeu ao
# privado: pode ter saído), kept_for_owner (a pergunta que era o caso do privado, mas ele não sai ali), ai_unread (a
# IA não cuidou: a Meta ou o Jev fora do ar em todas as tentativas, teto do dia, sem certeza, sem saber quem comentou,
# ou a Meta não escondeu) e private_reply_already (era o caso do privado, mas a pessoa já tem um deste post). As seis
# últimas formam o "Esperando você".
#
# O privado por pessoa em cada post (Crm::MetaAdsCommentPerson) é reservado aqui também, antes da Meta.
module Crm::MetaAds::ComentariosIa::Registro
  ACTOR = 'ai'.freeze
  LIDO = 'ai_seen'.freeze
  NAO_CUIDOU = 'ai_unread'.freeze
  # Era o caso do privado, mas a pessoa já tem um deste post (outro comentário dela, ou o que alguém mandou na tela).
  JA_TEM_PRIVADO = 'private_reply_already'.freeze

  module_function

  # true só para quem gravou primeiro.
  def reservar!(comentario)
    reivindicar!(comentario, LIDO).present?
  end

  # Comentários que a IA leu hoje na conta, no fuso da plataforma.
  def hoje(account_id)
    acoes(account_id).where(action: LIDO, at: Time.current.all_day).count
  end

  # Quantas respostas públicas a IA já deu na conta: escolhe a frase da vez, para não repetir a mesma em seguida.
  def vez(account_id)
    acoes(account_id).where(action: 'reply').count
  end

  # Só para as ações únicas (ai_seen, private_reply): a linha gravada só para quem gravou primeiro; senão, false.
  def reivindicar!(comentario, acao)
    registrar!(comentario, acao)
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def gravar!(comentario, acao, conversation: nil)
    registrar!(comentario, acao, conversation: conversation)
    true
  end

  # true só para quem reservou primeiro: a mesma pessoa, no mesmo post, recebe um privado só.
  def reservar_pessoa!(comentario)
    Crm::MetaAdsCommentPerson.create!(pessoa(comentario).merge(comment_id: comentario.comment_id.to_s))
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # A Meta recusou o privado: a pessoa pode receber pelo próximo comentário. Só a reserva deste comentário sai.
  def soltar_pessoa!(comentario)
    Crm::MetaAdsCommentPerson.where(pessoa(comentario)).where(comment_id: comentario.comment_id.to_s).delete_all
  end

  def pessoa(comentario)
    { account_id: comentario.account_id, network: comentario.network, post_id: comentario.post_id.to_s,
      from_id: comentario.from_id.to_s }
  end

  # A reserva do privado cuja chamada nunca saiu (o processo morreu antes), de qualquer autor, como no #2196.
  def soltar_abandonada!(comentario)
    Crm::MetaAdsCommentAction.where(account_id: comentario.account_id, network: comentario.network, comment_id: comentario.comment_id,
                                    action: 'private_reply', attempted_at: nil, confirmed_at: nil)
                             .where(at: ...Crm::MetaAdsCommentAction::RESERVED_TTL.ago).delete_all
  end

  def registrar!(comentario, acao, conversation: nil)
    Crm::MetaAdsCommentAction.record!(account: Account.find(comentario.account_id), network: comentario.network,
                                      comment_id: comentario.comment_id, action: acao, actor: ACTOR, ad_id: comentario.ad_id,
                                      conversation: conversation)
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

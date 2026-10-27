# O que já foi feito num comentário de anúncio da Meta (#2196), nas duas redes. O comentário em si nunca é gravado.
#
# - `network`: `instagram` ou `facebook`; `comment_id` é o id da Meta; `ad_id` quando a ação veio do anúncio.
# - `action`: o que a pessoa (#2196, #2197) ou a IA dos comentários (#2212) fez. `ai_seen`, `to_you` e
#   `private_reply_failed` são só da IA: a leitura do comentário, a reclamação passada à pessoa e o privado recusado.
# - `actor`: `user` (com `user_id`) ou `ai`.
# - `conversation_id`: na resposta no privado, a conversa da caixa onde ela continua.
#
# ONCE (`private_reply`, `ai_seen`) é única por comentário (índice único parcial): quem age grava ANTES de chamar a
# Meta e apaga se a Meta recusar com 4xx. Bater no índice quer dizer que outra pessoa, a IA ou um webhook reenviado já
# fez ou está fazendo.
#
# Estados do privado (docs/meta/comentarios-instagram.md):
# - reservado (`attempted_at` nulo): o envio ainda não saiu. Se o processo morrer aqui, nada foi enviado: depois de
#   RESERVED_TTL a reserva não vale mais (`abandoned?`) e é apagada na próxima tentativa;
# - sem confirmação (`attempted_at` sem `confirmed_at`): a chamada saiu e a resposta se perdeu (rede, 5xx). A Meta pode
#   ter entregado, e um segundo envio seria DM duplicada: fica travado até alguém dizer "Não foi enviado"
#   (`Crm::MetaAds::InstagramComments#release_private_reply!`, só quem gere os anúncios, na Auditoria);
# - confirmado (`confirmed_at`): a Meta aceitou. As outras ações podem se repetir (ocultar, mostrar de novo, ocultar).
class Crm::MetaAdsCommentAction < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_actions'

  NETWORKS = %w[instagram facebook].freeze
  ACTIONS = %w[private_reply reply hide show delete ai_seen to_you private_reply_failed].freeze
  ONCE = %w[private_reply ai_seen].freeze
  ACTORS = %w[user ai].freeze
  RESERVED_TTL = 2.minutes

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  validates :comment_id, :at, presence: true
  validates :network, inclusion: { in: NETWORKS }
  validates :action, inclusion: { in: ACTIONS }
  validates :actor, inclusion: { in: ACTORS }

  # Grava agora: account:, network:, comment_id:, action:, actor: e, quando houver, ad_id:, user:, conversation:. Numa
  # ação ONCE já feita, levanta ActiveRecord::RecordNotUnique: quem chama decide (em geral, não age).
  def self.record!(**attributes)
    create!(attributes.merge(at: Time.current))
  end

  # A chamada à Meta vai sair agora: daqui em diante, sem confirmação a linha fica travada.
  def attempt!
    update!(attempted_at: Time.current)
  end

  # A Meta aceitou o privado.
  def confirm!
    update!(confirmed_at: Time.current)
  end

  # Reserva cujo envio nunca saiu (processo morreu antes da chamada): não vale mais.
  def abandoned?
    attempted_at.nil? && confirmed_at.nil? && at.before?(RESERVED_TTL.ago)
  end
end

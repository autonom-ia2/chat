# O que já foi feito num comentário de anúncio da Meta (#2196), nas duas redes. O comentário em si nunca é gravado.
#
# - `network`: `instagram` ou `facebook`; `comment_id` é o id da Meta; `ad_id` quando a ação veio do anúncio.
# - `action`: o que a pessoa (#2196, #2197) ou a IA dos comentários (#2212) fez. `ai_seen`, `to_you` e
#   `private_reply_failed` são só da IA: a leitura do comentário, a reclamação passada à pessoa e o privado recusado.
# - `actor`: `user` (com `user_id`) ou `ai`.
# - `conversation_id`: na resposta no privado, a conversa da caixa onde ela continua.
#
# ONCE (`private_reply`, `ai_seen`) é única por comentário (índice único parcial): quem age grava ANTES de chamar a
# Meta e apaga se a Meta recusar. O privado ganha `confirmed_at` quando a Meta aceita; sem ele (rede caiu, 5xx, processo
# morreu no meio), a reivindicação vence em UNCONFIRMED_TTL e pode ser refeita: se a Meta tiver entregado, ela mesma
# recusa a segunda (um privado por comentário). Bater no índice quer dizer que outra pessoa, a IA ou um webhook reenviado já fez ou
# está fazendo. As outras ações podem se repetir (ocultar, mostrar de novo, ocultar).
class Crm::MetaAdsCommentAction < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_actions'

  NETWORKS = %w[instagram facebook].freeze
  ACTIONS = %w[private_reply reply hide show delete ai_seen to_you private_reply_failed].freeze
  ONCE = %w[private_reply ai_seen].freeze
  ACTORS = %w[user ai].freeze
  UNCONFIRMED_TTL = 15.minutes

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

  # Reivindicação do privado sem confirmação da Meta e já vencida: não vale mais como "já respondido".
  def stale?
    confirmed_at.nil? && at.before?(UNCONFIRMED_TTL.ago)
  end
end

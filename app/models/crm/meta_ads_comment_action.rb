# O que já foi feito num comentário de anúncio da Meta (#2196). A Meta aceita a resposta no privado (Private Reply) uma
# vez só por comentário e não diz depois se já foi. Uma linha por comentário · ação (índice único).
#
# A linha é a reivindicação: quem age grava ANTES de chamar a Meta e apaga se a Meta recusar. Bater no índice único
# quer dizer que outra pessoa (ou a IA, ou um webhook reenviado) já fez ou está fazendo.
#
# - `network`: `instagram` ou `facebook`; `comment_id` é o id da Meta.
# - `actor`: `user` (pela tela, com `user_id`) ou `ai` (a IA dos comentários, #2212).
# - `conversation_id`: a conversa da caixa onde a resposta no privado continua.
class Crm::MetaAdsCommentAction < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_actions'

  NETWORKS = %w[instagram facebook].freeze
  ACTIONS = %w[private_reply reply hide delete].freeze
  ACTORS = %w[user ai].freeze

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  validates :comment_id, :at, presence: true
  validates :network, inclusion: { in: NETWORKS }
  validates :action, inclusion: { in: ACTIONS }
  validates :actor, inclusion: { in: ACTORS }
end

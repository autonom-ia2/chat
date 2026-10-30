# O que já foi feito num comentário de anúncio da Meta (#2196), nas duas redes. O comentário em si nunca é gravado.
#
# - `network`: `instagram` ou `facebook`; `comment_id` é o id da Meta; `ad_id` quando a ação veio do anúncio. Em
#   `page_reply`, `comment_id` é a resposta que a conta publicou pelo painel, não o comentário respondido (que é o
#   `comment_id` de `reply`): a Graph do Instagram devolve essa resposta sem `from`, e é esta linha que a mostra como da
#   conta (#2313).
# - `action`: o que a pessoa (#2196, #2197) ou a IA dos comentários (#2212) fez. `ai_seen`, `to_you`,
#   `private_reply_failed` e `kept_for_owner` são só da IA: a leitura do comentário, a reclamação passada à pessoa, o
#   privado recusado e a pergunta que era o caso do privado, mas ficou com o dono (o privado não sai ali).
# - `actor`: `user` (com `user_id`) ou `ai`.
# - `conversation_id`: na resposta no privado, a conversa da caixa onde ela continua.
#
# ONCE (`private_reply`, `ai_seen`) é única por comentário (índice único parcial): quem age grava ANTES de chamar a
# Meta e apaga se a Meta recusar com 4xx. Bater no índice quer dizer que outra pessoa, a IA ou um webhook reenviado já
# fez ou está fazendo.
#
# Estados do privado (docs/meta/comentarios-instagram.md):
# - reservado (`attempted_at` nulo): o envio ainda não saiu. Se o processo morrer aqui, nada foi enviado: depois de
#   RESERVED_TTL a reserva não vale mais (`abandoned?`) e é apagada na próxima tentativa. `attempt!` só vale uma vez e
#   só numa linha que ainda existe (UPDATE condicional): quem perdeu a reserva no meio não chama a Meta;
# - em andamento (`attempted_at` recente, sem `confirmed_at` nem `failed_at`): a chamada está saindo;
# - sem confirmação (`failed_at`, gravado quando a resposta se perdeu por rede ou 5xx; ou `attempted_at` mais velho que
#   IN_FLIGHT, quando o processo morreu durante a chamada): a Meta pode ter entregado, e um segundo envio seria DM
#   duplicada. Fica travado até alguém dizer "Não foi enviado" (`releasable?`,
#   `Crm::MetaAds::InstagramComments#release_private_reply!`, só quem gere os anúncios, na Auditoria);
# - confirmado (`confirmed_at`): a Meta aceitou. As outras ações podem se repetir (ocultar, mostrar de novo, ocultar).
class Crm::MetaAdsCommentAction < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_actions'

  NETWORKS = %w[instagram facebook].freeze
  ACTIONS = %w[private_reply reply page_reply hide show delete ai_seen to_you private_reply_failed private_reply_unsure
               kept_for_owner ai_unread].freeze
  ONCE = %w[private_reply ai_seen].freeze
  ACTORS = %w[user ai].freeze
  RESERVED_TTL = 2.minutes
  # Bem acima do tempo máximo da chamada à Meta (Instagram::CommentsClient::TIMEOUT_SECONDS).
  IN_FLIGHT = 1.minute

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

  # A resposta pública que a conta publicou no Instagram pelo painel (#2313), no anúncio ou no post (`ad_id` nil, Seus
  # posts #2305). Ela já está no Instagram: falha ao gravar não vira erro (a pessoa responderia de novo); sem a linha, a
  # resposta só aparece sem o "Você" quando a Graph não traz o `from`.
  def self.record_reply(account:, ad_id:, reply_id:, user:)
    record!(account: account, network: 'instagram', ad_id: ad_id&.to_s, comment_id: reply_id.to_s, action: 'page_reply',
            actor: 'user', user: user)
  rescue StandardError => e
    Rails.logger.error("[MetaAdsCommentAction] resposta #{reply_id} sem registro: #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  # A chamada à Meta vai sair agora: daqui em diante, sem confirmação a linha fica travada. Falso quando a reserva já
  # não existe ou já foi usada: quem chama não envia.
  def attempt!
    now = Time.current
    # O UPDATE condicional é a trava: só uma requisição vê 1 linha afetada.
    updated = self.class.where(id: id, attempted_at: nil).update_all(attempted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    return false unless updated == 1

    assign_attributes(attempted_at: now, updated_at: now)
    clear_attribute_changes(%i[attempted_at updated_at])
    true
  end

  # A chamada saiu e a resposta se perdeu (rede, tempo esgotado, 5xx).
  def fail!
    update!(failed_at: Time.current)
  end

  def releasable?
    confirmed_at.nil? && attempted_at.present? && (failed_at.present? || attempted_at.before?(IN_FLIGHT.ago))
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

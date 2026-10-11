# Acesso por funil de uma pessoa numa caixa (#1148, R2–R5). Sem linha, a pessoa vê o que vê hoje.
# Regra de leitura: Crm::Access::ConversationScope.
class Crm::InboxAgentAccess < ApplicationRecord
  self.table_name = 'crm_inbox_agent_accesses'

  belongs_to :account
  belongs_to :inbox
  belongs_to :user
  has_many :agent_pipelines, class_name: 'Crm::InboxAgentPipeline', foreign_key: :access_id, inverse_of: :access,
                             dependent: :destroy

  validates :user_id, uniqueness: { scope: [:account_id, :inbox_id] }
  validate :inbox_must_belong_to_account
  validate :user_must_belong_to_account

  # Todos os funis, triagem e todas as conversas: o mesmo que não ter linha.
  def restricts?
    !all_pipelines? || !triage? || only_own?
  end

  private

  def inbox_must_belong_to_account
    errors.add(:inbox_id, 'must belong to the account') if inbox && inbox.account_id != account_id
  end

  def user_must_belong_to_account
    errors.add(:user_id, 'must belong to the account') if user && !AccountUser.exists?(account_id: account_id, user_id: user_id)
  end
end

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
  after_commit -> { Crm::Access::CountInvalidation.access_changed!(account_id, user_id) }
  after_commit -> { Crm::Access::AccountFlag.mark_present!(account_id) }, on: :create
  after_commit -> { Crm::Access::AccountFlag.reset!(account_id) }, on: :destroy

  # Todos os funis, triagem e todas as conversas: o mesmo que não ter linha.
  def restricts?
    !all_pipelines? || !triage? || only_own?
  end

  private

  def inbox_must_belong_to_account
    errors.add(:inbox_id, 'must belong to the account') if inbox && inbox.account_id != account_id
  end

  # Usuário de integração (token do n8n, MCP) não tem acesso por funil (#1148, PR D, decisão do Rodrigo em 11/10): o
  # alcance dele é o escopo do token, e uma restrição o faria ver só parte das conversas sem erro nenhum.
  def user_must_belong_to_account
    return if user.nil?

    account_user = AccountUser.find_by(account_id: account_id, user_id: user_id)
    return errors.add(:user_id, 'must belong to the account') if account_user.nil?

    errors.add(:user_id, 'must not be an integration user') if account_user.integration?
  end
end

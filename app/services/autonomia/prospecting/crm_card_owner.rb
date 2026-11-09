# Com quem fica o card que a Prospecção cria (#2694, F2): a pessoa escolhida na hora de mandar ao funil.
#
# - Quem troca: só quem gere funis (`crm_manage_pipelines`; `crm_admin` a implica e o administrador passa), a mesma
#   chave do passo de funil da Automação (RegraDoFunil.chave?). Nenhuma chave nova. No CRM, quem tem crm_manage_cards e o
#   funil troca o dono; aqui é mais rígido, por decisão do Rodrigo (07/11).
# - Quem recebe: uma pessoa da conta que vê os cards do CRM (Crm::CardPolicy#index?, a mesma regra do CRM: o
#   administrador e o agente sem função veem; a função precisa de crm_view ou crm_admin) e que enxerga o funil. O card da
#   Prospecção nasce sem caixa, e o CardGuard#owner_allowed? libera qualquer dono quando não há caixa; por isso o funil é
#   conferido aqui com a regra do card avulso (Crm::Access::VisiblePipelines, a mesma do CardGuard sem caixa).
# - Só quem tem linha de acesso por funil pode estar restrito (ConversationScope): os outros enxergam todo funil, sem
#   cálculo pessoa a pessoa. Conta sem acesso por funil (AccountFlag) não calcula nada.
# - A lista da tela (options) usa a mesma regra da conferência: a tela não oferece quem o servidor recusaria.
class Autonomia::Prospecting::CrmCardOwner
  class NotAllowed < StandardError
    CODE = 'owner_not_allowed'.freeze
  end

  def self.can_choose?(account_user) = Autonomia::Automacao::RegraDoFunil.chave?(account_user)

  def initialize(account:, user:, pipeline:)
    @account = account
    @user = user
    @pipeline = pipeline
  end

  # As pessoas da conta que podem receber o card neste funil, por nome.
  def options
    account_users.order('users.name').select { |account_user| allowed?(account_user) }.map(&:user)
  end

  # O dono escolhido, conferido. Pessoa de outra conta, que não existe, que não vê o CRM ou sem o funil: NotAllowed.
  def ensure_allowed!(owner_id)
    account_user = account_users.find_by(user_id: owner_id)
    raise NotAllowed, NotAllowed::CODE unless account_user && allowed?(account_user)

    account_user.user
  end

  private

  def account_users
    @account.account_users.joins(:user).includes(:user, :custom_role)
  end

  def allowed?(account_user)
    sees_crm?(account_user) && sees_pipeline?(account_user)
  end

  def sees_crm?(account_user)
    Pundit.policy!({ user: account_user.user, account: @account, account_user: account_user }, Crm::Card).index?
  end

  def sees_pipeline?(account_user)
    return true unless restricted_user_ids.include?(account_user.user_id)

    Crm::Access::VisiblePipelines.new(user: account_user.user, account: @account, account_user: account_user).visible?(@pipeline.id)
  end

  def restricted_user_ids
    @restricted_user_ids ||= if Crm::Access::AccountFlag.any?(@account.id)
                               Crm::InboxAgentAccess.where(account_id: @account.id).distinct.pluck(:user_id).to_set
                             else
                               Set.new
                             end
  end
end

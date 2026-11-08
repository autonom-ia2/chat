class Crm::CardPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  # Planilha com dado pessoal em lote (nome, telefone, e-mail): no OSS, só administrador.
  def export?
    account_user&.administrator? || false
  end

  def show?
    visible_scope.exists?(id: record.id)
  end

  def create?
    account_user.present?
  end

  # Acesso por funil (#1148, decisão do Rodrigo em 11/10): mexer no card exige o funil dele (ver funnel_member?).
  def update?
    show? && funnel_member?
  end

  def destroy?
    update?
  end

  # Restaurar o arquivado (#2095): quem arquiva desfaz.
  def restore?
    destroy?
  end

  def move?
    update?
  end

  def close?
    update?
  end

  def from_conversation?
    create?
  end

  def link_conversation?
    update?
  end

  def unlink_conversation?
    update?
  end

  def link_contact?
    update?
  end

  def unlink_contact?
    update?
  end

  def evaluate_ai?
    update?
  end

  # O resumo é gravado no card: também exige o funil dele.
  def summarize?
    update?
  end

  def reset_auto_followup?
    update?
  end

  def current_ai_suggestion?
    show?
  end

  # Excluir de vez (#2096): só administrador, também no EE. Não vira chave de função: apaga sem volta o histórico de
  # clientes, como excluir a conta ou mexer na segurança (CLAUDE.md, "Nunca delegar por função").
  def permanent_delete?
    account_user&.administrator? || false
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      Crm::Cards::VisibleScopeQuery.new(
        scope: scope,
        account: account,
        user: user,
        account_user: account_user
      ).perform
    end
  end

  private

  def visible_scope
    Pundit.policy_scope!(user_context, Crm::Card)
  end

  # A regra do mover (Crm::Access::CardGuard) com o funil do próprio card: a pessoa precisa ver todas as conversas do
  # card e ter o funil dele nas caixas envolvidas. Quem só vê o card (dono ou atendente sem o funil) continua vendo, mas
  # não fecha, arquiva, reabre, edita nem vincula. Sem acesso por funil, sempre verdadeiro.
  def funnel_member?
    Crm::Access::CardGuard.new(user: user, account: account, account_user: account_user).edit_allowed?(record)
  end
end

Crm::CardPolicy.prepend_mod_with('Crm::CardPolicy')

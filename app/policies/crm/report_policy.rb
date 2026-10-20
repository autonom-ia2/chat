class Crm::ReportPolicy < ApplicationPolicy
  def view?
    account_user.present?
  end

  # AI usage shows what the account spends on AI (#1157): only administrators in OSS.
  def view_ai_usage?
    account_user&.administrator? || false
  end
end

Crm::ReportPolicy.prepend_mod_with('Crm::ReportPolicy')

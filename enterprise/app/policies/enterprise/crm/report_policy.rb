module Enterprise::Crm::ReportPolicy
  include CrmPermissions

  def view?
    crm_permission?('crm_view_reports')
  end

  # Spend follows the AI key, which plain agents do not get (PLAIN_AGENT_DENIED_KEYS).
  def view_ai_usage?
    crm_permission?('crm_manage_ai')
  end
end

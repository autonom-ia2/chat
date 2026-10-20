module Enterprise::AccountUser
  CRM_KEYS = CustomRole::PERMISSIONS.select { |key| key.start_with?('crm_') }.freeze

  # The keys the panel and the Guide check routes against. They carry the same implications
  # as permission_granted? (#1157): `<module>_manage` brings `<module>_view`, and crm_admin
  # brings every crm_* key. Before, a role saved with only crm_admin saw CRM in the menu but
  # was turned away by the routes, which list crm_view.
  def permissions
    custom_role.present? ? (effective_role_permissions + ['custom_role']) : super
  end

  # A `<module>_manage` key implies the matching `<module>_view`.
  def permission_granted?(key)
    return true if super

    granted = custom_role&.permissions
    return false if granted.blank?

    granted.include?(key) || (key.end_with?('_view') && granted.include?("#{key.delete_suffix('_view')}_manage"))
  end

  private

  def effective_role_permissions
    granted = Array(custom_role.permissions)
    implied_views = granted.filter_map do |key|
      view = "#{key.delete_suffix('_manage')}_view" if key.end_with?('_manage')
      view if CustomRole::PERMISSIONS.include?(view)
    end
    implied_crm = granted.include?('crm_admin') ? CRM_KEYS : []
    (granted + implied_views + implied_crm).uniq
  end
end

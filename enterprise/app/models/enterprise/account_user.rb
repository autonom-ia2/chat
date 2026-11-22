module Enterprise::AccountUser
  def permissions
    custom_role.present? ? (custom_role.permissions + ['custom_role']) : super
  end

  # A `<module>_manage` key implies the matching `<module>_view`.
  def permission_granted?(key)
    return true if super

    granted = custom_role&.permissions
    return false if granted.blank?

    granted.include?(key) || (key.end_with?('_view') && granted.include?("#{key.delete_suffix('_view')}_manage"))
  end

  # Missed calls are pushed by default, alongside the core defaults
  def create_notification_setting
    super
    setting = user.notification_settings.find_by(account_id: account_id)
    setting.push_voice_call_missed = true
    setting.save!
  end
end

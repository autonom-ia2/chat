module SuperAdmin::NavigationHelper
  def settings_open?
    params[:controller].in? %w[super_admin/settings super_admin/app_configs super_admin/instagram_automations]
  end

  def settings_pages
    features = SuperAdmin::FeaturesHelper.available_features.select do |_feature, attrs|
      attrs['config_key'].present? && attrs['enabled']
    end

    # Add general at the beginning
    general_feature = [['general', { 'config_key' => 'general', 'name' => 'General' }]]

    instagram_automation = [['instagram_automation', {
      'name' => I18n.t('super_admin.instagram_automation.title'),
      'path' => super_admin_instagram_automation_path
    }]]

    general_feature + features.to_a + instagram_automation
  end
end

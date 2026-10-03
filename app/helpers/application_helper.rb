module ApplicationHelper
  def available_locales_with_name
    LANGUAGES_CONFIG.values
                    .reject { |val| LOCALE_PREFERENCE_ALIASES.key?(val[:iso_639_1_code]) }
                    .map { |val| val.slice(:name, :iso_639_1_code) }
  end

  def feature_help_urls
    features = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
    features.each_with_object({}) do |feature, hash|
      hash[feature['name']] = feature['help_url'] if feature['help_url']
    end
  end
end

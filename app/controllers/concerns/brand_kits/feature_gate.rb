# Com BRAND_KITS_ENABLED desligada, a API da identidade visual responde 404 (#1076).
module BrandKits::FeatureGate
  extend ActiveSupport::Concern

  included do
    before_action :ensure_brand_kits_enabled
  end

  private

  def ensure_brand_kits_enabled
    render json: { error: 'brand_kits.disabled' }, status: :not_found unless BrandKits::Config.enabled?
  end
end

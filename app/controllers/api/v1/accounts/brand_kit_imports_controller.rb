# Importar a identidade visual de um site (#1076): POST enfileira e devolve o id; GET acompanha e, quando
# termina, devolve a proposta para a pessoa conferir antes de salvar como kit. Uma importação ativa por
# conta e até BrandImportJob::HOURLY_LIMIT por hora.
class Api::V1::Accounts::BrandKitImportsController < Api::V1::Accounts::BaseController
  include BrandKits::FeatureGate

  def show
    @import = BrandImportJob.where(account: Current.account).find(params[:id])
    authorize @import
  end

  def create
    authorize BrandImportJob
    url = BrandKits::SiteImporter.normalize_url(params[:url])
    return render_error('brand_kit_import.rate_limited', :too_many_requests) if rate_limited?
    return if active_import_conflict?

    @import = BrandImportJob.create!(account: Current.account, user: Current.user, url: url)
    BrandKits::ImportJob.perform_later(@import.id)
    render :show, status: :accepted
  rescue BrandKits::SiteImporter::Error => e
    render json: { error: 'brand_kit_import.invalid_url', error_code: e.code, error_message: error_message(e.code) },
           status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render_error('brand_kit_import.already_running', :conflict)
  end

  private

  def rate_limited?
    BrandImportJob.where(account: Current.account).where('created_at > ?', 1.hour.ago).count >= BrandImportJob::HOURLY_LIMIT
  end

  def active_import_conflict?
    active = BrandImportJob.where(account: Current.account).active.first
    return false if active.nil?
    return active.fail!('stale').then { false } if active.stale?

    render json: { error: 'brand_kit_import.already_running', id: active.id }, status: :conflict
    true
  end

  def render_error(code, status)
    render json: { error: code }, status: status
  end

  def error_message(code)
    I18n.t("brand_kits.import_errors.#{code}", default: I18n.t('brand_kits.import_errors.internal_error'))
  end
  helper_method :error_message
end

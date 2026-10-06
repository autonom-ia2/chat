# Kits de marca da conta (#1076). Arquivar substitui apagar. A logo escolhida na importação
# (`logo_source_url`) só é baixada aqui, ao salvar; falha na logo não impede salvar o kit — vira aviso.
class Api::V1::Accounts::BrandKitsController < Api::V1::Accounts::BaseController
  before_action :fetch_kit, only: [:show, :update, :destroy, :set_default]
  before_action :refuse_archived, only: [:update, :set_default]

  def index
    authorize BrandKit
    @brand_kits = kit_scope.live.with_attached_logo.order(is_default: :desc, name: :asc)
  end

  def show; end

  def create
    @brand_kit = kit_scope.new(kit_params.merge(created_by: Current.user))
    authorize @brand_kit
    wants_default = boolean_param(:is_default) || no_default?
    save_with_logo { @brand_kit.make_default! if wants_default }
    render :show, status: :created
  end

  def update
    @brand_kit.assign_attributes(kit_params)
    save_with_logo
    render :show
  end

  def destroy
    @brand_kit.archive!
    render :show
  end

  def set_default
    @brand_kit.make_default!
    render :show
  end

  private

  def kit_scope
    BrandKit.where(account: Current.account)
  end

  def fetch_kit
    @brand_kit = kit_scope.find(params[:id])
    authorize @brand_kit
  end

  def refuse_archived
    render json: { error: 'brand_kit.archived' }, status: :unprocessable_entity if @brand_kit.archived?
  end

  def no_default?
    !kit_scope.live.exists?(is_default: true)
  end

  def save_with_logo
    @warnings = []
    BrandKit.transaction do
      @brand_kit.logo.purge_later if boolean_param(:remove_logo)
      @brand_kit.save!
      yield if block_given?
    end
    store_logo
  end

  def store_logo
    upload = option_params[:logo]
    source = option_params[:logo_source_url].presence
    return if upload.blank? && source.blank?

    upload.present? ? BrandKits::LogoDownloader.attach_upload(@brand_kit, upload) : BrandKits::LogoDownloader.new(@brand_kit, source).perform
    @brand_kit.save!
  rescue BrandKits::LogoDownloader::Error => e
    @warnings << e.code
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(option_params[key]) || false
  end

  # Opções do salvamento que não são colunas: padrão, remover logo, logo escolhida na importação ou enviada.
  def option_params
    @option_params ||= params.require(:brand_kit).permit(:is_default, :remove_logo, :logo_source_url, :logo)
  end

  def kit_params
    params.require(:brand_kit).permit(
      :name, :source_url,
      appearance: [:logo_url, {
        palette: BrandKits::Appearance::PALETTE_ROLES,
        typography: BrandKits::Appearance::TYPOGRAPHY_KEYS,
        social_links: [:network, :url],
        footer: BrandKits::Appearance::FOOTER_LIMITS.keys
      }]
    )
  end
end

class SuperAdmin::ProspectingScoringProfilesController < SuperAdmin::ApplicationController
  def index
    Autonomia::Prospecting::ScoringProfile.default_profile
    @profiles = Autonomia::Prospecting::ScoringProfile.includes(:accounts).order(default: :desc, name: :asc)
  end

  def new
    @profile = Autonomia::Prospecting::ScoringProfile.new(
      name: 'Novo perfil',
      weights: Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS
    )
    @eligible_accounts = eligible_accounts
  end

  def edit
    @profile = profile
    @eligible_accounts = eligible_accounts
  end

  def create
    @profile = Autonomia::Prospecting::ScoringProfile.new(profile_attributes)
    @profile.created_by = current_super_admin
    @profile.updated_by = current_super_admin
    save_profile!

    redirect_to super_admin_prospecting_scoring_profiles_path, notice: 'Prospecting scoring profile created'
  rescue ActiveRecord::RecordInvalid
    @eligible_accounts = eligible_accounts
    render :new, status: :unprocessable_entity
  end

  def update
    @profile = profile
    # Numa linha já salva, trocar as contas grava na hora: a transação desfaz se o perfil não passar na validação.
    ActiveRecord::Base.transaction do
      @profile.assign_attributes(profile_attributes)
      @profile.updated_by = current_super_admin
      save_profile!
    end

    redirect_to super_admin_prospecting_scoring_profiles_path, notice: 'Prospecting scoring profile updated'
  rescue ActiveRecord::RecordInvalid
    @eligible_accounts = eligible_accounts
    render :edit, status: :unprocessable_entity
  end

  def destroy
    current_profile = profile
    if current_profile.default? && Autonomia::Prospecting::ScoringProfile.where.not(id: current_profile.id).none?
      return redirect_to super_admin_prospecting_scoring_profiles_path,
                         alert: 'Create another profile before deleting the default profile'
    end

    current_profile.destroy!
    ensure_default_profile!
    redirect_to super_admin_prospecting_scoring_profiles_path, notice: 'Prospecting scoring profile deleted'
  end

  private

  def profile
    Autonomia::Prospecting::ScoringProfile.find(params[:id])
  end

  def profile_attributes
    profile_params = params.require(:autonomia_prospecting_scoring_profile)

    {
      name: profile_params[:name],
      default: ActiveModel::Type::Boolean.new.cast(profile_params[:default]),
      weights: scoring_weights_param
    }.merge(account_ids_param)
  end

  # Nenhuma conta marcada = perfil global. Formulário que não manda o campo mantém as contas como estão (#681).
  def account_ids_param
    permitted = params.require(:autonomia_prospecting_scoring_profile).permit(account_ids: [])
    return {} unless permitted.key?(:account_ids)

    { account_ids: Array(permitted[:account_ids]).compact_blank.map(&:to_i) }
  end

  # Contas com a prospecção ligada, mais as que já estão no perfil mesmo com a prospecção desligada depois.
  def eligible_accounts
    enabled = Account.where("accounts.internal_attributes ->> ? = 'true'", Autonomia::Prospecting::Config::INTERNAL_ATTR_KEY)
    enabled.or(Account.where(id: @profile.account_ids)).order(:name)
  end

  def scoring_weights_param
    permitted = params.require(:autonomia_prospecting_scoring_profile).permit(
      weights: Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.keys
    )
    permitted.fetch(:weights, {}).to_h
  end

  def save_profile!
    ActiveRecord::Base.transaction do
      if @profile.default?
        Autonomia::Prospecting::ScoringProfile.where.not(id: @profile.id).update_all(default: false)
      elsif Autonomia::Prospecting::ScoringProfile.where(default: true).where.not(id: @profile.id).none?
        @profile.default = true
      end

      @profile.save!
    end
  end

  def ensure_default_profile!
    return if Autonomia::Prospecting::ScoringProfile.where(default: true).exists?

    Autonomia::Prospecting::ScoringProfile.order(:name).first&.update!(default: true)
  end
end

module Enterprise::Api::V1::Accounts::OnboardingsController
  def help_center_generation
    @account = Current.account
    render json: help_center_generation_status
  end

  private

  # O onboarding não cria mais portal de Central de Ajuda: a Central é só leitura e o conteúdo
  # vem do repositório (#501). Por isso não há mais override de create_onboarding_inboxes.

  def complete_inbox_setup
    # Drop the onboarding-only generation pointer; the OSS method's save! persists both deletions.
    @account.custom_attributes.delete('help_center_generation_id')
    super
  end

  def help_center_generation_status
    generation_id = help_center_generation_id
    return super if generation_id.blank?

    state = Onboarding::HelpCenterGenerationState.current(generation_id)

    {
      generation_id: generation_id,
      state: state,
      articles_count: articles_count,
      categories_count: categories_count
    }
  end

  def help_center_generation_id
    @account.custom_attributes['help_center_generation_id']
  end

  def articles_count
    onboarding_portal&.articles&.count || 0
  end

  def categories_count
    onboarding_portal&.categories&.count || 0
  end

  def onboarding_portal
    @onboarding_portal ||= @account.portals.first
  end
end

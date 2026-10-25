class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :ensure_custom_roles_feature_enabled
  before_action :check_authorization
  before_action :fetch_custom_role, only: [:show, :update, :destroy]

  NO_ROLE_DESTINATION = 'none'.freeze

  def index
    @custom_roles = Current.account.custom_roles.for_people
  end

  def show; end

  def create
    grant_guard.write!(nil, permitted_params[:permissions])
    @custom_role = Current.account.custom_roles.create!(permitted_params)
  end

  def update
    grant_guard.write!(@custom_role, permitted_params.fetch(:permissions, @custom_role.permissions))
    @custom_role.update!(permitted_params)
  end

  # Quem tem a função vai para o destino escolhido e a função some, tudo junto ou nada (#2185). Antes, quem tinha a
  # função virava agente comum em silêncio, e agente comum vê quase todo o CRM.
  def destroy
    grant_guard.write!(@custom_role, [])
    needs_destination = AccountUser.exists?(custom_role_id: @custom_role.id)
    destination_id = needs_destination ? destination_role_id : nil
    return if performed?
    return head :ok if move_holders_and_destroy(destination_id, needs_destination)

    refuse_destination('changed_meanwhile', :conflict)
  end

  # Trava a função e o destino e relê quem tem a função dentro da transação: se alguém ganhou a função, ou o destino
  # sumiu, entre a pergunta e a exclusão, desfaz tudo (409). Sem isso o `dependent: :nullify` deixaria essa pessoa como
  # agente comum em silêncio. As travas seguem a ordem do id, para duas exclusões cruzadas não se travarem.
  def move_holders_and_destroy(destination_id, needs_destination)
    ActiveRecord::Base.transaction do
      locked = CustomRole.where(id: [@custom_role.id, destination_id].compact).order(:id).lock.to_a
      # Fora da associação: carregada, ela levaria os já movidos para os callbacks de exclusão da função.
      holders = AccountUser.where(custom_role_id: @custom_role.id).lock.to_a
      raise ActiveRecord::Rollback if locked.size < (destination_id ? 2 : 1) || (holders.any? && !needs_destination)

      # Um a um pelo modelo: cada mudança fica na auditoria da pessoa e atualiza o que ela enxerga.
      holders.each { |holder| holder.update!(custom_role_id: destination_id) }
      raise ActiveRecord::Rollback if AccountUser.exists?(custom_role_id: @custom_role.id)

      @custom_role.destroy!
    end
  end

  def permitted_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end

  # Outra função da conta, que quem exclui poderia entregar (a mesma regra de dar função a uma pessoa), ou 'none':
  # sem função, agente comum. Administrador nunca é destino. Sem destino, ou com um que não serve, responde 422.
  def destination_role_id
    value = params[:destination_role_id]
    return refuse_destination('destination_required') if value.blank?
    return if value == NO_ROLE_DESTINATION

    role = destination_candidates.find_by(id: value) if value.is_a?(String) || value.is_a?(Integer)
    return refuse_destination('destination_invalid') if role.nil?

    grant_guard.role_to_grant!(role.id).id
  end

  def destination_candidates
    Current.account.custom_roles.for_people.where.not(id: @custom_role.id)
  end

  def refuse_destination(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("errors.custom_role.#{code}") }, status: status
    nil
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.for_people.find(params[:id])
  end

  def grant_guard
    @grant_guard ||= CustomRoles::GrantGuard.new(actor: Current.account_user)
  end

  def ensure_custom_roles_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('custom_roles')
  end
end

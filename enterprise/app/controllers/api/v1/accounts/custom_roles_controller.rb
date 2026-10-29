class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  # A autorização vem antes: quem não gerencia funções recebe a recusa genérica e não fica sabendo do plano da conta.
  before_action :check_authorization
  before_action :ensure_custom_roles_feature_enabled
  before_action :fetch_custom_role, only: [:show, :update, :destroy]

  NO_ROLE_DESTINATION = 'none'.freeze
  FEATURE_OFF = 'feature_off'.freeze
  # Todo código que um 401 daqui leva no corpo: os do GrantGuard e o da conta sem o recurso (#2308, rodada 5). A tela
  # tem uma frase para cada (FRASE_DO_401 em salvarFuncao.js; codigosDo401.spec.js lê esta lista).
  UNAUTHORIZED_CODES = [*CustomRoles::GrantGuard::CODES, FEATURE_OFF].freeze

  def index
    @custom_roles = Current.account.custom_roles.for_people
  end

  def show; end

  def create
    grant_guard.write!(nil, permitted_params[:permissions])
    @custom_role = Current.account.custom_roles.create!(permitted_params)
  rescue ActiveRecord::RecordNotUnique
    render_name_taken
  rescue CustomRoles::GrantGuard::Denied => e
    log_handled_error(e)
    refuse(e.code, :unauthorized)
  end

  def update
    grant_guard.write!(@custom_role, permitted_params.fetch(:permissions, @custom_role.permissions))
    @custom_role.update!(permitted_params)
  rescue ActiveRecord::RecordNotUnique
    render_name_taken
  rescue CustomRoles::GrantGuard::Denied => e
    log_handled_error(e)
    refuse(e.code, :unauthorized)
  end

  # Quem tem a função vai para o destino escolhido e a função some, tudo junto ou nada (#2185). Antes, quem tinha a
  # função virava agente comum em silêncio, e agente comum vê quase todo o CRM.
  def destroy
    grant_guard.write!(@custom_role, [])
    needs_destination = AccountUser.exists?(custom_role_id: @custom_role.id)
    destination_id = needs_destination ? destination_role_id : nil
    return if performed?
    return head :ok if move_holders_and_destroy(destination_id, needs_destination)

    refuse('changed_meanwhile', :conflict)
  rescue ActiveRecord::InvalidForeignKey
    # Alguém ganhou a função depois da trava: a chave estrangeira recusa a exclusão e a transação já foi desfeita.
    refuse('changed_meanwhile', :conflict)
  rescue CustomRoles::GrantGuard::Denied => e
    log_handled_error(e)
    refuse(e.code, :unauthorized)
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
    return refuse('destination_required') if value.blank?
    return if value == NO_ROLE_DESTINATION

    role = destination_candidates.find_by(id: value) if value.is_a?(String) || value.is_a?(Integer)
    # Fora do alcance de quem exclui também é destino inválido (422), como na Issue: a tela só oferece os que alcança.
    return refuse('destination_invalid') if role.nil? || !grant_guard.reach?(role.permissions)

    role.id
  end

  def destination_candidates
    Current.account.custom_roles.for_people.where.not(id: @custom_role.id)
  end

  # Duas gravações do mesmo nome ao mesmo tempo: a segunda bate no índice e recebe o mesmo erro da validação.
  def render_name_taken
    render json: { message: "#{CustomRole.human_attribute_name(:name)} #{I18n.t('errors.messages.taken')}", attributes: ['name'] },
           status: :unprocessable_entity
  end

  # Recusas com código no corpo, no mesmo formato: destino do apagar (422/409) e, no 401, o motivo — 'out_of_reach',
  # 'own_role' ou 'feature_off' (#2308, decisão 11). O status e a regra não mudam; a tela só diz qual foi.
  def refuse(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("errors.custom_role.#{code}") }, status: status
    nil
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.for_people.find(params[:id])
  end

  def grant_guard
    @grant_guard ||= CustomRoles::GrantGuard.new(actor: Current.account_user)
  end

  # A recusa fica no log, como as do GrantGuard: sem isso, um plano rebaixado não deixaria rastro na investigação.
  FEATURE_OFF_LOG = 'custom_roles: recusa feature_off (recurso desligado na conta)'.freeze

  def ensure_custom_roles_feature_enabled
    return if Current.account.feature_enabled?('custom_roles')

    Rails.logger.info(FEATURE_OFF_LOG)
    refuse(FEATURE_OFF, :unauthorized)
  end
end

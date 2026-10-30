# Which custom roles a person may hand out, create, edit or delete (#1931, rule 2 in CLAUDE.md).
# - A role the giver reaches: every key is one the giver holds, and none is a delegation key. An administrator, or
#   someone whose role has grant_above_own, reaches every role.
# - Nobody but an administrator edits or deletes the role they hold.
# - Roles behind integration tokens are never handed out (CustomRole.for_people).
# A plain agent (no custom role) is always allowed: rule 2 covers custom roles only (Rodrigo, 20/10).
class CustomRoles::GrantGuard
  OUT_OF_REACH = 'out_of_reach'.freeze
  OWN_ROLE = 'own_role'.freeze
  # Every reason a refusal can carry (#2308, review round 5). Denied takes no other: a new reason goes here first, and
  # the role screen needs a sentence for it (FRASE_DO_401 in salvarFuncao.js; codigosDo401.spec.js reads this list).
  CODES = [OUT_OF_REACH, OWN_ROLE].freeze

  # The refusal (401) with its reason, so the role screen can say which one it was (#2308, decision 11):
  # OWN_ROLE (nobody but an administrator edits the role they hold) or OUT_OF_REACH. Still a
  # Pundit::NotAuthorizedError: every caller that renders the generic 401 keeps doing so.
  class Denied < Pundit::NotAuthorizedError
    attr_reader :code

    def initialize(code)
      raise ArgumentError, "unknown custom role refusal: #{code}" unless CODES.include?(code)

      @code = code
      super("custom role refused: #{code}")
    end
  end

  def initialize(actor:)
    @actor = actor
  end

  # The role to give, or nil for a plain agent. Raises 404 for a role outside the account and 401 out of reach.
  def role_to_grant!(custom_role_id)
    return if custom_role_id.blank?

    role = @actor.account.custom_roles.for_people.find(custom_role_id)
    deny! unless reach?(role.permissions)
    role
  end

  # Changing or removing someone's current role is also handing out access: the current role must be in reach too.
  def reach_current!(target)
    deny! if target.custom_role.present? && !reach?(target.custom_role.permissions)
  end

  def write!(role, permissions)
    deny!(OWN_ROLE) if role.present? && !@actor.administrator? && role.id == @actor.custom_role_id
    deny! if role.present? && !reach?(role.permissions)
    deny! unless reach?(permissions)
  end

  def reach?(permissions)
    return true if @actor.permission_granted?('grant_above_own')

    # The keys the role will store (#2124: an editing CRM key brings crm_view), not only the ones asked for.
    keys = CustomRole.with_implied_permissions(permissions)
    keys.none? { |key| CustomRole::DELEGATION_KEYS.include?(key) } && keys.all? { |key| @actor.permission_granted?(key) }
  end

  private

  def deny!(code = OUT_OF_REACH)
    raise Denied, code
  end
end

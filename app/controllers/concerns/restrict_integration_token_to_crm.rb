# Fail-closed authorization gate for CRM integration tokens (plan §3.2, B-T1).
#
# When a request authenticates via a Crm::IntegrationToken, this maps the
# requested controller/action to an explicit crm_* scope and rejects anything not
# in the map — DEFAULT DENY. Non-CRM controllers (conversations, contacts, admin,
# anything else a full-API user token could reach) are denied outright, closing
# the structural hole where the EE card_policy lacks a `close?` override.
#
# It is additive and a no-op for normal user / agent-bot auth.
module RestrictIntegrationTokenToCrm
  # NOTE: the host controller must register the before_action AFTER the
  # api_access_token authentication callbacks (so current_integration_token is
  # resolved first). Api::BaseController wires it explicitly for that reason.

  # controller => { action => required crm_* scope }. crm_admin implies all.
  # CRM reports are CRM-scoped here (crm_view_reports) even though native v2
  # reports live outside /crm/ — integration tokens only ever reach CRM
  # controllers, and report access is gated on its own scope (B-T1).
  CRM_SCOPE_MAP = {
    'api/v1/accounts/ai_requests' => { 'show' => 'crm_manage_ai' },
    'api/v1/accounts/crm/cards' => {
      'index' => 'crm_view', 'show' => 'crm_view', 'by_conversation' => 'crm_view',
      'card_stages' => 'crm_view', 'current_ai_suggestion' => 'crm_view',
      'create' => 'crm_manage_cards', 'from_conversation' => 'crm_manage_cards',
      'update' => 'crm_manage_cards', 'destroy' => 'crm_manage_cards',
      'link_conversation' => 'crm_manage_cards', 'unlink_conversation' => 'crm_manage_cards',
      'link_contact' => 'crm_manage_cards', 'unlink_contact' => 'crm_manage_cards',
      'close' => 'crm_manage_cards',
      'move' => 'crm_move_cards',
      'evaluate_ai' => 'crm_manage_ai', 'summarize' => 'crm_manage_ai'
    },
    'api/v1/accounts/crm/pipelines' => {
      'index' => 'crm_view', 'show' => 'crm_view',
      'create' => 'crm_manage_pipelines', 'update' => 'crm_manage_pipelines', 'destroy' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/stages' => {
      'index' => 'crm_view',
      'create' => 'crm_manage_pipelines', 'update' => 'crm_manage_pipelines',
      'destroy' => 'crm_manage_pipelines', 'reorder' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/pipeline_inboxes' => {
      'index' => 'crm_view',
      'create' => 'crm_manage_pipelines', 'destroy' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/stage_automations' => {
      'index' => 'crm_view', 'show' => 'crm_view',
      'create' => 'crm_manage_pipelines', 'update' => 'crm_manage_pipelines', 'destroy' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/stage_automation_steps' => {
      'create' => 'crm_manage_pipelines', 'update' => 'crm_manage_pipelines', 'destroy' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/inbox_settings' => {
      'index' => 'crm_view', 'update' => 'crm_manage_pipelines'
    },
    'api/v1/accounts/crm/ai_settings' => {
      'show' => 'crm_view', 'update' => 'crm_manage_ai'
    },
    'api/v1/accounts/crm/ai_suggestions' => {
      'accept' => 'crm_manage_ai', 'dismiss' => 'crm_manage_ai'
    },
    'api/v1/accounts/crm/follow_ups' => {
      'index' => 'crm_view', 'show' => 'crm_view', 'messaging_window' => 'crm_view', 'reminders' => 'crm_view',
      'create' => 'crm_manage_cards', 'update' => 'crm_manage_cards', 'destroy' => 'crm_manage_cards',
      'complete' => 'crm_manage_cards', 'cancel' => 'crm_manage_cards', 'dismiss_reminder' => 'crm_manage_cards'
    },
    'api/v1/accounts/crm/kanban' => {
      'index' => 'crm_view'
    },
    'api/v1/accounts/crm/calendar' => {
      'events' => 'crm_view'
    },
    'api/v1/accounts/crm/reports' => {
      'pipelines' => 'crm_view_reports', 'summary' => 'crm_view_reports', 'funnel' => 'crm_view_reports',
      'ai_vs_human' => 'crm_view_reports', 'throughput' => 'crm_view_reports',
      'follow_ups' => 'crm_view_reports', 'workload' => 'crm_view_reports'
    },
    'api/v1/accounts/crm/ai_usage' => {
      'index' => 'crm_view_reports', 'export' => 'crm_view_reports'
    }
  }.freeze

  private

  def restrict_integration_token_to_crm!
    required_scope = CRM_SCOPE_MAP.dig(params[:controller], params[:action])

    # Default deny: unmapped controller (conversations/contacts/admin/etc.) or
    # unmapped action.
    return render_unauthorized('This token is only authorized for CRM endpoints') if required_scope.blank?

    return if integration_token_scopes.include?('crm_admin')
    return if integration_token_scopes.include?(required_scope)

    render_unauthorized("This token is missing the required '#{required_scope}' scope")
  end

  def integration_token_scopes
    current_integration_token&.account_user&.custom_role&.permissions || []
  end
end

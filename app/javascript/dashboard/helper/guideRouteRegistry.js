// Guia da Plataforma — ALLOW-LIST of route names the guide is permitted to navigate to.
//
// Extraído dos `nav_target` do KB embarcado (lib/operator_guide/guia-produto.md). Defense-in-depth:
// o backend só sugere navegação a partir do KB, e o FE só navega se o nome estiver AQUI E resolver no
// router E o usuário tiver permissão (route guard). Um nome fora desta lista é ignorado (no-op).
export const GUIDE_ROUTE_REGISTRY = new Set([
  'account_overview_reports',
  'agent_bots',
  'agent_list',
  'attributes_list',
  'auditlogs_list',
  'automation_list',
  'autonomia_agent_panel',
  'autonomia_agents_builder',
  'autonomia_agents_index',
  'billing_settings_index',
  'campaigns_email_builder',
  'campaigns_email_index',
  'campaigns_email_sender_index',
  'campaigns_whatsapp_api_index',
  'canned_list',
  'contacts_campaign_imports',
  'contacts_dashboard_index',
  'contacts_dashboard_labels_index',
  'contacts_dashboard_segments_index',
  'conversation_mentions',
  'conversation_unattended',
  'crm_calendar_index',
  'crm_campaign_management_index',
  'crm_dashboard_index',
  'crm_integration_tokens_index',
  'crm_kanban_index',
  'crm_sla_index',
  'custom_roles_list',
  'folder_conversations',
  'general_settings_index',
  'home',
  'inbox_conversation',
  'labels_list',
  'macros_new',
  'portals_index',
  'profile_settings_index',
  'search',
  'security_settings_index',
  'settings_applications',
  'settings_applications_integration',
  'settings_inbox_new',
  'settings_inbox_show',
  'settings_inboxes_page_channel',
  'settings_integrations_crm_n8n',
  'settings_integrations_webhook',
  'settings_teams_new',
  'sla_reports',
  // V2 coverage expansion — report sub-pages + campaign types
  'agent_reports_index',
  'inbox_reports_index',
  'team_reports_index',
  'label_reports_index',
  'csat_reports',
  'campaigns_sms_index',
  'campaigns_livechat_index',
  'campaigns_whatsapp_index',
  // Epico #485 — onboarding assistido
  'first_steps',
]);

export const isGuideRoute = name => GUIDE_ROUTE_REGISTRY.has(name);

export default GUIDE_ROUTE_REGISTRY;

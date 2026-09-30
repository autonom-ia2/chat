import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import {
  CONVERSATION_PERMISSIONS,
  ROLES,
} from 'dashboard/constants/permissions';
import { frontendURL } from '../../../helper/URLHelper';

const CaptainPageRouteView = () => import('./pages/CaptainPageRouteView.vue');
const AssistantsIndexPage = () => import('./pages/AssistantsIndexPage.vue');
const AssistantEmptyStateIndex = () => import('./assistants/Index.vue');

const AssistantOverviewIndex = () => import('./assistants/overview/Index.vue');
const AssistantSettingsIndex = () => import('./assistants/settings/Index.vue');
const AssistantSystemSettingsIndex = () =>
  import('./assistants/settings/System.vue');
const AssistantAudienceSettingsIndex = () =>
  import('./assistants/settings/Audience.vue');
const AssistantScheduleSettingsIndex = () =>
  import('./assistants/settings/Schedule.vue');
const AssistantInboxesIndex = () => import('./assistants/inboxes/Index.vue');
const AssistantPlaygroundIndex = () =>
  import('./assistants/playground/Index.vue');
const AssistantGuardrailsIndex = () =>
  import('./assistants/guardrails/Index.vue');
const AssistantGuidelinesIndex = () =>
  import('./assistants/guidelines/Index.vue');
const AssistantScenariosIndex = () =>
  import('./assistants/scenarios/Index.vue');
const DocumentsIndex = () => import('./documents/Index.vue');
const ResponsesIndex = () => import('./responses/Index.vue');
const FaqSuggestionsIndex = () => import('./responses/FaqSuggestions.vue');
const CustomToolsIndex = () => import('./tools/Index.vue');

const meta = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

const faqSuggestionsMeta = {
  ...meta,
  permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
};

const metaCustomTools = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_CUSTOM_TOOLS,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

const metaV2 = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_V2,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

const assistantRoutes = [
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/overview'),
    component: AssistantOverviewIndex,
    name: 'captain_assistants_overview_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/faqs'),
    component: ResponsesIndex,
    name: 'captain_assistants_responses_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/documents'),
    component: DocumentsIndex,
    name: 'captain_assistants_documents_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/tools'),
    component: CustomToolsIndex,
    name: 'captain_tools_index',
    meta: metaCustomTools,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/scenarios'),
    component: AssistantScenariosIndex,
    name: 'captain_assistants_scenarios_index',
    meta: metaV2,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/playground'),
    component: AssistantPlaygroundIndex,
    name: 'captain_assistants_playground_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/inboxes'),
    component: AssistantInboxesIndex,
    name: 'captain_assistants_inboxes_index',
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/faqs/suggestions'
    ),
    component: FaqSuggestionsIndex,
    name: 'captain_assistants_faq_suggestions',
    meta: faqSuggestionsMeta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/faqs/pending'),
    redirect: to => ({
      name: 'captain_assistants_faq_suggestions',
      params: to.params,
      query: to.query,
    }),
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/settings'),
    component: AssistantSettingsIndex,
    name: 'captain_assistants_settings_index',
    meta,
  },
  // Settings sub-pages
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/system'
    ),
    component: AssistantSystemSettingsIndex,
    name: 'captain_assistants_settings_system_index',
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/audience'
    ),
    component: AssistantAudienceSettingsIndex,
    name: 'captain_assistants_settings_audience_index',
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/schedule'
    ),
    component: AssistantScheduleSettingsIndex,
    name: 'captain_assistants_settings_schedule_index',
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/guardrails'
    ),
    component: AssistantGuardrailsIndex,
    name: 'captain_assistants_guardrails_index',
    meta: metaV2,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/guidelines'
    ),
    component: AssistantGuidelinesIndex,
    name: 'captain_assistants_guidelines_index',
    meta: metaV2,
  },
  {
    path: frontendURL('accounts/:accountId/captain/assistants'),
    component: AssistantEmptyStateIndex,
    name: 'captain_assistants_create_index',
    meta: {
      permissions: ['administrator', 'agent'],
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/:navigationPath'),
    component: AssistantsIndexPage,
    name: 'captain_assistants_index',
    meta,
  },
];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/captain'),
    component: CaptainPageRouteView,
    redirect: to => {
      return {
        name: 'captain_assistants_index',
        params: {
          navigationPath: 'captain_assistants_overview_index',
          ...to.params,
        },
      };
    },
    children: [...assistantRoutes],
  },
];

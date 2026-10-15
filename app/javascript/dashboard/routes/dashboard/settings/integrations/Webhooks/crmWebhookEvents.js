// CRM Kanban "Conexões" outgoing webhook events. Canonical dotted strings MUST
// match the backend Webhook::CRM_WEBHOOK_EVENTS (app/models/webhook.rb) exactly,
// since the stored value IS the subscription string the listener filters on.
// Dotted (not underscored) so they cannot collide with the core EVENTS i18n map.
export const CRM_WEBHOOK_EVENTS = [
  { value: 'crm.card.created', labelKey: 'CRM_CARD_CREATED' },
  { value: 'crm.card.moved', labelKey: 'CRM_CARD_MOVED' },
  { value: 'crm.card.won', labelKey: 'CRM_CARD_WON' },
  { value: 'crm.card.lost', labelKey: 'CRM_CARD_LOST' },
  { value: 'crm.card.resolved', labelKey: 'CRM_CARD_RESOLVED' },
  { value: 'crm.card.cancelled', labelKey: 'CRM_CARD_CANCELLED' },
  { value: 'crm.card.reopened', labelKey: 'CRM_CARD_REOPENED' },
  { value: 'crm.card.archived', labelKey: 'CRM_CARD_ARCHIVED' },
];

const SUBSCRIPTIONS = 'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS';

// Label key of a stored subscription, the same one the form shows. CRM events
// live under CRM_EVENTS; the list used to build EVENTS.CRM.CARD.WON and showed
// the raw key (#1579).
export const webhookEventLabelKey = event => {
  const crmEvent = CRM_WEBHOOK_EVENTS.find(({ value }) => value === event);
  if (crmEvent) return `${SUBSCRIPTIONS}.CRM_EVENTS.${crmEvent.labelKey}`;
  return `${SUBSCRIPTIONS}.EVENTS.${String(event).toUpperCase()}`;
};

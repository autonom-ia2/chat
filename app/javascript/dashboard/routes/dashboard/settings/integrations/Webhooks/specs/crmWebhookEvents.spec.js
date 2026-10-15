import { describe, expect, it } from 'vitest';
import en from 'dashboard/i18n/locale/en/integrations.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/integrations.json';
import { CRM_WEBHOOK_EVENTS, webhookEventLabelKey } from '../crmWebhookEvents';

const valorEm = (catalogo, chave) =>
  chave.split('.').reduce((no, parte) => no?.[parte], catalogo);

// Todo evento que o backend aceita como assinatura (app/models/webhook.rb).
const EVENTOS_DO_BACKEND = [
  'conversation_status_changed',
  'conversation_updated',
  'conversation_created',
  'contact_created',
  'contact_updated',
  'message_created',
  'message_updated',
  'webwidget_triggered',
  'inbox_created',
  'inbox_updated',
  'conversation_typing_on',
  'conversation_typing_off',
  ...CRM_WEBHOOK_EVENTS.map(({ value }) => value),
];

describe('webhookEventLabelKey', () => {
  it('usa o rótulo do CRM para eventos do CRM, o mesmo do formulário', () => {
    expect(webhookEventLabelKey('crm.card.won')).toBe(
      'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.CRM_EVENTS.CRM_CARD_WON'
    );
    expect(webhookEventLabelKey('message_created')).toBe(
      'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS.MESSAGE_CREATED'
    );
  });

  // #1579: a lista de webhooks mostrava a chave crua (…EVENTS.CRM.CARD.WON).
  it.each([
    ['en', en],
    ['pt_BR', ptBR],
  ])(
    'tem texto em %s para todo evento que o backend aceita',
    (_idioma, catalogo) => {
      const semTexto = EVENTOS_DO_BACKEND.filter(
        evento =>
          typeof valorEm(catalogo, webhookEventLabelKey(evento)) !== 'string'
      );
      expect(semTexto).toEqual([]);
    }
  );
});

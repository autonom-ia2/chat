import { describe, expect, it } from 'vitest';
import { acoesOferecidas, webhookTravado } from '../macroWebhook';

const tipos = [{ key: 'add_label' }, { key: 'send_webhook_event' }];
const comWebhook = [{ action_name: 'send_webhook_event', action_params: [] }];
const semWebhook = [{ action_name: 'add_label', action_params: [] }];
const chaves = lista => lista.map(({ key }) => key);

describe('macroWebhook (#2451)', () => {
  it('com integration_manage, oferece o webhook', () => {
    expect(chaves(acoesOferecidas(tipos, true, semWebhook))).toEqual([
      'add_label',
      'send_webhook_event',
    ]);
  });

  it('sem integration_manage, esconde o webhook da macro que não o usa', () => {
    expect(chaves(acoesOferecidas(tipos, false, semWebhook))).toEqual([
      'add_label',
    ]);
  });

  it('sem integration_manage, a macro que já usa o webhook continua mostrando a ação', () => {
    expect(chaves(acoesOferecidas(tipos, false, comWebhook))).toContain(
      'send_webhook_event'
    );
  });

  it('sem integration_manage, salvar trava na macro com webhook, também ao tirá-lo', () => {
    expect(webhookTravado(false, comWebhook, comWebhook)).toBe(true);
    expect(webhookTravado(false, semWebhook, comWebhook)).toBe(true);
    expect(webhookTravado(false, semWebhook, [])).toBe(false);
  });

  it('com integration_manage, nada trava', () => {
    expect(webhookTravado(true, comWebhook, comWebhook)).toBe(false);
  });
});

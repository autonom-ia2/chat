import Settings from '../Settings.vue';

const computeWhatsappUnauthorized = context =>
  Settings.computed.whatsappUnauthorized.call(context);

describe('Inbox Settings', () => {
  it('shows WhatsApp reauthorization for embedded signup inboxes without checking account feature flags', () => {
    const isFeatureEnabledonAccount = vi.fn(() => false);

    const result = computeWhatsappUnauthorized({
      accountId: 1,
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: true,
      isFeatureEnabledonAccount,
      isOnChatwootCloud: true,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(true);
    expect(isFeatureEnabledonAccount).not.toHaveBeenCalled();
  });

  it('does not show WhatsApp reauthorization for manual WhatsApp inboxes', () => {
    const result = computeWhatsappUnauthorized({
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: false,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(false);
  });

  // #1487: escolha única pelo ChoiceSelect (teclado WAI-ARIA, 44 px), nunca pelo Select antigo.
  it('uses ChoiceSelect for single choices, not the old Select', () => {
    expect(Settings.components.ChoiceSelect).toBeDefined();
    expect(Settings.components.SelectInput).toBeUndefined();
  });
});

import { effectScope, ref } from 'vue';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { useChannelConnect } from '../../inbox-setup/useChannelConnect';

const assisted = ref(false);
const entitled = ref(true);
const disabled = ref(false);
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => ({}) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isMetaInboxCreationDisabled: disabled,
    isCloudFeatureEnabled: feature =>
      feature === 'channel_instagram' ? entitled.value : assisted.value,
  }),
}));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({ runEmbeddedSignup: vi.fn() }),
}));
vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: {
    generateAuthorization: vi.fn(),
    getTesterConfiguration: vi.fn(),
  },
}));

let scope;
let connect;
let openAssisted;
beforeEach(() => {
  assisted.value = false;
  entitled.value = true;
  disabled.value = false;
  scope = effectScope();
  openAssisted = vi.fn();
  connect = scope.run(() =>
    useChannelConnect({ onInstagramConnect: openAssisted })
  );
  instagramClient.generateAuthorization.mockResolvedValue({
    data: { url: 'https://fixture.example/oauth' },
  });
  vi.stubGlobal('window', { location: { href: '' } });
});
afterEach(() => {
  scope.stop();
  vi.unstubAllGlobals();
});

describe('onboarding Instagram account gate', () => {
  it('keeps OFF as direct OAuth with the onboarding return hint and no tester call', async () => {
    await connect.connectViaOAuth('instagram');
    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
      return_to: 'onboarding',
    });
    expect(instagramClient.getTesterConfiguration).not.toHaveBeenCalled();
    expect(openAssisted).not.toHaveBeenCalled();
    expect(window.location.href).toBe('https://fixture.example/oauth');
  });

  it('opens the assisted view while ON without direct OAuth fallback', async () => {
    assisted.value = true;
    await connect.connectViaOAuth('instagram');
    expect(openAssisted).toHaveBeenCalledOnce();
    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
  });

  it('rechecks the account flag when it changes from ON to OFF', async () => {
    assisted.value = true;
    await connect.connectViaOAuth('instagram');
    assisted.value = false;
    await connect.connectViaOAuth('instagram');
    expect(openAssisted).toHaveBeenCalledOnce();
    expect(instagramClient.generateAuthorization).toHaveBeenCalledOnce();
  });

  it.each([true, false])(
    'blocks a denied channel with assisted mode %s',
    async enabled => {
      assisted.value = enabled;
      entitled.value = false;
      await connect.connectViaOAuth('instagram');
      expect(openAssisted).not.toHaveBeenCalled();
      expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
    }
  );

  it.each([true, false])(
    'blocks the Meta restriction with assisted mode %s',
    async enabled => {
      disabled.value = true;
      assisted.value = enabled;
      await connect.connectViaOAuth('instagram');
      expect(openAssisted).not.toHaveBeenCalled();
      expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
    }
  );
});

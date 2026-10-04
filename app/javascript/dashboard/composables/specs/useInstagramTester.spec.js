import { effectScope, ref } from 'vue';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { useInstagramTester } from '../useInstagramTester';

vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: {
    getTesterConfiguration: vi.fn(),
    searchTesters: vi.fn(),
    getTesterStatus: vi.fn(),
    inviteTester: vi.fn(),
    generateAuthorization: vi.fn(),
  },
}));

const candidate = {
  id: '10001',
  username: 'demo_company',
  name: 'Empresa Demo',
  selection_token: 'signed-demo-selection',
};
const configuration = {
  enabled: true,
  available: true,
  app_name: 'Aplicativo Demo',
  acceptance_url: 'https://www.instagram.com/accounts/manage_access/',
};
let scope;
let disabled;
let tester;
let onLegacy;

beforeEach(() => {
  scope = effectScope();
  disabled = ref(false);
  onLegacy = vi.fn();
  tester = scope.run(() => useInstagramTester({ disabled, onLegacy }));
  instagramClient.getTesterConfiguration.mockResolvedValue({
    data: configuration,
  });
  instagramClient.searchTesters.mockResolvedValue({
    data: { results: [candidate] },
  });
});

afterEach(() => {
  scope.stop();
  vi.unstubAllGlobals();
});

describe('Instagram tester request guards and cancellation', () => {
  it('preserves the onboarding return hint when authorizing the accepted selected profile', async () => {
    tester = scope.run(() =>
      useInstagramTester({ disabled, returnTo: ref('onboarding') })
    );
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'accepted' },
    });
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: window.location.href },
    });
    await tester.loadConfiguration();
    tester.username.value = candidate.username;
    await tester.search();
    await tester.selectProfile(candidate);
    await tester.authorize();
    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith(
      {
        tester_selection_token: candidate.selection_token,
        return_to: 'onboarding',
      },
      { signal: expect.any(AbortSignal) }
    );
  });
  it('blocks disabled tester configuration for an ON account without invoking legacy OAuth', async () => {
    instagramClient.getTesterConfiguration.mockResolvedValue({
      data: { enabled: false },
    });
    await tester.loadConfiguration();
    expect(onLegacy).not.toHaveBeenCalled();
    expect(tester.configuration.value).toBeNull();
    expect(tester.error.value).toBe('UNAVAILABLE');
    await tester.authorize();
    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
  });

  it.each([null, 'absent', 'pending', 'accepted'])(
    'rejects direct search, status, invite and OAuth calls while restricted at status %s',
    async status => {
      await tester.loadConfiguration();
      tester.username.value = 'demo_company';
      await tester.search();
      tester.selected.value = candidate;
      tester.status.value = status;
      disabled.value = true;
      instagramClient.searchTesters.mockClear();

      await tester.search();
      await tester.checkStatus();
      await tester.invite();
      await tester.authorize();
      expect(instagramClient.searchTesters).not.toHaveBeenCalled();
      expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
      expect(instagramClient.inviteTester).not.toHaveBeenCalled();
      expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
      expect(tester.status.value).toBe(status);
    }
  );

  it('rejects direct profile selection while restricted without changing selection', async () => {
    await tester.loadConfiguration();
    tester.username.value = 'demo_company';
    await tester.search();
    disabled.value = true;
    await tester.selectProfile(candidate);
    expect(tester.selected.value).toBeNull();
    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
  });

  it.each(['search', 'status', 'invite', 'authorize'])(
    'maps proxy_unavailable to UNAVAILABLE and releases loading during %s',
    async action => {
      await tester.loadConfiguration();
      tester.username.value = 'demo_company';
      await tester.search();
      tester.selected.value = candidate;
      tester.status.value = action === 'invite' ? 'absent' : 'accepted';
      const failure = {
        response: {
          data: {
            error_code: 'proxy_unavailable',
            message: 'PRIVATE PROVIDER RESPONSE',
          },
        },
      };
      instagramClient.searchTesters.mockRejectedValue(failure);
      instagramClient.getTesterStatus.mockRejectedValue(failure);
      instagramClient.inviteTester.mockRejectedValue(failure);
      instagramClient.generateAuthorization.mockRejectedValue(failure);
      const invoke = action === 'status' ? 'checkStatus' : action;
      await tester[invoke]();
      expect(tester.error.value).toBe('UNAVAILABLE');
      expect(tester.busy.value).toBe(false);
      if (action === 'invite') {
        expect(tester.needsReconciliation.value).toBe(true);
        expect(tester.status.value).toBeNull();
      }
    }
  );

  it.each(['resolve', 'reject'])(
    'ignores a late OAuth %s after disposal without navigating or surfacing an error',
    async outcome => {
      await tester.loadConfiguration();
      tester.username.value = 'demo_company';
      await tester.search();
      tester.selected.value = candidate;
      tester.status.value = 'accepted';
      let resolveAuthorization;
      let rejectAuthorization;
      instagramClient.generateAuthorization.mockImplementationOnce(
        () =>
          new Promise((resolve, reject) => {
            resolveAuthorization = resolve;
            rejectAuthorization = reject;
          })
      );
      const location = { href: 'unchanged' };
      vi.stubGlobal('window', { location });
      const pending = tester.authorize();
      const signal =
        instagramClient.generateAuthorization.mock.calls[0][1].signal;
      scope.stop();
      expect(signal.aborted).toBe(true);
      if (outcome === 'resolve') {
        resolveAuthorization({
          data: { url: 'https://example.invalid/oauth' },
        });
      } else {
        rejectAuthorization(new Error('late failure'));
      }
      await pending;
      expect(location.href).toBe('unchanged');
      expect(tester.error.value).toBe('');
      expect(tester.busy.value).toBe(false);
    }
  );

  it.each(['resolve', 'reject'])(
    'ignores late configuration %s after disposal without activating legacy or setting errors',
    async outcome => {
      let resolveConfiguration;
      let rejectConfiguration;
      instagramClient.getTesterConfiguration.mockImplementationOnce(
        () =>
          new Promise((resolve, reject) => {
            resolveConfiguration = resolve;
            rejectConfiguration = reject;
          })
      );
      const pending = tester.loadConfiguration();
      const signal =
        instagramClient.getTesterConfiguration.mock.calls[0][0].signal;
      scope.stop();
      if (outcome === 'resolve') {
        resolveConfiguration({ data: { enabled: false } });
      } else {
        rejectConfiguration(new Error('late failure'));
      }
      await pending;
      expect(signal.aborted).toBe(true);
      expect(onLegacy).not.toHaveBeenCalled();
      expect(tester.error.value).toBe('');
      expect(tester.configuration.value).toBeNull();
      expect(tester.busy.value).toBe(false);
    }
  );
});

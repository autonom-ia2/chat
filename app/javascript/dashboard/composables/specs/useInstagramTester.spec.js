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
      data: {
        status: 'accepted',
        authorization_attestation: 'signed-demo-authorization',
      },
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
        tester_authorization_attestation: 'signed-demo-authorization',
        return_to: 'onboarding',
      },
      { signal: expect.any(AbortSignal) }
    );
  });

  it('uses only the confirmation belonging to the newly selected profile', async () => {
    const otherCandidate = {
      ...candidate,
      id: '10002',
      username: 'other_company',
      selection_token: 'signed-other-selection',
    };
    instagramClient.searchTesters.mockResolvedValue({
      data: { results: [candidate, otherCandidate] },
    });
    instagramClient.getTesterStatus
      .mockResolvedValueOnce({
        data: {
          status: 'accepted',
          authorization_attestation: 'signed-first-confirmation',
        },
      })
      .mockResolvedValueOnce({ data: { status: 'accepted' } });
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: window.location.href },
    });
    await tester.loadConfiguration();
    tester.username.value = candidate.username;
    await tester.search();
    await tester.selectProfile(candidate);
    tester.changeProfile();
    await tester.selectProfile(otherCandidate);
    await tester.authorize();

    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith(
      { tester_selection_token: otherCandidate.selection_token },
      { signal: expect.any(AbortSignal) }
    );
  });

  it('requires a new status check after the server rejects an expired confirmation', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: {
        status: 'accepted',
        authorization_attestation: 'expired-confirmation',
      },
    });
    instagramClient.generateAuthorization.mockRejectedValue({
      response: { data: { error_code: 'unknown_status' } },
    });
    await tester.loadConfiguration();
    tester.username.value = candidate.username;
    await tester.search();
    await tester.selectProfile(candidate);
    await tester.authorize();

    expect(tester.selected.value).toEqual(candidate);
    expect(tester.status.value).toBeNull();
    expect(tester.error.value).toBe('STATUS_ERROR');
    instagramClient.generateAuthorization.mockClear();
    await tester.authorize();
    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
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

  describe('invite outcomes', () => {
    const selectAbsent = async () => {
      instagramClient.getTesterStatus.mockResolvedValueOnce({
        data: { status: 'absent' },
      });
      await tester.loadConfiguration();
      tester.username.value = candidate.username;
      await tester.search();
      await tester.selectProfile(candidate);
    };
    const failure = code => ({ response: { data: { error_code: code } } });

    it('keeps the profile absent and invitable when Rails proves the invite was not sent', async () => {
      await selectAbsent();
      instagramClient.inviteTester.mockRejectedValue(
        failure('invite_not_sent')
      );
      await tester.invite();

      expect(tester.status.value).toBe('absent');
      expect(tester.needsReconciliation.value).toBe(false);
      expect(tester.error.value).toBe('INVITE_NOT_SENT');
      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(1);
      await tester.invite();
      expect(instagramClient.inviteTester).toHaveBeenCalledTimes(2);
    });

    it('verifies once after an unknown invite and shows the pending invitation', async () => {
      await selectAbsent();
      instagramClient.inviteTester.mockRejectedValue(failure('invite_unknown'));
      instagramClient.getTesterStatus.mockResolvedValueOnce({
        data: { status: 'pending' },
      });
      await tester.invite();

      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
      expect(tester.status.value).toBe('pending');
      expect(tester.titleKey.value).toBe('PENDING_TITLE');
      expect(tester.error.value).toBe('');
      expect(tester.needsReconciliation.value).toBe(false);
    });

    it('keeps the unknown state when the single automatic check still lists the profile as absent', async () => {
      await selectAbsent();
      instagramClient.inviteTester.mockRejectedValue(failure('invite_unknown'));
      instagramClient.getTesterStatus.mockResolvedValue({
        data: { status: 'absent' },
      });
      await tester.invite();

      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
      expect(tester.status.value).toBeNull();
      expect(tester.needsReconciliation.value).toBe(true);
      expect(tester.error.value).toBe('INVITE_UNKNOWN');
      await tester.invite();
      expect(instagramClient.inviteTester).toHaveBeenCalledTimes(1);
    });

    it('keeps the unknown state when the single automatic check fails', async () => {
      await selectAbsent();
      instagramClient.inviteTester.mockRejectedValue(failure('invite_unknown'));
      instagramClient.getTesterStatus.mockRejectedValueOnce(
        failure('meta_unavailable')
      );
      await tester.invite();

      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
      expect(tester.status.value).toBeNull();
      expect(tester.needsReconciliation.value).toBe(true);
      expect(tester.error.value).toBe('INVITE_UNKNOWN');
      await tester.invite();
      expect(instagramClient.inviteTester).toHaveBeenCalledTimes(1);
    });

    it('does not verify automatically after a rejected invite', async () => {
      await selectAbsent();
      instagramClient.inviteTester.mockRejectedValue(
        failure('invite_rejected')
      );
      await tester.invite();

      expect(tester.error.value).toBe('INVITE_ERROR');
      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(1);
    });
  });

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

describe('Instagram tester status from search', () => {
  const other = {
    ...candidate,
    id: '10002',
    username: 'demo_company_two',
    selection_token: 'signed-other-selection',
  };
  const searchWith = async (...results) => {
    instagramClient.searchTesters.mockResolvedValue({ data: { results } });
    await tester.loadConfiguration();
    tester.username.value = candidate.username;
    await tester.search();
  };
  const select = index => tester.selectProfile(tester.results.value[index]);

  it('uses an exact absent status once without a status request', async () => {
    instagramClient.inviteTester.mockResolvedValue({
      data: { status: 'pending', invited: true },
    });
    await searchWith({ ...candidate, tester_status: 'absent' });
    await select(0);

    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
    expect(tester.status.value).toBe('absent');
    expect(tester.titleKey.value).toBe('ABSENT_TITLE');
    await tester.invite();
    expect(instagramClient.inviteTester).toHaveBeenCalledTimes(1);
    expect(tester.titleKey.value).toBe('SENT_TITLE');
  });

  it('uses an exact pending status without a status request', async () => {
    await searchWith({ ...candidate, tester_status: 'pending' });
    await select(0);

    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
    expect(tester.titleKey.value).toBe('PENDING_TITLE');
  });

  it.each(['accepted', null, 'bogus', undefined])(
    'reads Meta once for search status %s',
    async testerStatus => {
      instagramClient.getTesterStatus.mockResolvedValue({
        data: { status: 'absent' },
      });
      await searchWith({ ...candidate, tester_status: testerStatus });
      await select(0);

      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(1);
    }
  );

  it('reads Meta again when the profile is selected after a sent invite', async () => {
    let resolveStatus;
    instagramClient.inviteTester.mockResolvedValue({
      data: { status: 'pending', invited: true },
    });
    instagramClient.getTesterStatus.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveStatus = resolve;
        })
    );
    await searchWith({ ...candidate, tester_status: 'absent' });
    await select(0);
    await tester.invite();
    tester.changeProfile();
    const reading = select(0);

    expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(1);
    expect(tester.status.value).toBeNull();
    expect(tester.titleKey.value).not.toBe('ABSENT_TITLE');
    resolveStatus({ data: { status: 'pending' } });
    await reading;
    expect(tester.titleKey.value).toBe('PENDING_TITLE');
  });

  it('never re-exposes Invite after an unknown invite and a new selection', async () => {
    let resolveStatus;
    instagramClient.inviteTester.mockRejectedValue({
      response: { data: { error_code: 'invite_unknown' } },
    });
    instagramClient.getTesterStatus.mockResolvedValueOnce({
      data: { status: 'absent' },
    });
    await searchWith({ ...candidate, tester_status: 'absent' });
    await select(0);
    await tester.invite();
    expect(tester.error.value).toBe('INVITE_UNKNOWN');
    instagramClient.getTesterStatus.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveStatus = resolve;
        })
    );
    tester.changeProfile();
    const reading = select(0);

    expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
    expect(tester.status.value).toBeNull();
    resolveStatus({ data: { status: 'pending' } });
    await reading;
    expect(tester.status.value).toBe('pending');
  });

  it('uses the search status again after a new search', async () => {
    await searchWith({ ...candidate, tester_status: 'absent' });
    await select(0);
    tester.changeProfile();
    await tester.search();
    await select(0);

    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
    expect(tester.status.value).toBe('absent');
  });

  it.each([
    [{ data: { status: 'pending' } }, 'notice', 'STILL_PENDING'],
    [{ data: { status: 'bogus' } }, 'error', 'STATUS_ERROR'],
  ])(
    'clears a previous message when the search status is used %#',
    async (statusResponse, field, message) => {
      instagramClient.getTesterStatus.mockResolvedValue({
        data: { status: 'pending' },
      });
      await searchWith(other, { ...candidate, tester_status: 'absent' });
      await select(0);
      instagramClient.getTesterStatus.mockResolvedValue(statusResponse);
      await tester.checkStatus();
      expect(tester[field].value).toBe(message);
      await select(1);

      expect(tester.notice.value).toBe('');
      expect(tester.error.value).toBe('');
      expect(tester.status.value).toBe('absent');
      expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
    }
  );
});

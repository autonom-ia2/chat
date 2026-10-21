import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePermissionGranted } from '../useCanManage';

vi.mock('dashboard/composables/store');

const mockSeat = account => {
  const getters = {
    getCurrentUser: ref({ accounts: [{ id: 1, ...account }] }),
    getCurrentAccountId: ref(1),
  };
  useMapGetter.mockImplementation(getter => getters[getter]);
};

describe('usePermissionGranted', () => {
  it('grants every key to an administrator', () => {
    mockSeat({ role: 'administrator', permissions: ['administrator'] });

    expect(usePermissionGranted('token_manage').value).toBe(true);
  });

  it('grants the key when the custom role holds it', () => {
    mockSeat({
      role: 'agent',
      custom_role_id: 7,
      permissions: ['integration_manage'],
    });

    expect(usePermissionGranted('integration_manage').value).toBe(true);
  });

  it('denies a key the custom role does not hold', () => {
    mockSeat({
      role: 'agent',
      custom_role_id: 7,
      permissions: ['integration_manage'],
    });

    expect(usePermissionGranted('token_manage').value).toBe(false);
  });

  it('denies a plain agent', () => {
    mockSeat({ role: 'agent', permissions: ['agent'] });

    expect(usePermissionGranted('integration_manage').value).toBe(false);
  });
});

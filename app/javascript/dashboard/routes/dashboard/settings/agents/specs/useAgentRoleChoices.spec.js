import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAgentRoleChoices } from '../useAgentRoleChoices';

vi.mock('dashboard/composables/store');
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const roles = [
  { id: 10, name: 'Atendimento', permissions: ['contact_view'] },
  { id: 11, name: 'Caixas', permissions: ['inbox_manage'] },
];

const choicesFor = ({ role, permissions }) => {
  const getters = {
    getCurrentUser: { id: 2, accounts: [{ id: 1, permissions }] },
    getCurrentAccountId: 1,
    getCurrentRole: role,
    getCurrentCustomRoleId: role === 'administrator' ? null : 7,
    'customRole/getCustomRoles': roles,
  };
  useMapGetter.mockImplementation(key => ref(getters[key]));
  return useAgentRoleChoices().roleChoices.value;
};

describe('useAgentRoleChoices (#1931)', () => {
  it('offers every role to an administrator', () => {
    const choices = choicesFor({ role: 'administrator', permissions: [] });
    expect(choices.every(choice => !choice.disabled)).toBe(true);
  });

  it('keeps administrator and roles out of reach visible but disabled, with the reason', () => {
    const choices = choicesFor({
      role: 'agent',
      permissions: ['people_manage', 'contact_manage', 'custom_role'],
    });
    const byValue = value => choices.find(choice => choice.value === value);

    expect(byValue('administrator')).toEqual(
      expect.objectContaining({
        disabled: true,
        hint: 'AGENT_MGMT.LOCK.ONLY_ADMIN_MAKES_ADMIN',
      })
    );
    expect(byValue('agent').disabled).toBe(false);
    expect(byValue(10).disabled).toBe(false);
    expect(byValue(11)).toEqual(
      expect.objectContaining({ disabled: true, hint: 'AGENT_MGMT.LOCK.ABOVE' })
    );
  });
});

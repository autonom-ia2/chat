import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAgentRoleChoices } from '../useAgentRoleChoices';

vi.mock('dashboard/composables/store');
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const roles = [
  { id: 10, name: 'Atendimento', permissions: ['contact_view'] },
  { id: 11, name: 'Caixas', permissions: ['inbox_manage'] },
];

const choicesFor = ({ role, permissions, flags = [], currentCustomRoleId }) => {
  const getters = {
    getCurrentUser: { id: 2, accounts: [{ id: 1, permissions }] },
    getCurrentAccountId: 1,
    getCurrentRole: role,
    getCurrentCustomRoleId: role === 'administrator' ? null : 7,
    'customRole/getCustomRoles': roles,
    'accounts/isFeatureEnabledonAccount': (_account, flag) =>
      flags.includes(flag),
  };
  useMapGetter.mockImplementation(key => ref(getters[key]));
  return useAgentRoleChoices({ currentCustomRoleId }).roleChoices.value;
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

  // #2317: tirar alguém da função (escolher "Agente" para quem tem uma função) segue a régua de dar uma função.
  describe('taking someone out of their custom role (#2317)', () => {
    const manager = {
      role: 'agent',
      permissions: ['people_manage', 'contact_manage'],
      flags: ['custom_roles'],
    };
    const agentChoice = options =>
      choicesFor(options).find(choice => choice.value === 'agent');

    it('locks the plain agent, with the reason, for a giver who does not reach the "Sem função" keys', () => {
      expect(agentChoice({ ...manager, currentCustomRoleId: 10 })).toEqual(
        expect.objectContaining({
          disabled: true,
          hint: 'AGENT_MGMT.LOCK.ONLY_ADMIN_TAKES_OUT',
        })
      );
    });

    it('keeps it open when adding someone, or editing someone without a custom role', () => {
      expect(agentChoice(manager).disabled).toBe(false);
      expect(
        agentChoice({ ...manager, currentCustomRoleId: null }).disabled
      ).toBe(false);
    });

    it('keeps it open for an administrator, grant_above_own, or with custom roles off', () => {
      const editing = { ...manager, currentCustomRoleId: 10 };
      expect(agentChoice({ ...editing, role: 'administrator' }).disabled).toBe(
        false
      );
      expect(
        agentChoice({
          ...editing,
          permissions: [...manager.permissions, 'grant_above_own'],
        }).disabled
      ).toBe(false);
      expect(agentChoice({ ...editing, flags: [] }).disabled).toBe(false);
    });
  });
});

import {
  MODULES,
  PRESETS,
  LEVELS,
  CONVERSATION_LEVELS,
  getLevel,
  setLevel,
  visibleExtras,
  toggleExtra,
} from '../permissionMatrix';

const moduleByKey = key => MODULES.find(module => module.key === key);

describe('permissionMatrix', () => {
  describe('view/manage modules', () => {
    const campaigns = moduleByKey('CAMPAIGNS');

    it('stores only the highest key of the chosen level', () => {
      const permissions = setLevel(campaigns, LEVELS.MANAGE, ['campaign_view']);

      expect(permissions).toEqual(['campaign_manage']);
      expect(getLevel(campaigns, permissions)).toBe(LEVELS.MANAGE);
    });

    it('removes the module keys on no access and keeps other modules', () => {
      expect(
        setLevel(campaigns, LEVELS.NONE, ['campaign_manage', 'inbox_view'])
      ).toEqual(['inbox_view']);
    });

    it('reads legacy manage-only keys, like contact_manage, as edit', () => {
      expect(getLevel(moduleByKey('CONTACTS'), ['contact_manage'])).toBe(
        LEVELS.MANAGE
      );
    });
  });

  describe('conversations', () => {
    const conversations = moduleByKey('CONVERSATIONS');

    it('maps conversation_manage to all and grants every scope', () => {
      const permissions = setLevel(conversations, CONVERSATION_LEVELS.ALL, []);

      expect(permissions).toEqual([
        'conversation_manage',
        'conversation_unassigned_manage',
        'conversation_participating_manage',
      ]);
    });

    it('defaults limited to participating and never drops the last scope', () => {
      const limited = setLevel(conversations, CONVERSATION_LEVELS.LIMITED, []);

      expect(limited).toEqual(['conversation_participating_manage']);
      expect(
        toggleExtra(conversations, 'conversation_participating_manage', limited)
      ).toEqual(limited);
    });
  });

  describe('crm', () => {
    const crm = moduleByKey('CRM');

    it('keeps crm_view stored when editing and hides the redundant move toggle', () => {
      const permissions = setLevel(crm, LEVELS.MANAGE, []);

      expect(permissions).toEqual([
        'crm_view',
        'crm_manage_cards',
        'crm_move_cards',
      ]);
      expect(visibleExtras(crm, permissions)).not.toContain('crm_move_cards');
    });

    it('reads a legacy crm_admin-only role as having CRM access', () => {
      expect(getLevel(crm, ['crm_admin'])).toBe(LEVELS.VIEW);
    });

    it('clears every crm key on no access', () => {
      expect(
        setLevel(crm, LEVELS.NONE, ['crm_view', 'crm_admin', 'report_manage'])
      ).toEqual(['report_manage']);
    });
  });

  it('builds presets from existing keys only', () => {
    const known = MODULES.flatMap(module => [
      ...Object.values(module.levels || {}),
      ...(module.extras || []),
      'conversation_manage',
    ]);

    Object.values(PRESETS).forEach(preset => {
      preset().forEach(key => expect(known).toContain(key));
    });
  });
});

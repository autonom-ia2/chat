import {
  MODULES,
  MODULE_GROUPS,
  PRESETS,
  PROFILES,
  BLANK_PROFILE,
  LEVELS,
  CONVERSATION_LEVELS,
  getLevel,
  setLevel,
  levelSlots,
  visibleExtras,
  toggleExtra,
  isExtraLocked,
  unmetSuggestion,
  profilePermissions,
  sensitiveExtrasOn,
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

  // #1188: módulo de função "Agendamento"; agendamento_manage implica _view no backend.
  describe('scheduling', () => {
    const scheduling = moduleByKey('SCHEDULING');

    it('lives in the account settings group, next to automations', () => {
      const group = MODULE_GROUPS.find(g => g.key === 'SETTINGS');
      const keys = group.modules.map(module => module.key);

      expect(keys).toContain('SCHEDULING');
      expect(keys.indexOf('SCHEDULING')).toBe(keys.indexOf('AUTOMATIONS') + 1);
      expect(scheduling.settings).toBe(true);
      expect(scheduling.icon).toBe('i-lucide-calendar-clock');
    });

    it('uses the agendamento keys for view and manage', () => {
      expect(scheduling.levels).toEqual({
        view: 'agendamento_view',
        manage: 'agendamento_manage',
      });
    });

    it('stores only the highest key and reads manage as manage', () => {
      const permissions = setLevel(scheduling, LEVELS.MANAGE, [
        'agendamento_view',
      ]);

      expect(permissions).toEqual(['agendamento_manage']);
      expect(getLevel(scheduling, permissions)).toBe(LEVELS.MANAGE);
    });

    it('reads manage alone as including view, and view as only view', () => {
      expect(getLevel(scheduling, ['agendamento_manage'])).toBe(LEVELS.MANAGE);
      expect(getLevel(scheduling, ['agendamento_view'])).toBe(LEVELS.VIEW);
      expect(getLevel(scheduling, ['automation_manage'])).toBe(LEVELS.NONE);
    });

    it('clears both keys on no access and keeps other modules', () => {
      expect(
        setLevel(scheduling, LEVELS.NONE, [
          'agendamento_manage',
          'agendamento_view',
          'automation_view',
        ])
      ).toEqual(['automation_view']);
    });

    it('offers no access, view and edit in the fixed positions', () => {
      expect(levelSlots(scheduling)).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
      ]);
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

  // #732, item 6: "Ver buscas de todos" é uma chave a mais da Prospecção.
  describe('prospecting', () => {
    const prospecting = moduleByKey('PROSPECTING');

    it('offers "see everyone searches" once the module has access', () => {
      expect(visibleExtras(prospecting, [])).toEqual([]);
      expect(visibleExtras(prospecting, ['prospecting_view'])).toEqual([
        'prospecting_view_all_searches',
      ]);
      expect(
        toggleExtra(prospecting, 'prospecting_view_all_searches', [
          'prospecting_view',
        ])
      ).toEqual(['prospecting_view', 'prospecting_view_all_searches']);
    });

    it('keeps the extra when switching between view and edit, and drops it on no access', () => {
      const withExtra = ['prospecting_view', 'prospecting_view_all_searches'];
      const managed = setLevel(prospecting, LEVELS.MANAGE, withExtra);

      expect(managed).toEqual([
        'prospecting_view_all_searches',
        'prospecting_manage',
      ]);
      expect(setLevel(prospecting, LEVELS.NONE, managed)).toEqual([]);
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

  describe('level slots', () => {
    it('keeps no access, view and edit in fixed positions', () => {
      expect(levelSlots(moduleByKey('CAMPAIGNS'))).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
      ]);
      expect(levelSlots(moduleByKey('CANNED_RESPONSES'))).toEqual([
        LEVELS.NONE,
        null,
        LEVELS.MANAGE,
      ]);
      expect(levelSlots(moduleByKey('REPORTS'))).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        null,
      ]);
      expect(levelSlots(moduleByKey('CONVERSATIONS'))).toEqual([
        CONVERSATION_LEVELS.NONE,
        CONVERSATION_LEVELS.LIMITED,
        CONVERSATION_LEVELS.ALL,
      ]);
    });
  });

  describe('crm admin', () => {
    const crm = moduleByKey('CRM');

    it('turns every CRM option on, matching what the backend grants', () => {
      const permissions = toggleExtra(crm, 'crm_admin', ['crm_view']);
      expect(permissions).toEqual(
        expect.arrayContaining([
          'crm_admin',
          'crm_view_reports',
          'crm_manage_pipelines',
          'crm_manage_ai',
          'crm_export',
        ])
      );
      expect(sensitiveExtrasOn(permissions)).toEqual([
        'crm_manage_ai',
        'crm_export',
        'crm_admin',
      ]);
    });

    it('keeps the options it includes on while crm_admin is on', () => {
      const on = toggleExtra(crm, 'crm_admin', ['crm_view']);
      expect(isExtraLocked('crm_export', on)).toBe(true);
      expect(toggleExtra(crm, 'crm_export', on)).toEqual(on);
      expect(isExtraLocked('crm_move_cards', on)).toBe(false);
    });

    it('turns off only crm_admin when switched off', () => {
      const on = toggleExtra(crm, 'crm_admin', ['crm_view']);
      const off = toggleExtra(crm, 'crm_admin', on);
      expect(off).not.toContain('crm_admin');
      expect(off).toContain('crm_export');
    });
  });

  describe('suggestions', () => {
    const prospecting = moduleByKey('PROSPECTING');

    it('points to campaigns when prospecting can edit but campaigns cannot', () => {
      expect(unmetSuggestion(prospecting, ['prospecting_manage']).key).toBe(
        'CAMPAIGNS'
      );
      expect(
        unmetSuggestion(prospecting, ['prospecting_manage', 'campaign_manage'])
      ).toBeNull();
      expect(unmetSuggestion(prospecting, ['prospecting_view'])).toBeNull();
    });
  });

  describe('profiles', () => {
    it('has a preset for every profile and an empty blank profile', () => {
      PROFILES.forEach(profile => {
        expect(profilePermissions(profile.key).length).toBeGreaterThan(0);
      });
      expect(profilePermissions(BLANK_PROFILE)).toEqual([]);
    });

    it('keeps the read-only profile free of any edit key', () => {
      const permissions = profilePermissions('READ_ONLY');
      MODULES.forEach(module => {
        expect(getLevel(module, permissions)).not.toBe(LEVELS.MANAGE);
      });
      expect(permissions.some(key => key.startsWith('conversation_'))).toBe(
        false
      );
    });
  });
});

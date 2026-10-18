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
  slotLevel,
  visibleExtras,
  toggleExtra,
  isExtraLocked,
  unmetSuggestion,
  suggestedLevel,
  profilePermissions,
  sensitiveExtrasOn,
} from '../permissionMatrix';
import en from 'dashboard/i18n/locale/en/customRole.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/customRole.json';

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

    describe('só ler (#1800)', () => {
      it('maps conversation_view alone to view', () => {
        const permissions = setLevel(conversations, CONVERSATION_LEVELS.VIEW, [
          'conversation_manage',
          'conversation_unassigned_manage',
          'conversation_participating_manage',
          'contact_view',
        ]);

        expect(permissions).toEqual(['contact_view', 'conversation_view']);
        expect(getLevel(conversations, permissions)).toBe(
          CONVERSATION_LEVELS.VIEW
        );
        expect(visibleExtras(conversations, permissions)).toEqual([]);
      });

      it('keeps the trio as the level and reading as an extra of limited', () => {
        const permissions = [
          'conversation_participating_manage',
          'conversation_view',
        ];

        expect(getLevel(conversations, permissions)).toBe(
          CONVERSATION_LEVELS.LIMITED
        );
        expect(visibleExtras(conversations, permissions)).toContain(
          'conversation_view'
        );
        expect(
          toggleExtra(conversations, 'conversation_view', permissions)
        ).toEqual(['conversation_participating_manage']);
      });

      it('handling starts with own conversations and keeps reading the others', () => {
        expect(setLevel(conversations, LEVELS.MANAGE, [])).toEqual([
          'conversation_participating_manage',
        ]);
        expect(
          setLevel(conversations, LEVELS.MANAGE, ['conversation_view'])
        ).toEqual(['conversation_participating_manage', 'conversation_view']);
      });

      it('handling keeps the current reach', () => {
        const all = setLevel(conversations, CONVERSATION_LEVELS.ALL, []);

        expect(setLevel(conversations, LEVELS.MANAGE, all)).toEqual(all);
        expect(
          setLevel(conversations, CONVERSATION_LEVELS.LIMITED, all)
        ).toEqual([
          'conversation_unassigned_manage',
          'conversation_participating_manage',
        ]);
      });

      it('all drops reading, which it already covers', () => {
        expect(
          setLevel(conversations, CONVERSATION_LEVELS.ALL, [
            'conversation_view',
          ])
        ).not.toContain('conversation_view');
      });

      it('lights the handle position for own and all', () => {
        expect(slotLevel(conversations, CONVERSATION_LEVELS.LIMITED)).toBe(
          LEVELS.MANAGE
        );
        expect(slotLevel(conversations, CONVERSATION_LEVELS.ALL)).toBe(
          LEVELS.MANAGE
        );
        expect(slotLevel(conversations, CONVERSATION_LEVELS.VIEW)).toBe(
          LEVELS.VIEW
        );
      });
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
      // Conversas: não vê, só lê, atende (as próprias ou todas, escolhidas embaixo; #1800).
      expect(levelSlots(moduleByKey('CONVERSATIONS'))).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
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

    // #1797: distribuição pede ver as caixas, e ver já basta.
    it('points to inboxes at view level for assignment', () => {
      const assignment = moduleByKey('ASSIGNMENT');

      expect(unmetSuggestion(assignment, ['assignment_manage']).key).toBe(
        'INBOXES'
      );
      expect(suggestedLevel(assignment)).toBe('view');
      expect(
        unmetSuggestion(assignment, ['assignment_manage', 'inbox_view'])
      ).toBeNull();
      expect(
        unmetSuggestion(assignment, ['assignment_manage', 'inbox_manage'])
      ).toBeNull();
    });
  });

  describe('contatos: exportar e excluir (#1845)', () => {
    const contacts = MODULES.find(module => module.key === 'CONTACTS');

    it('mostra exportar para quem vê e exportar e excluir para quem edita', () => {
      expect(visibleExtras(contacts, ['contact_view'])).toEqual([
        'contact_export',
      ]);
      expect(visibleExtras(contacts, ['contact_manage'])).toEqual([
        'contact_export',
        'contact_delete',
      ]);
    });

    it('voltar para ver tira excluir e mantém exportar', () => {
      const permissions = [
        'contact_manage',
        'contact_export',
        'contact_delete',
      ];
      expect(setLevel(contacts, LEVELS.VIEW, permissions)).toEqual([
        'contact_export',
        'contact_view',
      ]);
    });

    it('sem acesso tira as duas chaves', () => {
      const permissions = [
        'contact_manage',
        'contact_export',
        'contact_delete',
      ];
      expect(setLevel(contacts, LEVELS.NONE, permissions)).toEqual([]);
    });

    it('trata as duas como sensíveis', () => {
      expect(sensitiveExtrasOn(['contact_export', 'contact_delete'])).toEqual([
        'contact_export',
        'contact_delete',
      ]);
    });
  });

  // A linha do ajuste fino mostra nome e descrição pela chave; sem a tradução, a tela mostra a chave crua (#1845).
  it('todo ajuste fino tem nome e descrição em en e pt_BR', () => {
    const extras = MODULES.flatMap(module => module.extras || []);
    [en, ptBR].forEach(({ CUSTOM_ROLE }) => {
      extras.forEach(key => {
        expect(CUSTOM_ROLE.PERMISSIONS[key.toUpperCase()]).toBeTruthy();
        expect(CUSTOM_ROLE.EXTRAS[key.toUpperCase()]).toBeTruthy();
      });
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

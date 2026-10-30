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
  levelOptions,
  levelSlots,
  slotLevel,
  visibleExtras,
  toggleExtra,
  isExtraLocked,
  unmetSuggestion,
  suggestedLevel,
  profilePermissions,
  sensitiveExtrasOn,
  modulesWithKeys,
  KEYS_OUTSIDE_MATRIX,
} from '../permissionMatrix';
import { DELEGATION_KEYS } from 'dashboard/constants/permissions';
import { keyLockReason } from 'dashboard/helper/peopleAccess';
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

  // #1969: Financeiro. Ver = valores de custo; Editar = ligar e desligar a autorização de cobranças da Meta.
  describe('finance', () => {
    const finance = moduleByKey('FINANCE');

    it('has its own group and the financial keys', () => {
      const group = MODULE_GROUPS.find(g => g.key === 'FINANCE');

      expect(group.modules.map(module => module.key)).toEqual(['FINANCE']);
      expect(finance.levels).toEqual({
        view: 'financial_view',
        manage: 'financial_manage',
      });
    });

    it('stores only the highest key and clears both on no access', () => {
      const permissions = setLevel(finance, LEVELS.MANAGE, ['financial_view']);

      expect(permissions).toEqual(['financial_manage']);
      expect(getLevel(finance, permissions)).toBe(LEVELS.MANAGE);
      expect(setLevel(finance, LEVELS.NONE, permissions)).toEqual([]);
    });

    it('gives the Finance profile the costs in view', () => {
      expect(getLevel(finance, profilePermissions('FINANCE'))).toBe(
        LEVELS.VIEW
      );
    });

    it('has the module texts in en and pt_BR', () => {
      [en, ptBR].forEach(locale => {
        expect(locale.CUSTOM_ROLE.MATRIX.GROUPS.FINANCE).toBeTruthy();
        expect(locale.CUSTOM_ROLE.MATRIX.MODULES.FINANCE.NAME).toBeTruthy();
      });
    });
  });

  // #2027: Integrações ao lado das caixas, só "pode mexer"; ver e trocar tokens é um ajuste fino dela, porque as
  // telas dos tokens (robôs, webhooks, CRM/n8n) ficam em Integrações. As duas chaves só o administrador entrega.
  describe('integrations and tokens', () => {
    const integrations = moduleByKey('INTEGRATIONS');

    it('lives in connections, right after inboxes, with tokens as its extra', () => {
      const group = MODULE_GROUPS.find(g => g.key === 'CONNECTIONS');

      expect(group.modules.map(module => module.key)).toEqual([
        'INBOXES',
        'INTEGRATIONS',
      ]);
      expect(levelSlots(integrations)).toEqual([
        LEVELS.NONE,
        null,
        LEVELS.MANAGE,
      ]);
      expect(setLevel(integrations, LEVELS.MANAGE, [])).toEqual([
        'integration_manage',
      ]);
      expect(integrations.extras).toEqual(['token_manage']);
    });

    it('asks inboxes at view to reconnect a channel', () => {
      expect(unmetSuggestion(integrations, ['integration_manage']).key).toBe(
        'INBOXES'
      );
      expect(
        unmetSuggestion(integrations, ['integration_manage', 'inbox_view'])
      ).toBeNull();
    });

    it('is not handed out by any profile', () => {
      PROFILES.forEach(profile => {
        const permissions = profilePermissions(profile.key);
        expect(permissions).not.toContain('integration_manage');
        expect(permissions).not.toContain('token_manage');
      });
    });

    it('has the texts in en and pt_BR', () => {
      [en, ptBR].forEach(({ CUSTOM_ROLE }) => {
        const module = CUSTOM_ROLE.MATRIX.MODULES.INTEGRATIONS;
        expect(module.NAME).toBeTruthy();
        expect(module.LEVEL_MANAGE).toBeTruthy();
        expect(module.SUGGESTION).toBeTruthy();
        expect(CUSTOM_ROLE.EXTRAS.TOKEN_MANAGE).toBeTruthy();
        expect(CUSTOM_ROLE.PERMISSIONS.TOKEN_MANAGE).toBeTruthy();
      });
    });
  });

  // #2070: Anúncios da Meta ganha "Editar" (meta_ads_manage): conectar, configurar, desconectar e agir sobre o
  // consultor. Chave protegida: só o administrador entrega, e nenhum perfil pronto a traz.
  describe('meta ads', () => {
    const metaAds = moduleByKey('META_ADS');

    it('has view and manage, storing only the highest key', () => {
      expect(levelSlots(metaAds)).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
      ]);
      expect(setLevel(metaAds, LEVELS.MANAGE, ['meta_ads_view'])).toEqual([
        'meta_ads_manage',
      ]);
      expect(getLevel(metaAds, ['meta_ads_manage'])).toBe(LEVELS.MANAGE);
      expect(getLevel(metaAds, ['meta_ads_view'])).toBe(LEVELS.VIEW);
    });

    it('is a delegation key, handed out by no profile', () => {
      expect(DELEGATION_KEYS).toContain('meta_ads_manage');
      expect(DELEGATION_KEYS).not.toContain('meta_ads_view');
      PROFILES.forEach(profile => {
        expect(profilePermissions(profile.key)).not.toContain(
          'meta_ads_manage'
        );
      });
    });

    it('has the texts in en and pt_BR', () => {
      [en, ptBR].forEach(({ CUSTOM_ROLE }) => {
        const module = CUSTOM_ROLE.MATRIX.MODULES.META_ADS;
        expect(module.LEVEL_VIEW).toBeTruthy();
        expect(module.LEVEL_MANAGE).toBeTruthy();
        expect(CUSTOM_ROLE.PERMISSIONS.META_ADS_MANAGE).toBeTruthy();
      });
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

  describe('conversas: apagar mensagens (#1893)', () => {
    const conversations = moduleByKey('CONVERSATIONS');
    const DELETE = 'conversation_message_delete';

    it('aparece para quem atende as próprias ou todas, e não para quem só lê', () => {
      expect(
        visibleExtras(conversations, ['conversation_participating_manage'])
      ).toContain(DELETE);
      expect(
        visibleExtras(
          conversations,
          setLevel(conversations, CONVERSATION_LEVELS.ALL, [])
        )
      ).toEqual([DELETE]);
      expect(visibleExtras(conversations, ['conversation_view'])).toEqual([]);
    });

    it('atender não liga a chave sozinho', () => {
      expect(setLevel(conversations, LEVELS.MANAGE, [])).not.toContain(DELETE);
      expect(
        setLevel(conversations, CONVERSATION_LEVELS.ALL, [])
      ).not.toContain(DELETE);
    });

    it('trocar entre as próprias e todas mantém a chave', () => {
      const all = [
        ...setLevel(conversations, CONVERSATION_LEVELS.ALL, []),
        DELETE,
      ];
      const limited = setLevel(conversations, CONVERSATION_LEVELS.LIMITED, all);

      expect(limited).toContain(DELETE);
      expect(
        setLevel(conversations, CONVERSATION_LEVELS.ALL, limited)
      ).toContain(DELETE);
    });

    it('só ler ou sem acesso tira a chave', () => {
      const permissions = ['conversation_participating_manage', DELETE];

      expect(
        setLevel(conversations, CONVERSATION_LEVELS.VIEW, permissions)
      ).toEqual(['conversation_view']);
      expect(
        setLevel(conversations, CONVERSATION_LEVELS.NONE, permissions)
      ).toEqual([]);
    });

    it('desligar a chave mantém o alcance e ela é sensível', () => {
      const permissions = ['conversation_participating_manage', DELETE];

      expect(toggleExtra(conversations, DELETE, permissions)).toEqual([
        'conversation_participating_manage',
      ]);
      expect(sensitiveExtrasOn(permissions)).toEqual([DELETE]);
    });

    // O formato que a migration gera: só conversation_manage, sem os alcances guardados.
    it('desliga a chave num cargo antigo de todas as conversas', () => {
      expect(
        toggleExtra(conversations, DELETE, ['conversation_manage', DELETE])
      ).toEqual(['conversation_manage']);
    });

    it('de todas para as próprias num cargo antigo começa pelas próprias e mantém a chave', () => {
      const limited = setLevel(conversations, CONVERSATION_LEVELS.LIMITED, [
        'conversation_manage',
        DELETE,
      ]);

      expect(limited).toEqual([DELETE, 'conversation_participating_manage']);
      expect(getLevel(conversations, limited)).toBe(
        CONVERSATION_LEVELS.LIMITED
      );
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

  // Espelho de CustomRole::PERMISSIONS (enterprise/app/models/custom_role.rb). Chave nova no servidor entra aqui e
  // numa área da matriz (ou em KEYS_OUTSIDE_MATRIX, #2352); o teste abaixo acusa a diferença (#2115).
  const SERVER_KEYS = [
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
    'conversation_view',
    'conversation_message_delete',
    'contact_manage',
    'report_manage',
    'knowledge_base_manage',
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
    'crm_manage_pipelines',
    'crm_manage_ai',
    'crm_view_reports',
    'crm_admin',
    'crm_export',
    'crm_delete_cards',
    'crm_metas_manage',
    'contact_view',
    'contact_export',
    'contact_delete',
    'knowledge_base_view',
    'autonomia_view',
    'autonomia_manage',
    'desempenho_view',
    'campaign_view',
    'campaign_manage',
    'campaign_send',
    'inbox_view',
    'inbox_manage',
    'canned_response_manage',
    'prospecting_view',
    'prospecting_manage',
    'prospecting_view_all_searches',
    'insurance_view',
    'insurance_manage',
    'automation_view',
    'automation_manage',
    'agendamento_view',
    'agendamento_manage',
    'whatsapp_templates_view',
    'whatsapp_templates_manage',
    'meta_ads_view',
    'meta_ads_manage',
    'posts_view',
    'posts_manage',
    'label_manage',
    'attribute_manage',
    'macro_manage',
    'sla_manage',
    'assignment_manage',
    'people_manage',
    'custom_role_manage',
    'grant_above_own',
    'financial_view',
    'financial_manage',
    'integration_manage',
    'token_manage',
    'sales_value_view',
  ];
  const known = MODULES.flatMap(module => [
    ...Object.values(module.levels || {}),
    ...(module.extras || []),
    ...(module.type === 'conversations' ? ['conversation_manage'] : []),
  ]);

  it('covers exactly the 59 server keys between the matrix and the keys outside it', () => {
    expect(SERVER_KEYS).toHaveLength(59);
    expect(known.filter(key => KEYS_OUTSIDE_MATRIX.includes(key))).toEqual([]);
    expect([...new Set([...known, ...KEYS_OUTSIDE_MATRIX])].sort()).toEqual(
      [...SERVER_KEYS].sort()
    );
  });

  it('builds presets from server keys only', () => {
    Object.values(PRESETS).forEach(preset => {
      preset().forEach(key => expect(SERVER_KEYS).toContain(key));
    });
  });

  // #2352: the help-center article keys left both role editors.
  it('builds no preset with a key outside the matrix', () => {
    Object.values(PRESETS).forEach(preset => {
      expect(preset().filter(key => KEYS_OUTSIDE_MATRIX.includes(key))).toEqual(
        []
      );
    });
  });

  it('keeps a stored key outside the matrix when another module changes', () => {
    const permissions = setLevel(moduleByKey('CAMPAIGNS'), LEVELS.MANAGE, [
      'knowledge_base_view',
      'campaign_view',
    ]);
    expect(permissions).toEqual(['knowledge_base_view', 'campaign_manage']);
  });

  // #2360: "Pode mexer" de Seus posts só chega com a F2 (#2305).
  describe('levels offered later', () => {
    // Nenhuma área adia um nível hoje (Seus posts liberou editar na F2 #2305); a regra continua valendo.
    const later = { ...moduleByKey('CAMPAIGNS'), laterLevels: [LEVELS.MANAGE] };

    it('does not offer a later level to a new role', () => {
      expect(levelOptions(later)).toEqual([LEVELS.NONE, LEVELS.VIEW]);
      expect(levelSlots(later)).toEqual([LEVELS.NONE, LEVELS.VIEW, null]);
    });

    it('still shows a later level to a role that already has it, so it can be lowered', () => {
      expect(levelOptions(later, LEVELS.MANAGE)).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
      ]);
    });

    it('offers posts edit to every role since F2 (#2305)', () => {
      const posts = moduleByKey('POSTS');

      expect(levelOptions(posts)).toEqual([
        LEVELS.NONE,
        LEVELS.VIEW,
        LEVELS.MANAGE,
      ]);
      expect(getLevel(posts, ['posts_manage'])).toBe(LEVELS.MANAGE);
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
        'crm_metas_manage',
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

    it('mostra excluir já ligado num cargo que só vê, para dar para desligar', () => {
      expect(
        visibleExtras(contacts, ['contact_view', 'contact_delete'])
      ).toEqual(['contact_export', 'contact_delete']);
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

  describe('campanhas: disparar (#1898)', () => {
    const campaigns = MODULES.find(module => module.key === 'CAMPAIGNS');

    it('mostra disparar só para quem edita', () => {
      expect(visibleExtras(campaigns, ['campaign_view'])).toEqual([]);
      expect(visibleExtras(campaigns, ['campaign_manage'])).toEqual([
        'campaign_send',
      ]);
    });

    it('voltar para ver ou tirar o acesso tira disparar', () => {
      const permissions = ['campaign_manage', 'campaign_send'];
      expect(setLevel(campaigns, LEVELS.VIEW, permissions)).toEqual([
        'campaign_view',
      ]);
      expect(setLevel(campaigns, LEVELS.NONE, permissions)).toEqual([]);
    });

    it('editar sozinho não liga disparar', () => {
      expect(setLevel(campaigns, LEVELS.MANAGE, [])).toEqual([
        'campaign_manage',
      ]);
    });

    it('trata disparar como sensível', () => {
      expect(sensitiveExtrasOn(['campaign_manage', 'campaign_send'])).toEqual([
        'campaign_send',
      ]);
    });
  });

  describe('crm: arquivar cards (#1874)', () => {
    const crm = moduleByKey('CRM');

    it('"Pode mexer" não liga arquivar sozinho, e o ajuste aparece só para quem mexe', () => {
      const permissions = setLevel(crm, LEVELS.MANAGE, ['crm_view']);
      expect(permissions).not.toContain('crm_delete_cards');
      expect(visibleExtras(crm, permissions)).toContain('crm_delete_cards');
      expect(visibleExtras(crm, ['crm_view'])).not.toContain(
        'crm_delete_cards'
      );
    });

    it('voltar para ver tira arquivar', () => {
      const permissions = ['crm_view', 'crm_manage_cards', 'crm_delete_cards'];
      expect(setLevel(crm, LEVELS.VIEW, permissions)).toEqual(['crm_view']);
    });

    it('Administrador do CRM inclui arquivar e o mantém ligado', () => {
      const on = toggleExtra(crm, 'crm_admin', ['crm_view']);
      expect(on).toContain('crm_delete_cards');
      expect(isExtraLocked('crm_delete_cards', on)).toBe(true);
    });
  });

  describe('crm: metas do mês (#1991)', () => {
    const crm = moduleByKey('CRM');
    const METAS = 'crm_metas_manage';

    it('aparece para quem vê o CRM, não liga sozinho e tem texto em en e pt_BR', () => {
      expect(visibleExtras(crm, ['crm_view'])).toContain(METAS);
      expect(setLevel(crm, LEVELS.MANAGE, ['crm_view'])).not.toContain(METAS);
      expect(en.CUSTOM_ROLE.PERMISSIONS.CRM_METAS_MANAGE).toBeTruthy();
      expect(ptBR.CUSTOM_ROLE.PERMISSIONS.CRM_METAS_MANAGE).toBeTruthy();
      expect(en.CUSTOM_ROLE.EXTRAS.CRM_METAS_MANAGE).toBeTruthy();
      expect(ptBR.CUSTOM_ROLE.EXTRAS.CRM_METAS_MANAGE).toBeTruthy();
    });

    // #2075: a meta é dinheiro; ligar as metas liga os valores em R$, desligar as metas deixa os valores.
    it('liga junto com os valores em R$, desliga sozinha, e sem acesso ao CRM sai junto', () => {
      const on = toggleExtra(crm, METAS, ['crm_view']);
      expect(on).toEqual(['crm_view', METAS, 'sales_value_view']);
      expect(toggleExtra(crm, METAS, on)).toEqual([
        'crm_view',
        'sales_value_view',
      ]);
      expect(setLevel(crm, LEVELS.NONE, on)).toEqual([]);
    });

    it('é sensível: ligar pede confirmação', () => {
      expect(sensitiveExtrasOn(['crm_view', METAS])).toEqual([METAS]);
    });

    it('Administrador do CRM inclui as metas e as mantém ligadas', () => {
      const on = toggleExtra(crm, 'crm_admin', ['crm_view']);
      expect(on).toContain(METAS);
      expect(isExtraLocked(METAS, on)).toBe(true);
    });
  });

  describe('crm: valores de venda em R$ (#2075)', () => {
    const crm = moduleByKey('CRM');
    const VALORES = 'sales_value_view';

    it('aparece para quem vê o CRM, não liga sozinha e tem texto em en e pt_BR', () => {
      expect(visibleExtras(crm, ['crm_view'])).toContain(VALORES);
      expect(setLevel(crm, LEVELS.MANAGE, ['crm_view'])).not.toContain(VALORES);
      expect(en.CUSTOM_ROLE.PERMISSIONS.SALES_VALUE_VIEW).toBeTruthy();
      expect(ptBR.CUSTOM_ROLE.PERMISSIONS.SALES_VALUE_VIEW).toBeTruthy();
      expect(en.CUSTOM_ROLE.EXTRAS.SALES_VALUE_VIEW).toBeTruthy();
      expect(ptBR.CUSTOM_ROLE.EXTRAS.SALES_VALUE_VIEW).toBeTruthy();
    });

    it('desligar os valores desliga as metas, que dependem deles, menos as que o crm_admin trava', () => {
      const on = ['crm_view', 'crm_metas_manage', VALORES];
      expect(toggleExtra(crm, VALORES, on)).toEqual(['crm_view']);
      const admin = toggleExtra(crm, 'crm_admin', ['crm_view', VALORES]);
      expect(toggleExtra(crm, VALORES, admin)).toContain('crm_metas_manage');
      expect(toggleExtra(crm, VALORES, ['crm_view'])).toEqual([
        'crm_view',
        VALORES,
      ]);
    });

    // Chave protegida: o Administrador do CRM, que quem cuida de Pessoas repassa, não a liga.
    it('é sensível e o Administrador do CRM não a liga', () => {
      expect(sensitiveExtrasOn(['crm_view', VALORES])).toEqual([VALORES]);
      const on = toggleExtra(crm, 'crm_admin', ['crm_view']);
      expect(on).not.toContain(VALORES);
      expect(isExtraLocked(VALORES, on)).toBe(false);
    });
  });

  describe('pessoas (#1931)', () => {
    const people = moduleByKey('PEOPLE');

    it('fica nas configurações da conta, só com não vê e pode mexer', () => {
      const group = MODULE_GROUPS.find(g => g.key === 'SETTINGS');
      expect(group.modules).toContain(people);
      expect(levelSlots(people)).toEqual([LEVELS.NONE, null, LEVELS.MANAGE]);
      expect(setLevel(people, LEVELS.MANAGE, [])).toEqual(['people_manage']);
    });

    it('mostra montar funções e entregar acima só para quem pode mexer', () => {
      expect(visibleExtras(people, [])).toEqual([]);
      expect(visibleExtras(people, ['people_manage'])).toEqual([
        'custom_role_manage',
        'grant_above_own',
      ]);
    });

    it('voltar para não vê tira os ajustes finos junto', () => {
      const permissions = toggleExtra(
        people,
        'grant_above_own',
        toggleExtra(people, 'custom_role_manage', ['people_manage'])
      );
      expect(permissions).toEqual([
        'people_manage',
        'custom_role_manage',
        'grant_above_own',
      ]);
      expect(
        setLevel(people, LEVELS.NONE, [...permissions, 'crm_view'])
      ).toEqual(['crm_view']);
    });

    it('trata os dois ajustes como sensíveis', () => {
      expect(
        sensitiveExtrasOn([
          'people_manage',
          'custom_role_manage',
          'grant_above_own',
        ])
      ).toEqual(['custom_role_manage', 'grant_above_own']);
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

  // #2115: o que a frase do perfil promete precisa estar nas chaves dele, e o que diz que não pode, fora.
  describe('promessas dos perfis', () => {
    const PHRASE_KEYS = {
      OWN_CONVERSATIONS: ['conversation_unassigned_manage'],
      SEND_CAMPAIGNS: ['campaign_send'],
      EDIT_CONTACTS: ['contact_manage', 'contact_export'],
      EDIT_IMPORT_CONTACTS: ['contact_manage'],
      EXPORT_CRM: ['crm_export'],
      SET_GOALS: ['sales_value_view', 'crm_metas_manage'],
      SETUP_INBOXES: ['inbox_manage'],
    };

    PROFILES.forEach(profile => {
      it(`${profile.key} cumpre o que a frase promete`, () => {
        const permissions = profilePermissions(profile.key);
        profile.can
          .filter(phrase => PHRASE_KEYS[phrase])
          .forEach(phrase => {
            expect(permissions).toEqual(
              expect.arrayContaining(PHRASE_KEYS[phrase])
            );
          });
        profile.cannot
          .filter(phrase => PHRASE_KEYS[phrase])
          .forEach(phrase => {
            PHRASE_KEYS[phrase].forEach(key =>
              expect(permissions).not.toContain(key)
            );
          });
      });
    });

    it('Marketing dispara campanhas e exporta contatos', () => {
      expect(profilePermissions('MARKETING')).toEqual(
        expect.arrayContaining([
          'campaign_manage',
          'campaign_send',
          'contact_export',
        ])
      );
    });

    it('Atendente pega da fila, e Supervisor e Gestor comercial não exportam contatos', () => {
      expect(profilePermissions('AGENT')).toContain(
        'conversation_unassigned_manage'
      );
      expect(profilePermissions('SUPERVISOR')).not.toContain('contact_export');
      expect(profilePermissions('SALES_MANAGER')).not.toContain(
        'contact_export'
      );
      expect(profilePermissions('SALES_MANAGER')).toContain('crm_export');
      const supervisor = PROFILES.find(item => item.key === 'SUPERVISOR');
      expect(supervisor.can).not.toContain('EDIT_CONTACTS');
    });

    it('Gestor comercial vê os valores e define as metas', () => {
      expect(profilePermissions('SALES_MANAGER')).toEqual(
        expect.arrayContaining(['sales_value_view', 'crm_metas_manage'])
      );
    });

    it('Operações não reconecta canais: integration_manage fica com o administrador', () => {
      expect(profilePermissions('OPERATIONS')).not.toContain(
        'integration_manage'
      );
      [en, ptBR].forEach(({ CUSTOM_ROLE }) => {
        expect(CUSTOM_ROLE.PROFILES.PHRASES.SETUP_INBOXES).toBeTruthy();
      });
    });

    it('Somente leitura vê anúncios, agendamento e cotação', () => {
      const permissions = profilePermissions('READ_ONLY');
      ['META_ADS', 'SCHEDULING', 'INSURANCE'].forEach(key => {
        expect(getLevel(moduleByKey(key), permissions)).toBe(LEVELS.VIEW);
      });
    });

    it('nenhum perfil apaga mensagens', () => {
      PROFILES.forEach(profile => {
        expect(profilePermissions(profile.key)).not.toContain(
          'conversation_message_delete'
        );
      });
    });

    it('toda frase dos perfis tem texto em en e pt_BR', () => {
      const phrases = PROFILES.flatMap(profile => [
        ...profile.can,
        ...profile.cannot,
      ]);
      [en, ptBR].forEach(({ CUSTOM_ROLE }) => {
        phrases.forEach(phrase => {
          expect(CUSTOM_ROLE.PROFILES.PHRASES[phrase]).toBeTruthy();
        });
      });
    });
  });

  // #2115: quem não entrega chave protegida recebe o modelo sem ela, e a tela diz em que áreas.
  describe('modelo aplicado por quem não entrega chave protegida', () => {
    const giver = {
      isAdmin: false,
      permissions: [
        'custom_role_manage',
        ...profilePermissions('SALES_MANAGER').filter(
          key => !DELEGATION_KEYS.includes(key)
        ),
      ],
    };
    const withinReach = keys => keys.filter(key => !keyLockReason(giver, key));

    it('tira as chaves protegidas e a meta, que depende delas', () => {
      const applied = withinReach(profilePermissions('SALES_MANAGER'));

      expect(applied).not.toContain('sales_value_view');
      expect(applied).not.toContain('crm_metas_manage');
      expect(applied).toContain('crm_export');
    });

    it('aponta a área onde o modelo ficou incompleto', () => {
      const full = profilePermissions('SALES_MANAGER');
      const applied = withinReach(full);
      const leftOut = full.filter(key => !applied.includes(key));

      expect(modulesWithKeys(leftOut).map(module => module.key)).toEqual([
        'CRM',
      ]);
      expect(modulesWithKeys(['conversation_manage'])[0].key).toBe(
        'CONVERSATIONS'
      );
      expect(modulesWithKeys([])).toEqual([]);
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

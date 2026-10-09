import {
  extractChangedAccountUserValues,
  generateTranslationPayload,
  generateLogActionKey,
  translateLogPayload,
  getAutonomiaOperationChanges,
  auditLogFiltersFromQuery,
  buildAuditLogRouteQuery,
} from '../auditlogHelper'; // import the functions

describe('Helper functions', () => {
  const agentList = [
    { id: 1, name: 'Agent 1' },
    { id: 2, name: 'Agent 2' },
    { id: 3, name: 'Agent 3' },
  ];

  describe('extractChangedAccountUserValues', () => {
    it('should correctly extract i18n keys when role is changed', () => {
      const changes = {
        role: [0, 1],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual(['AUDIT_LOGS.FIELDS.ROLE']);
      expect(values).toEqual(['AUDIT_LOGS.ROLES.ADMINISTRATOR']);
    });

    it('should correctly extract i18n keys when availability is changed', () => {
      const changes = {
        availability: [0, 2],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual(['AUDIT_LOGS.FIELDS.AVAILABILITY']);
      expect(values).toEqual(['AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY']);
    });

    it('should correctly extract i18n keys when both are changed', () => {
      const changes = {
        role: [1, 0],
        availability: [1, 2],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual([
        'AUDIT_LOGS.FIELDS.ROLE',
        'AUDIT_LOGS.FIELDS.AVAILABILITY',
      ]);
      expect(values).toEqual([
        'AUDIT_LOGS.ROLES.AGENT',
        'AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY',
      ]);
    });
  });

  describe('generateTranslationPayload', () => {
    it('should handle AccountUser create', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'create',
        user_id: 1,
        auditable_id: 123,
        audited_changes: {
          user_id: 2,
          role: 1,
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 123,
        invitee: 'Agent 2',
        role: 'AUDIT_LOGS.ROLES.ADMINISTRATOR',
      });
    });

    it('should handle AccountUser update', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable_id: 123,
        audited_changes: {
          user_id: 2,
          role: [1, 0],
          availability: [0, 2],
        },
        auditable: {
          user_id: 3,
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 123,
        user: 'Agent 3',
        attributes: [
          'AUDIT_LOGS.FIELDS.ROLE',
          'AUDIT_LOGS.FIELDS.AVAILABILITY',
        ],
        values: [
          'AUDIT_LOGS.ROLES.AGENT',
          'AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY',
        ],
      });
    });

    it('should handle InboxMember or TeamMember', () => {
      const auditLogItemInboxMember = {
        auditable_type: 'InboxMember',
        action: 'create',
        audited_changes: {
          user_id: 2,
        },
        user_id: 1,
        auditable_id: 789,
      };

      const payloadInboxMember = generateTranslationPayload(
        auditLogItemInboxMember,
        agentList
      );
      expect(payloadInboxMember).toEqual({
        agentName: 'Agent 1',
        id: 789,
        user: 'Agent 2',
      });

      const auditLogItemTeamMember = {
        auditable_type: 'TeamMember',
        action: 'create',
        audited_changes: {
          user_id: 3,
        },
        user_id: 1,
        auditable_id: 789,
      };

      const payloadTeamMember = generateTranslationPayload(
        auditLogItemTeamMember,
        agentList
      );
      expect(payloadTeamMember).toEqual({
        agentName: 'Agent 1',
        id: 789,
        user: 'Agent 3',
      });
    });

    it('should handle Message destroy with the conversation display id', () => {
      const auditLogItem = {
        auditable_type: 'Message',
        action: 'destroy',
        user_id: 1,
        auditable_id: 55123,
        audited_changes: {
          display_id: 1234,
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 55123,
        conversationId: 1234,
      });
    });

    // #536 — a frase que a pessoa confirmou no cartão do Guia é o que a linha
    // da Auditoria mostra; sem ela a linha diria só "fez pelo Guia".
    it('should carry the confirmed sentence of a Platform Guide action', () => {
      const auditLogItem = {
        auditable_type: 'Account',
        action: 'guide_action',
        user_id: 1,
        auditable_id: 16,
        audited_changes: {
          frase: 'Criar a etiqueta vip.',
          acao: 'POST labels',
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 16,
        frase: 'Criar a etiqueta vip.',
      });
    });

    it('should handle generic case like Team create', () => {
      const auditLogItem = {
        auditable_type: 'Team',
        action: 'create',
        user_id: 1,
        auditable_id: 456,
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 456,
      });
    });

    it('uses the normalized actor and operation key for an Autonomia agent audit', () => {
      const auditLogItem = {
        auditable_type: 'Autonomia::Agents::Agent',
        action: 'update',
        user_id: 88,
        username: 'operator@example.com',
        actor: { type: 'SuperAdmin', id: 88, name: 'Operador global' },
        auditable_id: 321,
        operation_key: 'voice_reply',
      };

      expect(generateTranslationPayload(auditLogItem, agentList)).toEqual({
        agentName: 88,
        id: 321,
        actor: 'Operador global',
        operationKey: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY',
      });
      expect(generateLogActionKey(auditLogItem)).toBe(
        'AUDIT_LOGS.AUTONOMIA_AGENT.EDIT'
      );
    });

    it('uses the plural operation keys for a multi-setting Autonomia audit', () => {
      const auditLogItem = {
        auditable_type: 'Autonomia::Agents::Agent',
        action: 'update',
        user_id: 88,
        actor: { type: 'SuperAdmin', id: 88, name: 'Operador global' },
        auditable_id: 321,
        operation_keys: ['voice_reply', 'operate_media'],
      };

      expect(
        generateTranslationPayload(auditLogItem, agentList).operationKey
      ).toBe('AUDIT_LOGS.OPERATION_KEYS.MULTIPLE');
    });
  });

  describe('getAutonomiaOperationChanges', () => {
    it('does not attach operation changes to other audit types', () => {
      expect(
        getAutonomiaOperationChanges({
          auditable_type: 'Team',
          audited_changes: {
            operation_config: {
              voice_reply: { old: true, new: false },
            },
          },
        })
      ).toEqual([]);
    });

    it('keeps only typed, masked operation changes and never exposes raw values', () => {
      const rawSecret = 'do-not-render-this-secret';
      const auditLogItem = {
        auditable_type: 'Autonomia::Agents::Agent',
        operation_keys: [
          'voice_reply',
          'test_allowlist_phones',
          'voice_instructions',
          'native_tool_slugs',
          'secret_key',
        ],
        audited_changes: {
          operation_config: {
            voice_reply: { old: true, new: false },
            test_allowlist_phones: {
              old: ['+551••••00'],
              new: ['+551••••11'],
            },
            voice_instructions: {
              old: { length: 8 },
              new: { length: 12 },
            },
            native_tool_slugs: {
              old: { count: 1 },
              new: { count: 2 },
            },
            secret_key: { old: rawSecret, new: rawSecret },
          },
        },
      };

      const changes = getAutonomiaOperationChanges(auditLogItem);

      expect(changes).toEqual([
        {
          key: 'voice_reply',
          label: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY',
          before: { type: 'boolean', value: true },
          after: { type: 'boolean', value: false },
        },
        {
          key: 'test_allowlist_phones',
          label: 'AUDIT_LOGS.OPERATION_KEYS.TEST_ALLOWLIST_PHONES',
          before: {
            type: 'masked_list',
            count: 1,
            preview: ['+551••••00'],
          },
          after: {
            type: 'masked_list',
            count: 1,
            preview: ['+551••••11'],
          },
        },
        {
          key: 'voice_instructions',
          label: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_INSTRUCTIONS',
          before: { type: 'length', value: 8 },
          after: { type: 'length', value: 12 },
        },
        {
          key: 'native_tool_slugs',
          label: 'AUDIT_LOGS.OPERATION_KEYS.NATIVE_TOOL_SLUGS',
          before: { type: 'count', value: 1 },
          after: { type: 'count', value: 2 },
        },
      ]);
      expect(JSON.stringify(changes)).not.toContain(rawSecret);
    });
  });

  describe('translateLogPayload', () => {
    // Um "dicionário" fake: devolve o próprio texto em português para cada
    // chave, como o i18n real faria — sem depender do vue-i18n no teste.
    const fakeTranslations = {
      'AUDIT_LOGS.FIELDS.ROLE': 'papel',
      'AUDIT_LOGS.FIELDS.AVAILABILITY': 'disponibilidade',
      'AUDIT_LOGS.ROLES.AGENT': 'Agente',
      'AUDIT_LOGS.ROLES.ADMINISTRATOR': 'Administrador',
      'AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY': 'ocupado',
    };
    const t = key => fakeTranslations[key] || key;

    it('translates a single role value', () => {
      const payload = {
        agentName: 'Lia Admin',
        role: 'AUDIT_LOGS.ROLES.AGENT',
      };
      expect(translateLogPayload(payload, t)).toEqual({
        agentName: 'Lia Admin',
        role: 'Agente',
        attributes: undefined,
        values: undefined,
      });
    });

    it('translates and joins attributes/values arrays', () => {
      const payload = {
        agentName: 'Lia Admin',
        attributes: [
          'AUDIT_LOGS.FIELDS.ROLE',
          'AUDIT_LOGS.FIELDS.AVAILABILITY',
        ],
        values: [
          'AUDIT_LOGS.ROLES.ADMINISTRATOR',
          'AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY',
        ],
      };
      expect(translateLogPayload(payload, t)).toEqual({
        agentName: 'Lia Admin',
        role: undefined,
        attributes: 'papel, disponibilidade',
        values: 'Administrador, ocupado',
      });
    });

    it('leaves non-key fields untouched', () => {
      const payload = {
        agentName: 'Lia Admin',
        id: 42,
        user: 'Marcos Andrade',
      };
      expect(translateLogPayload(payload, t)).toEqual({
        agentName: 'Lia Admin',
        id: 42,
        user: 'Marcos Andrade',
        role: undefined,
        attributes: undefined,
        values: undefined,
      });
    });

    it('translates the operation key without exposing its machine name', () => {
      const payload = {
        actor: 'Operador global',
        operationKey: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY',
      };
      const translate = key =>
        key === 'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY'
          ? 'respostas de voz'
          : key;

      expect(translateLogPayload(payload, translate)).toEqual({
        actor: 'Operador global',
        operationKey: 'respostas de voz',
        role: undefined,
        attributes: undefined,
        values: undefined,
      });
    });
  });

  describe('generateLogActionKey', () => {
    it('should generate correct action key when user updates self', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: {
          user_id: 1,
        },
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.SELF');
    });

    it('should generate correct action key when user updates other agent', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: {
          user_id: 2,
        },
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.OTHER');
    });

    it('should generate correct action key when a message is deleted', () => {
      const auditLogItem = {
        auditable_type: 'Message',
        action: 'destroy',
        user_id: 1,
        auditable_id: 42,
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.MESSAGE.DELETE');
    });

    // Sem a chave, a tela desenha a linha EM BRANCO: o registro existe e
    // ninguém consegue ler.
    it('should generate the key of a Platform Guide action', () => {
      const auditLogItem = {
        auditable_type: 'Account',
        action: 'guide_action',
        user_id: 1,
        auditable_id: 16,
      };

      expect(generateLogActionKey(auditLogItem)).toEqual(
        'AUDIT_LOGS.GUIDE.ACTION'
      );
    });

    it('should generate correct action key when updating a deleted user', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: null,
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.DELETED');
    });
  });

  describe('#auditLogFiltersFromQuery', () => {
    it('maps route query params to API filters', () => {
      expect(
        auditLogFiltersFromQuery({
          page: '2',
          q: 'jane',
          type: 'Inbox',
          sort: 'asc',
          agent_id: '42',
          operation_key: 'voice_reply',
          since: '100',
          until: '200',
        })
      ).toEqual({
        page: 2,
        q: 'jane',
        types: ['Inbox'],
        sort: 'asc',
        agent_id: 42,
        operation_key: 'voice_reply',
        since: 100,
        until: 200,
      });
    });

    it('defaults to page 1 and drops unknown values', () => {
      expect(
        auditLogFiltersFromQuery({ sort: 'sideways', range: 'last7days' })
      ).toEqual({ page: 1 });
    });

    it('ignores a half open date window', () => {
      expect(auditLogFiltersFromQuery({ since: '100' })).toEqual({ page: 1 });
    });

    it('drops unknown agent and operation filters', () => {
      expect(
        auditLogFiltersFromQuery({ agent_id: '0', operation_key: 'unknown' })
      ).toEqual({ page: 1 });
    });
  });

  describe('#buildAuditLogRouteQuery', () => {
    it('drops blank values', () => {
      expect(
        buildAuditLogRouteQuery({
          q: '',
          type: 'Inbox',
          range: 'last7days',
          page: undefined,
        })
      ).toEqual({ type: 'Inbox', range: 'last7days' });
    });
  });
});

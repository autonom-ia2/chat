import {
  extractChangedAccountUserValues,
  generateTranslationPayload,
  generateLogActionKey,
  translateLogPayload,
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
          since: '100',
          until: '200',
        })
      ).toEqual({
        page: 2,
        q: 'jane',
        types: ['Inbox'],
        sort: 'asc',
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

describe('excluir de vez no CRM (#2096)', () => {
  const item = (action, audited_changes) => ({
    auditable_type: 'Account',
    action,
    user_id: 1,
    auditable_id: 7,
    audited_changes,
  });
  const agentes = [{ id: 1, name: 'Marta' }];

  it('uma frase por alvo, e o contato pela escolha dos cards', () => {
    expect(
      generateLogActionKey(item('crm_hard_delete', { alvo: 'cards' }))
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CARDS');
    expect(
      generateLogActionKey(item('crm_hard_delete', { alvo: 'funil' }))
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.FUNIL');
    expect(
      generateLogActionKey(
        item('crm_hard_delete', { alvo: 'contato', modo: 'delete' })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_APAGANDO');
    expect(
      generateLogActionKey(
        item('crm_hard_delete', { alvo: 'contato', modo: 'keep' })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_MANTENDO');
    expect(
      generateLogActionKey(
        item('crm_hard_delete', {
          alvo: 'contato',
          modo: 'keep',
          reunioes_canceladas: 0,
          reunioes_so_aqui: 0,
        })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_MANTENDO');
    expect(
      generateLogActionKey(
        item('crm_hard_delete', {
          alvo: 'contato',
          modo: 'keep',
          reunioes_canceladas: 2,
          reunioes_so_aqui: 0,
        })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_MANTENDO_REUNIOES');
    expect(
      generateLogActionKey(
        item('crm_hard_delete', {
          alvo: 'contato',
          modo: 'keep',
          reunioes_canceladas: 2,
          reunioes_so_aqui: 1,
        })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_MANTENDO_REUNIOES_SO_AQUI');
    expect(
      generateLogActionKey(item('crm_hard_delete_failed', { alvo: 'funil' }))
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.FUNIL_FALHOU');
  });

  it('leva só ids e contagens para a frase', () => {
    const payload = generateTranslationPayload(
      item('crm_hard_delete', {
        alvo: 'funil',
        cards_apagados: 2,
        card_ids: [4, 5],
        pipeline_id: 9,
        cards_movidos: 3,
      }),
      agentes
    );
    expect(payload).toMatchObject({
      agentName: 'Marta',
      cardsApagados: 2,
      cardsMovidos: 3,
      pipelineId: 9,
    });
    expect(payload.motivo).toBeUndefined();
  });

  // #2096 (23/10): a exclusão de contato por qualquer caminho conta as reuniões canceladas.
  it('leva quantas reuniões o contato excluído teve canceladas', () => {
    const payload = generateTranslationPayload(
      item('crm_hard_delete', {
        alvo: 'contato',
        modo: 'keep',
        contact_id: 7,
        cards_mantidos: 1,
        reunioes_canceladas: 2,
        reunioes_so_aqui: 1,
      }),
      agentes
    );
    expect(payload).toMatchObject({
      contactId: 7,
      cardsMantidos: 1,
      reunioesCanceladas: 2,
      reunioesSoAqui: 1,
    });
  });

  // #2143: o contato sem card nem reunião que levou só leads da Prospecção tem frase própria, com as duas contagens.
  it('o contato que levou só leads tem frase própria', () => {
    const leads = item('crm_hard_delete', {
      alvo: 'contato',
      modo: 'leads',
      contact_id: 7,
      leads_apagados: 2,
      leads_minimizados: 1,
    });
    expect(generateLogActionKey(leads)).toBe(
      'AUDIT_LOGS.CRM_EXCLUIR.CONTATO_LEADS'
    );
    expect(generateTranslationPayload(leads, agentes)).toMatchObject({
      contactId: 7,
      leadsApagados: 2,
      leadsMinimizados: 1,
    });
  });

  it('o contato que a ação em massa não excluiu tem frase própria', () => {
    expect(
      generateLogActionKey(
        item('crm_hard_delete_failed', {
          alvo: 'contato',
          motivo: 'meeting_cancel_failed',
        })
      )
    ).toBe('AUDIT_LOGS.CRM_EXCLUIR.CONTATO_FALHOU');
  });

  it('traduz o motivo da desistência, e o código novo cai na frase geral', () => {
    const t = chave => `t(${chave})`;
    const conhecido = generateTranslationPayload(
      item('crm_hard_delete_failed', {
        alvo: 'funil',
        motivo: 'target_unavailable',
      }),
      agentes
    );
    expect(translateLogPayload(conhecido, t).motivo).toBe(
      't(AUDIT_LOGS.CRM_EXCLUIR.MOTIVOS.TARGET_UNAVAILABLE)'
    );
    const novo = generateTranslationPayload(
      item('crm_hard_delete_failed', {
        alvo: 'funil',
        motivo: 'card_rejected',
      }),
      agentes
    );
    expect(translateLogPayload(novo, t).motivo).toBe(
      't(AUDIT_LOGS.CRM_EXCLUIR.MOTIVOS.OUTRO)'
    );
  });
});

describe('pausar ou ativar anúncio da Meta (#2161)', () => {
  const item = audited_changes => ({
    auditable_type: 'Account',
    action: 'meta_ads_ad_status',
    user_id: 1,
    auditable_id: 7,
    audited_changes,
  });

  it('uma frase para pausar e outra para ativar, com o nome do anúncio', () => {
    const pausou = item({ ad_id: '123', ad_name: 'Capa', status: 'PAUSED' });

    expect(generateLogActionKey(pausou)).toBe('AUDIT_LOGS.META_ADS.PAUSED');
    expect(generateLogActionKey(item({ ad_id: '123', status: 'ACTIVE' }))).toBe(
      'AUDIT_LOGS.META_ADS.ACTIVE'
    );
    expect(
      generateTranslationPayload(pausou, [{ id: 1, name: 'Marta' }])
    ).toMatchObject({ agentName: 'Marta', adId: '123', adName: 'Capa' });
  });

  it('sem nome no cache, mostra o id', () => {
    expect(
      generateTranslationPayload(item({ ad_id: '123', status: 'PAUSED' }), [])
    ).toMatchObject({ adName: '123' });
  });
});

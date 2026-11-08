import { describe, it, expect } from 'vitest';
import {
  applyRoleFilter,
  canOperateConversation,
  readsOnlyConversations,
} from '../helpers';
import getters from '../getters';

// Quem só lê conversas (conversation_view, #1800): vê na lista, não opera. Mesma regra do servidor
// (ConversationPolicy#view? e #show?).
describe('quem só lê conversas', () => {
  const daOutraPessoa = { meta: { assignee: { id: 2 } } };
  const minha = { meta: { assignee: { id: 1 } } };
  const role = 'custom_role';

  it('vê a conversa de outra pessoa, mas não opera', () => {
    const permissions = ['conversation_view', 'custom_role'];

    expect(applyRoleFilter(daOutraPessoa, role, permissions, 1)).toBe(true);
    expect(canOperateConversation(daOutraPessoa, role, permissions, 1)).toBe(
      false
    );
    expect(readsOnlyConversations(permissions)).toBe(true);
  });

  it('com o trio junto, opera só a dela e lê as outras', () => {
    const permissions = [
      'conversation_view',
      'conversation_participating_manage',
      'custom_role',
    ];

    expect(canOperateConversation(minha, role, permissions, 1)).toBe(true);
    expect(canOperateConversation(daOutraPessoa, role, permissions, 1)).toBe(
      false
    );
    expect(applyRoleFilter(daOutraPessoa, role, permissions, 1)).toBe(true);
    expect(readsOnlyConversations(permissions)).toBe(false);
  });

  describe('mesma regra do ConversationPolicy#show?', () => {
    const vendas = ['conversation_view', 'conversation_participating_manage'];
    const semResponsavel = [
      'conversation_view',
      'conversation_unassigned_manage',
    ];
    const comRobo = {
      meta: { assignee: { id: 1 }, assignee_type: 'AgentBot' },
    };

    it('atende a em que participa sem ser responsável', () => {
      expect(canOperateConversation(daOutraPessoa, role, vendas, 1, true)).toBe(
        true
      );
      expect(canOperateConversation(daOutraPessoa, role, vendas, 1)).toBe(
        false
      );
    });

    it('robô com o mesmo id não faz da conversa "a dela"', () => {
      expect(canOperateConversation(comRobo, role, vendas, 1)).toBe(false);
    });

    it('assistente (Captain::Assistant) com o mesmo id também não (#2249)', () => {
      const comAssistente = {
        meta: { assignee: { id: 1 }, assignee_type: 'Captain::Assistant' },
      };
      expect(canOperateConversation(comAssistente, role, vendas, 1)).toBe(
        false
      );
    });

    it('sem responsável: só a que espera pessoa, como awaiting_person?', () => {
      const ninguem = { meta: {} };
      const roboPassou = {
        ...comRobo,
        additional_attributes: { bot_handoff_waiting_since: '2026-10-18' },
      };

      expect(canOperateConversation(ninguem, role, semResponsavel, 1)).toBe(
        true
      );
      expect(canOperateConversation(comRobo, role, semResponsavel, 1)).toBe(
        false
      );
      expect(canOperateConversation(roboPassou, role, semResponsavel, 1)).toBe(
        true
      );
      expect(
        canOperateConversation(daOutraPessoa, role, semResponsavel, 1)
      ).toBe(false);
    });
  });

  it('nada muda para administrador, agente e cargo com o trio', () => {
    expect(canOperateConversation(daOutraPessoa, 'administrator', [], 1)).toBe(
      true
    );
    expect(canOperateConversation(daOutraPessoa, 'agent', [], 1)).toBe(true);
    expect(
      canOperateConversation(daOutraPessoa, role, ['conversation_manage'], 1)
    ).toBe(true);
    expect(
      applyRoleFilter(
        daOutraPessoa,
        role,
        ['conversation_participating_manage'],
        1
      )
    ).toBe(false);
    expect(readsOnlyConversations(['conversation_manage'])).toBe(false);
    expect(readsOnlyConversations([])).toBe(false);
  });
});

describe('getter canOperateConversation', () => {
  const conversa = { id: 9, meta: { assignee: { id: 2 } } };
  const rootGetters = (permissions, participantes = []) => ({
    getCurrentUser: {
      id: 1,
      accounts: [{ id: 3, custom_role_id: 5, permissions }],
    },
    getCurrentAccountId: 3,
    'conversationWatchers/getByConversationId': () => participantes,
  });
  const pode = (permissions, participantes, alvo = conversa) =>
    getters.canOperateConversation(
      {},
      {},
      {},
      rootGetters(permissions, participantes)
    )(alvo);

  // De propósito: sem conversation_view, tudo fica como antes do #1804. O servidor segue a porta (show?), e ninguém que
  // opera vê o aviso piscar enquanto a lista de participantes carrega.
  it('sem conversation_view, nada se esconde, como antes do #1804', () => {
    expect(pode(['conversation_participating_manage'])).toBe(true);
    expect(pode(['conversation_participating_manage'], [], {})).toBe(true);
  });

  it('com conversation_view, participar da conversa aberta libera responder', () => {
    const vendas = ['conversation_view', 'conversation_participating_manage'];

    expect(pode(vendas)).toBe(false);
    expect(pode(vendas, [{ id: 1 }])).toBe(true);
    expect(pode(['conversation_view'], [{ id: 1 }])).toBe(false);
  });
});

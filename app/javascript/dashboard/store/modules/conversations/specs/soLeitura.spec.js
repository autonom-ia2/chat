import { describe, it, expect } from 'vitest';
import {
  applyRoleFilter,
  canOperateConversation,
  readsOnlyConversations,
} from '../helpers';

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

import {
  humanAssigneeId,
  isAssignedToUser,
  isHumanAssignee,
} from '../assigneeHelper';

const conversa = (assignee, assigneeType) => ({
  meta: { assignee, assignee_type: assigneeType },
});

describe('assigneeHelper (#2249)', () => {
  it('reconhece a pessoa responsável pelo id e pelo tipo', () => {
    expect(isAssignedToUser(conversa({ id: 5 }, 'User'), 5)).toBe(true);
    expect(humanAssigneeId(conversa({ id: 5 }, 'User'))).toBe(5);
  });

  ['AgentBot', 'Captain::Assistant'].forEach(tipo => {
    it(`${tipo} com o mesmo id do usuário não é dele`, () => {
      const chat = conversa({ id: 5, name: 'Robô' }, tipo);
      expect(isAssignedToUser(chat, 5)).toBe(false);
      expect(humanAssigneeId(chat)).toBeNull();
      expect(isHumanAssignee(chat.meta)).toBe(false);
    });
  });

  it('payload sem assignee_type conta como pessoa', () => {
    expect(isAssignedToUser(conversa({ id: 5 }, undefined), 5)).toBe(true);
    expect(isAssignedToUser({ meta: { assignee: { id: 5 } } }, 5)).toBe(true);
  });

  it('outra pessoa, sem responsável ou sem usuário: não é minha', () => {
    expect(isAssignedToUser(conversa({ id: 6 }, 'User'), 5)).toBe(false);
    expect(isAssignedToUser(conversa(null, null), 5)).toBe(false);
    expect(isAssignedToUser({}, 5)).toBe(false);
    expect(isAssignedToUser(conversa({ id: 5 }, 'User'), undefined)).toBe(
      false
    );
    expect(humanAssigneeId(undefined)).toBeNull();
  });
});

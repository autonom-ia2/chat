import { isHookActive, isCrmAiKeyPending } from '../crmAiKey';

describe('crmAiKey', () => {
  describe('isHookActive', () => {
    it('aceita o hook conectado e ligado', () => {
      expect(isHookActive({ status: true, settings: { enabled: true } })).toBe(
        true
      );
    });

    it('aceita o hook sem as chaves opcionais, que é como a API responde', () => {
      expect(isHookActive({ id: 1 })).toBe(true);
    });

    it('recusa o hook com status desligado', () => {
      expect(isHookActive({ status: false, settings: { enabled: true } })).toBe(
        false
      );
    });

    it('recusa o hook com a IA desligada nas configurações', () => {
      expect(isHookActive({ status: true, settings: { enabled: false } })).toBe(
        false
      );
    });

    it('recusa hook ausente', () => {
      expect(isHookActive(undefined)).toBe(false);
      expect(isHookActive(null)).toBe(false);
    });
  });

  describe('isCrmAiKeyPending', () => {
    it('a conta precisa da chave quando não há hook', () => {
      expect(isCrmAiKeyPending({ id: 'crm_kanban_ai', hooks: [] })).toBe(true);
    });

    it('a conta precisa da chave quando o hook está desligado', () => {
      expect(
        isCrmAiKeyPending({
          id: 'crm_kanban_ai',
          hooks: [{ status: true, settings: { enabled: false } }],
        })
      ).toBe(true);
    });

    it('a conta não precisa mais da chave com o hook ligado', () => {
      expect(
        isCrmAiKeyPending({
          id: 'crm_kanban_ai',
          hooks: [{ status: true, settings: { enabled: true } }],
        })
      ).toBe(false);
    });

    it('trata integração ausente como pendente, em vez de estourar', () => {
      expect(isCrmAiKeyPending(undefined)).toBe(true);
      expect(isCrmAiKeyPending({})).toBe(true);
    });
  });
});

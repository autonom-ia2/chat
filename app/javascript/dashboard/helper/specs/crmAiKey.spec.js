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

  // `enabled` vem do backend e, para esta integração, é o CredentialResolver:
  // vale tanto a chave da conta quanto a da instalação.
  describe('isCrmAiKeyPending', () => {
    it('a conta precisa da chave quando o backend diz que não há credencial', () => {
      expect(
        isCrmAiKeyPending({ id: 'crm_kanban_ai', enabled: false, hooks: [] })
      ).toBe(true);
    });

    it('a conta não precisa da chave quando o backend diz que há credencial', () => {
      expect(
        isCrmAiKeyPending({
          id: 'crm_kanban_ai',
          enabled: true,
          hooks: [{ status: true, settings: { enabled: true } }],
        })
      ).toBe(false);
    });

    it('não pede chave na conta que usa a chave da instalação, sem hook próprio', () => {
      expect(
        isCrmAiKeyPending({ id: 'crm_kanban_ai', enabled: true, hooks: [] })
      ).toBe(false);
    });

    it('pede chave quando o hook existe mas o backend não resolveu credencial', () => {
      expect(
        isCrmAiKeyPending({
          id: 'crm_kanban_ai',
          enabled: false,
          hooks: [{ status: true, settings: { enabled: false } }],
        })
      ).toBe(true);
    });

    it('trata integração ausente como pendente, em vez de estourar', () => {
      expect(isCrmAiKeyPending(undefined)).toBe(true);
      expect(isCrmAiKeyPending({})).toBe(true);
    });
  });
});

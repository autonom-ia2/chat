import AcompanharConversaAPI from '../acompanharConversa';
import ApiClient from '../ApiClient';

// #2138 — a chamada leva só o id de quem entra ou sai; a lista dos outros nunca vai.
describe('#AcompanharConversaAPI', () => {
  it('creates correct instance', () => {
    expect(AcompanharConversaAPI).toBeInstanceOf(ApiClient);
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      vi.clearAllMocks();
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#incluir faz POST com um id só', () => {
      AcompanharConversaAPI.incluir(42, 7);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/conversations/42/participants',
        { user_ids: [7] }
      );
      expect(axiosMock.patch).not.toHaveBeenCalled();
    });

    it('#tirar faz DELETE com um id só', () => {
      AcompanharConversaAPI.tirar(42, 7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/conversations/42/participants',
        { data: { user_ids: [7] } }
      );
      expect(axiosMock.patch).not.toHaveBeenCalled();
    });

    it('#quemAcompanha lê a lista', () => {
      AcompanharConversaAPI.quemAcompanha(42);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/conversations/42/participants'
      );
    });
  });
});

import wahaInboxAPI from '../wahaInbox';
import ApiClient from '../ApiClient';

describe('#WahaInboxAPI', () => {
  it('creates correct instance', () => {
    expect(wahaInboxAPI).toBeInstanceOf(ApiClient);
    expect(wahaInboxAPI).toHaveProperty('connection');
    expect(wahaInboxAPI).toHaveProperty('status');
    expect(wahaInboxAPI).toHaveProperty('reconnect');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    // #1941: só o estado da conexão, sem QR, para a faixa da lista da caixa.
    it('#status', () => {
      wahaInboxAPI.status(7);
      expect(axiosMock.get).toHaveBeenCalledWith(
        `${wahaInboxAPI.url}/7/status`
      );
    });

    it('#connection', () => {
      wahaInboxAPI.connection(7);
      expect(axiosMock.get).toHaveBeenCalledWith(
        `${wahaInboxAPI.url}/7/connection`
      );
    });
  });
});

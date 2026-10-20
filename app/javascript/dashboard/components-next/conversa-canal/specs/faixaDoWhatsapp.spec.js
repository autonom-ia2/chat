// Faixa "WhatsApp desconectado" na lista de uma caixa WAHA comum (#1941, item 5):
// consulta ao abrir e a cada 60 s, só nos estados que pedem ação, para quem vê a caixa;
// troca de caixa e saída da lista param a consulta; erro de rede ou recusa, sem faixa.
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import WahaInboxAPI from 'dashboard/api/wahaInbox';
import FaixaDoWhatsapp from '../faixa-whatsapp/FaixaDoWhatsapp.vue';
import enCanal from 'dashboard/i18n/locale/en/conversaCanal.json';
import ptCanal from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import enCaixas from 'dashboard/i18n/locale/en/inboxMgmt.json';
import ptCaixas from 'dashboard/i18n/locale/pt_BR/inboxMgmt.json';
import { INTERVALO_DA_CONSULTA } from '../faixa-whatsapp/useEstadoDaConexao';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/api/wahaInbox', () => ({ default: { status: vi.fn() } }));
// A rota das configurações abre? (flag e permissão da rota, usePodeAbrir)
const podeAbrir = vi.fn(() => true);
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir }),
}));

const CAIXA_WAHA = {
  id: 3,
  channel_type: INBOX_TYPES.API,
  waha_provider: true,
};
const OUTRA_WAHA = {
  id: 8,
  channel_type: INBOX_TYPES.API,
  waha_provider: true,
};
const CAIXA_API = {
  id: 4,
  channel_type: INBOX_TYPES.API,
  waha_provider: false,
};
const CAIXA_OFICIAL = { id: 5, channel_type: INBOX_TYPES.WHATSAPP };

const ADMIN = { accounts: [{ id: 1, permissions: ['administrator'] }] };
const AGENTE = { accounts: [{ id: 1, permissions: ['agent'] }] };
const GERENTE_DE_CAIXAS = {
  accounts: [{ id: 1, custom_role_id: 9, permissions: ['inbox_manage'] }],
};
const SO_VE_CAIXAS = {
  accounts: [{ id: 1, custom_role_id: 9, permissions: ['inbox_view'] }],
};

const loja = usuario =>
  createStore({
    getters: {
      getCurrentUser: () => usuario,
      getCurrentAccountId: () => 1,
    },
  });

const montar = ({ caixa = CAIXA_WAHA, usuario = ADMIN } = {}) =>
  mount(FaixaDoWhatsapp, {
    props: { caixa },
    global: { plugins: [loja(usuario)] },
  });

const responde = status =>
  WahaInboxAPI.status.mockResolvedValue({
    data: { status, connected: status === 'connected' },
  });

const recusa = status =>
  WahaInboxAPI.status.mockRejectedValue(
    Object.assign(new Error('recusada'), { response: { status } })
  );

const faixa = wrapper => wrapper.find('[data-faixa="whatsapp-desconectado"]');

beforeEach(() => {
  vi.useFakeTimers();
  WahaInboxAPI.status.mockReset();
  push.mockReset();
  podeAbrir.mockReset();
  podeAbrir.mockReturnValue(true);
});

afterEach(() => {
  vi.useRealTimers();
});

describe('FaixaDoWhatsapp (#1941)', () => {
  it.each([
    ['en', enCanal, enCaixas],
    ['pt_BR', ptCanal, ptCaixas],
  ])('os textos existem em %s', (_, canal, caixas) => {
    const faixaTextos = canal.CONVERSA_CANAL.FAIXA_WHATSAPP;
    ['SEM_MENSAGENS', 'RECONECTAR', 'PECA_AO_ADMIN'].forEach(chave =>
      expect(faixaTextos[chave]).toBeTruthy()
    );
    const estados = caixas.INBOX_MGMT.WAHA_CONNECTION.STATUS;
    ['AWAITING', 'FAILED', 'DISCONNECTED'].forEach(chave =>
      expect(estados[chave]).toBeTruthy()
    );
  });

  it.each([
    ['awaiting_scan', 'INBOX_MGMT.WAHA_CONNECTION.STATUS.AWAITING'],
    ['failed', 'INBOX_MGMT.WAHA_CONNECTION.STATUS.FAILED'],
    ['disconnected', 'INBOX_MGMT.WAHA_CONNECTION.STATUS.DISCONNECTED'],
  ])('mostra a faixa em %s, com o estado e o botão', async (status, rotulo) => {
    responde(status);
    const wrapper = montar();
    await flushPromises();

    expect(WahaInboxAPI.status).toHaveBeenCalledWith(CAIXA_WAHA.id);
    expect(faixa(wrapper).exists()).toBe(true);
    expect(wrapper.text()).toContain(rotulo);
    expect(wrapper.text()).toContain(
      'CONVERSA_CANAL.FAIXA_WHATSAPP.SEM_MENSAGENS'
    );
    expect(wrapper.get('button').text()).toBe(
      'CONVERSA_CANAL.FAIXA_WHATSAPP.RECONECTAR'
    );
  });

  it.each(['connected', 'connecting', 'unknown', undefined])(
    'sem faixa em %s',
    async status => {
      responde(status);
      const wrapper = montar();
      await flushPromises();

      expect(WahaInboxAPI.status).toHaveBeenCalledTimes(1);
      expect(faixa(wrapper).exists()).toBe(false);
    }
  );

  it('o botão leva à aba de conexão da caixa', async () => {
    responde('disconnected');
    const wrapper = montar();
    await flushPromises();

    await wrapper.get('button').trigger('click');

    const destino = {
      name: 'settings_inbox_show',
      params: { accountId: 1, inboxId: CAIXA_WAHA.id, tab: 'connection' },
    };
    expect(podeAbrir).toHaveBeenCalledWith(destino);
    expect(push).toHaveBeenCalledWith(destino);
  });

  it('função personalizada que gerencia caixas vê o botão', async () => {
    responde('failed');
    const wrapper = montar({ usuario: GERENTE_DE_CAIXAS });
    await flushPromises();

    expect(wrapper.find('button').exists()).toBe(true);
  });

  it.each([
    ['função que só vê caixas', SO_VE_CAIXAS, true],
    ['administrador com a rota fechada (flag desligada)', ADMIN, false],
  ])('%s: faixa sem botão', async (_, usuario, rotaAbre) => {
    podeAbrir.mockReturnValue(rotaAbre);
    responde('disconnected');
    const wrapper = montar({ usuario });
    await flushPromises();

    expect(faixa(wrapper).exists()).toBe(true);
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'CONVERSA_CANAL.FAIXA_WHATSAPP.PECA_AO_ADMIN'
    );
  });

  it('agente sem acesso às configurações vê a faixa sem botão', async () => {
    responde('disconnected');
    const wrapper = montar({ usuario: AGENTE });
    await flushPromises();

    expect(faixa(wrapper).exists()).toBe(true);
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'CONVERSA_CANAL.FAIXA_WHATSAPP.PECA_AO_ADMIN'
    );
  });

  it.each([
    ['sem caixa', null],
    ['caixa API sem WAHA', CAIXA_API],
    ['WhatsApp oficial', CAIXA_OFICIAL],
    ['caixa ainda não carregada', {}],
  ])('%s: não consulta e não mostra', async (_, caixa) => {
    responde('disconnected');
    const wrapper = montar({ caixa });
    await flushPromises();
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA * 2);
    await flushPromises();

    expect(WahaInboxAPI.status).not.toHaveBeenCalled();
    expect(faixa(wrapper).exists()).toBe(false);
  });

  it('caixa que carrega depois da lista: consulta quando chega', async () => {
    responde('awaiting_scan');
    const wrapper = montar({ caixa: {} });
    await flushPromises();
    expect(WahaInboxAPI.status).not.toHaveBeenCalled();

    await wrapper.setProps({ caixa: CAIXA_WAHA });
    await flushPromises();

    expect(WahaInboxAPI.status).toHaveBeenCalledWith(CAIXA_WAHA.id);
    expect(faixa(wrapper).exists()).toBe(true);
  });

  it('consulta de novo a cada 60 s e acompanha o estado', async () => {
    responde('connected');
    const wrapper = montar();
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(false);

    responde('disconnected');
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA - 1);
    await flushPromises();
    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(1);
    await flushPromises();
    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(2);
    expect(faixa(wrapper).exists()).toBe(true);

    responde('connected');
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA);
    await flushPromises();
    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(3);
    expect(faixa(wrapper).exists()).toBe(false);
  });

  it('para de consultar ao sair da lista', async () => {
    responde('disconnected');
    const wrapper = montar();
    await flushPromises();

    wrapper.unmount();
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA * 3);
    await flushPromises();

    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(1);
  });

  it('troca de caixa: para a antiga, consulta a nova e some com a faixa', async () => {
    responde('disconnected');
    const wrapper = montar();
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(true);

    responde('connected');
    await wrapper.setProps({ caixa: OUTRA_WAHA });
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(false);
    expect(WahaInboxAPI.status).toHaveBeenLastCalledWith(OUTRA_WAHA.id);

    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA);
    await flushPromises();
    const ids = WahaInboxAPI.status.mock.calls.map(([id]) => id);
    expect(ids).toEqual([CAIXA_WAHA.id, OUTRA_WAHA.id, OUTRA_WAHA.id]);
  });

  it('trocar para uma caixa que não é WAHA para a consulta', async () => {
    responde('disconnected');
    const wrapper = montar();
    await flushPromises();

    await wrapper.setProps({ caixa: CAIXA_OFICIAL });
    await nextTick();
    expect(faixa(wrapper).exists()).toBe(false);

    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA * 2);
    await flushPromises();
    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(1);
  });

  it('resposta atrasada da caixa antiga não pinta a faixa da nova', async () => {
    let responderAntiga;
    WahaInboxAPI.status.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          responderAntiga = resolve;
        })
    );
    const wrapper = montar();

    responde('connected');
    await wrapper.setProps({ caixa: OUTRA_WAHA });
    await flushPromises();

    responderAntiga({ data: { status: 'disconnected', connected: false } });
    await flushPromises();

    expect(faixa(wrapper).exists()).toBe(false);
  });

  it('erro de rede: sem faixa, e tenta de novo na próxima volta', async () => {
    responde('disconnected');
    const wrapper = montar();
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(true);

    WahaInboxAPI.status.mockRejectedValue(new Error('Network Error'));
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA);
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(false);

    responde('disconnected');
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA);
    await flushPromises();
    expect(WahaInboxAPI.status).toHaveBeenCalledTimes(3);
    expect(faixa(wrapper).exists()).toBe(true);
  });

  it('erro do servidor (500): sem faixa, e continua consultando', async () => {
    recusa(500);
    const wrapper = montar();
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(false);

    responde('failed');
    vi.advanceTimersByTime(INTERVALO_DA_CONSULTA);
    await flushPromises();
    expect(faixa(wrapper).exists()).toBe(true);
  });

  it.each([401, 403, 404, 422])(
    'recusa %s: sem faixa e sem novas consultas',
    async status => {
      recusa(status);
      const wrapper = montar();
      await flushPromises();
      vi.advanceTimersByTime(INTERVALO_DA_CONSULTA * 3);
      await flushPromises();

      expect(faixa(wrapper).exists()).toBe(false);
      expect(WahaInboxAPI.status).toHaveBeenCalledTimes(1);
    }
  );
});

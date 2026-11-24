import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enReenvio from 'dashboard/i18n/locale/en/reenvioHorario.json';
import enDuasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';
import ResultSegundaMensagem from '../ResultSegundaMensagem.vue';

// #3101 — a segunda mensagem do "Mandar de novo" no resultado da primeira campanha.
const R = enReenvio.REENVIO_HORARIO.RESULTADO;

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const RouterLinkStub = {
  props: ['to'],
  template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
};

const montar = (segunda, { permissions = ['administrator'] } = {}) => {
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions }] }),
      getCurrentAccountId: () => 1,
      'accounts/getAccount': () => () => ({ timezone: 'America/Sao_Paulo' }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enReenvio, ...enDuasVersoes } },
  });
  return mount(ResultSegundaMensagem, {
    props: {
      segunda: {
        dias: 3,
        quem: 'nao_respondeu',
        previsto_em: null,
        campanha: null,
        ...segunda,
      },
    },
    global: {
      plugins: [store, i18n],
      stubs: { 'router-link': RouterLinkStub },
    },
  });
};

const enviada = extra => ({
  status: 'enviado',
  campanha: {
    channel: 'sms',
    id: 42,
    name: 'Parcela · second message',
    processing: false,
    receberam: 12,
    responderam: 1,
    ...extra,
  },
});

describe('ResultSegundaMensagem', () => {
  it('enviada: para quem saiu, quantos receberam e responderam, e o caminho para o resultado dela', () => {
    const w = montar(enviada());

    expect(w.get('[data-frase]').text()).toBe(
      "Went out to people who didn't reply: 12 got it and 1 replied."
    );
    expect(w.get('[data-receberam]').text()).toBe('12 got it');
    expect(w.get('[data-responderam]').text()).toBe('1 replied');
    const link = w.get('[data-ver-segunda]');
    expect(link.text()).toBe(R.VER);
    expect(link.attributes('aria-label')).toBe(
      'See the result of Parcela · second message'
    );
    expect(JSON.parse(link.attributes('data-to'))).toEqual({
      name: 'campaigns_journey_result',
      params: { channel: 'sms', campaignId: '42' },
    });
    expect(w.find('[data-saindo]').exists()).toBe(false);
    expect(w.find('[data-criar-campanha]').exists()).toBe(false);
  });

  it('enviada e ainda saindo: avisa que os números sobem', () => {
    const w = montar(enviada({ processing: true, receberam: 40 }));
    expect(w.get('[data-receberam]').text()).toBe('40 got it');
    expect(w.get('[data-saindo]').text()).toBe(R.SAINDO);
  });

  // #3206: a varredura grava enviado logo que cria a campanha nova; antes de alguém receber, nunca "saiu para 0".
  it('enviada há pouco, sem ninguém ter recebido: diz que está começando a sair', () => {
    const w = montar(enviada({ processing: true, receberam: 0 }));
    expect(w.get('[data-frase]').text()).toBe(
      "It's starting to go out now, to people who didn't reply."
    );
    expect(w.find('[data-receberam]').exists()).toBe(false);
    expect(w.find('[data-saindo]').exists()).toBe(false);
    expect(w.find('[data-ver-segunda]').exists()).toBe(true);
  });

  it('enviada, mas a campanha nova foi apagada: diz isso, sem caminho', () => {
    const w = montar({ status: 'enviado' });
    expect(w.get('[data-frase]').text()).toBe(R.APAGADA);
    expect(w.find('[data-ver-segunda]').exists()).toBe(false);
  });

  it('aguardando sem data: sai N dias depois que a primeira terminar', () => {
    const w = montar({ status: 'aguardando' });
    expect(w.get('[data-frase]').text()).toBe(
      "Goes out 3 days after this campaign finishes, to people who didn't reply."
    );
  });

  it('aguardando com data: diz o dia e a hora no fuso da conta, para quem nem leu', () => {
    const w = montar({
      status: 'aguardando',
      quem: 'nao_leu',
      previsto_em: Math.floor(Date.UTC(2030, 0, 15, 15, 0) / 1000),
    });
    expect(w.get('[data-frase]').text()).toBe(
      "Goes out on January 15 at 12:00 PM, to people who didn't even read it."
    );
  });

  it('sem ninguém: não precisou sair, sem botão', () => {
    const w = montar({ status: 'sem_ninguem' });
    expect(w.get('[data-frase]').text()).toBe(R.SEM_NINGUEM);
    expect(w.find('[data-criar-campanha]').exists()).toBe(false);
    expect(w.find('[data-ver-segunda]').exists()).toBe(false);
  });

  it.each([
    ['cancelado', R.CANCELADO.replace('{quem}', "didn't reply")],
    ['falhou', R.FALHOU.replace('{quem}', "didn't reply")],
  ])(
    '%s: diz por que não saiu e leva a criar outra campanha',
    (status, texto) => {
      const w = montar({ status });
      expect(w.attributes('data-segunda-mensagem')).toBe(status);
      expect(w.get('[data-frase]').text()).toBe(texto);
      const criar = w.get('[data-criar-campanha]');
      expect(criar.text()).toBe(R.CRIAR);
      expect(JSON.parse(criar.attributes('data-to'))).toEqual({
        name: 'campaigns_journey_new',
      });
    }
  );

  it('quem só vê campanhas não recebe o botão de criar', () => {
    const w = montar({ status: 'falhou' }, { permissions: ['campaign_view'] });
    expect(w.find('[data-criar-campanha]').exists()).toBe(false);
  });

  it('cancelada de quem nem leu: fala de quem nem leu', () => {
    const w = montar({ status: 'cancelado', quem: 'nao_leu' });
    expect(w.get('[data-frase]').text()).toContain(
      "remind people who didn't even read it"
    );
  });
});

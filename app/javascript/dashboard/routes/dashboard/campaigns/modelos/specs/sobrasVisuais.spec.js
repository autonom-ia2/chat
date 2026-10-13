import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import ModeloCelular from '../components/ModeloCelular.vue';
import ModeloEnviadoPage from '../pages/ModeloEnviadoPage.vue';
import { botoesNoCelular } from '../helpers/regraEstrutural';

// Sobras da auditoria visual (#1387): a prévia com mais de 3 botões (L8) e a
// conta que ficou sem o pedido na criação em várias contas (L12).
const rota = vi.hoisted(() => ({ query: {} }));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('../api/modelosWhatsapp', () => ({ default: {} }));

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en } });

const resposta = texto => ({ tipo: 'resposta', texto, valor: '' });
const celular = botoes =>
  mount(ModeloCelular, {
    props: {
      remetente: 'Hub2you',
      conteudo: {
        formato: 'padrao',
        topo: { tipo: 'nenhum' },
        texto: [{ t: 'texto', v: 'Oi!' }],
        exemplos: {},
        rodape: '',
        botoes,
      },
    },
    global: { plugins: [i18n()] },
  });

describe('botoesNoCelular (L8)', () => {
  it('shows up to 3 buttons as they are', () => {
    const tres = ['a', 'b', 'c'].map(resposta);
    expect(botoesNoCelular(tres)).toEqual({ aVista: tres, escondidos: 0 });
  });

  it('with more than 3, shows the first 2 and hides the rest, like WhatsApp', () => {
    const cinco = ['a', 'b', 'c', 'd', 'e'].map(resposta);
    const { aVista, escondidos } = botoesNoCelular(cinco);
    expect(aVista.map(botao => botao.texto)).toEqual(['a', 'b']);
    expect(escondidos).toBe(3);
  });
});

describe('ModeloCelular (L8)', () => {
  it('draws "See all options" in place of the hidden buttons', () => {
    const wrapper = celular(['Sim', 'Não', 'Talvez', 'Depois'].map(resposta));
    const botoes = wrapper.findAll('[data-celular-botao]');
    expect(botoes.map(botao => botao.text())).toEqual(['Sim', 'Não']);
    expect(wrapper.find('[data-celular-ver-todas]').text()).toBe(
      'See all options'
    );
  });

  it('keeps 3 buttons without "See all options"', () => {
    const wrapper = celular(['Sim', 'Não', 'Talvez'].map(resposta));
    expect(wrapper.findAll('[data-celular-botao]')).toHaveLength(3);
    expect(wrapper.find('[data-celular-ver-todas]').exists()).toBe(false);
  });
});

describe('ModeloEnviadoPage (L12)', () => {
  const enviado = query => {
    rota.query = query;
    return mount(ModeloEnviadoPage, {
      global: { plugins: [i18n()], stubs: { Button: true } },
    });
  };

  it('names the account left without the request, and why', () => {
    const wrapper = enviado({
      ids: '1',
      semPedido: ['Hub2You Filial Sul'],
      motivo: 'Account down.',
    });
    expect(wrapper.find('[data-sem-pedido]').text()).toBe(
      'The request did not go to the account Hub2You Filial Sul. Account down.'
    );
  });

  it('names every account left without the request', () => {
    const wrapper = enviado({ ids: '1', semPedido: ['Sul', 'Norte'] });
    expect(wrapper.find('[data-sem-pedido]').text()).toBe(
      'The request did not go to the accounts Sul, Norte.'
    );
  });

  it('says nothing when every account got the request', () => {
    expect(enviado({ ids: '1,2' }).find('[data-sem-pedido]').exists()).toBe(
      false
    );
  });
});

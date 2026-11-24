import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import duasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';

const api = vi.hoisted(() => ({ getOverview: vi.fn() }));
vi.mock('dashboard/api/campaignResults', () => ({ default: api }));

const { default: AvisoDuasVersoesEsperando } = await import(
  '../AvisoDuasVersoesEsperando.vue'
);

// #3099 (D5) — na lista de Campanhas, as campanhas que esperam alguém escolher a versão do resto.
const A = duasVersoes.DUAS_VERSOES.AVISO_LISTA;
const montar = () =>
  mount(AvisoDuasVersoesEsperando, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: duasVersoes },
        }),
      ],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });

describe('AvisoDuasVersoesEsperando', () => {
  // Entre chaves: devolver o mock faria o vitest chamá-lo de novo como limpeza do teste.
  beforeEach(() => {
    api.getOverview.mockReset();
  });

  it('lista cada campanha esperando, com o prazo e o caminho para o resultado', async () => {
    api.getOverview.mockResolvedValue({
      data: {
        payload: {
          duas_versoes_esperando: [
            {
              channel: 'sms',
              id: 12,
              name: 'Renovação',
              resto: 1080,
              vai_sozinha_em: 1795000000,
            },
          ],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();

    expect(api.getOverview).toHaveBeenCalledWith({ days: 7 });
    const linha = wrapper.find('[data-esperando="sms:12"]');
    expect(linha.text()).toContain(
      A.TEXTO.replace('{nome}', 'Renovação').replace('{resto}', '1,080')
    );
    expect(linha.text()).toContain('version 1 goes on its own');
    expect(wrapper.find('h2').text()).toBe(A.TITULO);
    expect(linha.find('a').text()).toBe(A.ESCOLHER);
    expect(JSON.parse(linha.find('a').attributes('data-to'))).toEqual({
      name: 'campaigns_journey_result',
      params: { channel: 'sms', campaignId: 12 },
    });
  });

  it('avisa a campanha em que ninguém do teste recebeu e leva ao resultado', async () => {
    api.getOverview.mockResolvedValue({
      data: {
        payload: {
          duas_versoes_esperando: [
            {
              motivo: 'sem_envio',
              channel: 'whatsapp_api',
              id: 7,
              name: 'Boleto',
              resto: 900,
              vai_sozinha_em: 1795000000,
            },
          ],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('h2').text()).toBe(A.TITULO_ATENCAO);
    const linha = wrapper.find('[data-esperando="whatsapp_api:7"]');
    expect(linha.text()).toContain(
      A.TEXTO_SEM_ENVIO.replace('{nome}', 'Boleto')
    );
    expect(linha.text()).toContain('version 1 goes to the other 900 people');
    expect(linha.find('a').text()).toBe(A.VER);
    expect(linha.find('a').attributes('aria-label')).toBe(
      A.VER_ARIA.replace('{nome}', 'Boleto')
    );
  });

  it('sem campanha esperando, não aparece', async () => {
    api.getOverview.mockResolvedValue({
      data: { payload: { duas_versoes_esperando: [] } },
    });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-aviso-duas-versoes]').exists()).toBe(false);
  });

  it('sem conseguir ler, não aparece e a lista segue', async () => {
    api.getOverview.mockRejectedValue({ response: { status: 500 } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-aviso-duas-versoes]').exists()).toBe(false);
  });
});

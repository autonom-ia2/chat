import { mount, flushPromises, config } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptCrm from 'dashboard/i18n/locale/pt_BR/crm.json';
import CrmMetasAPI from 'dashboard/api/crmMetas';
import NumerosMetasGaveta from './NumerosMetasGaveta.vue';

vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('pt-BR') }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ reporting_timezone: 'America/Sao_Paulo' }),
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetas', () => ({
  default: { show: vi.fn(), salvar: vi.fn(() => Promise.resolve({})) },
}));

// Gaveta "Metas do mês" (#1991): a sugestão com o motivo ao lado, atalhos que
// só preenchem, e o salvar manda reais inteiros (vazio = sem meta).
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: ptCrm },
});
const plugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = plugins;
});

const RESPOSTA = {
  mes: '2026-10',
  mesAnterior: '2026-09',
  funis: [
    {
      id: 7,
      nome: 'Vendas',
      medida: 'valor',
      moeda: 'BRL',
      metaFunil: 20000,
      pessoas: [
        {
          id: 1,
          nome: 'Ana',
          meta: null,
          anterior: 8000,
          sugestao: { valor: 8000, historico: [7200, 8400, 7900] },
        },
        {
          id: 2,
          nome: 'Bruno',
          meta: 6000,
          anterior: null,
          sugestao: { valor: null, historico: [0, 0, 0] },
        },
      ],
    },
  ],
};

const SidePanel = {
  template: '<div><h2>{{ title }}</h2><slot /><slot name="footer" /></div>',
  props: ['title', 'description', 'width'],
  methods: { open() {}, close() {} },
};

const montar = async () => {
  CrmMetasAPI.show.mockResolvedValue({ data: RESPOSTA });
  const wrapper = mount(NumerosMetasGaveta, {
    global: {
      plugins: [i18n],
      stubs: { SidePanel, Teleport: true },
    },
  });
  wrapper.vm.abrir();
  await flushPromises();
  return wrapper;
};

// O Intl separa "R$" do valor com espaço sem quebra.
const semNbsp = alvo => alvo.text().replaceAll('\u00a0', ' ');

describe('NumerosMetasGaveta', () => {
  it('mostra a meta do funil, a sugestão com o motivo e quem não tem histórico', async () => {
    const wrapper = await montar();
    const conteudo = semNbsp(wrapper);
    expect(conteudo).toContain('Metas de outubro');
    expect(conteudo).toContain(
      'Sugestão: R$ 8.000. Nos últimos 3 meses, Ana fechou R$ 7.200, R$ 8.400 e R$ 7.900.'
    );
    expect(conteudo).toContain('Bruno não fechou venda nos últimos 3 meses.');
    expect(conteudo).toContain('Repetir setembro');
    expect(wrapper.findAll('[data-usar-sugestao]')).toHaveLength(1);
  });

  it('"Usar a sugestão" e salvar manda reais inteiros e null para o vazio', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-usar-sugestao]').trigger('click');
    await wrapper.find('[data-salvar-metas]').trigger('click');
    await flushPromises();

    expect(CrmMetasAPI.salvar).toHaveBeenCalledWith({
      mes: '2026-10',
      funis: [
        {
          id: 7,
          pessoas: [
            { id: 1, meta: 8000 },
            { id: 2, meta: 6000 },
          ],
        },
      ],
    });
    expect(wrapper.emitted('salvo')).toHaveLength(1);
  });

  it('avisa quando as pessoas somam diferente da meta do funil', async () => {
    const wrapper = await montar();
    expect(semNbsp(wrapper.find('[data-soma-diferente]'))).toContain(
      'As metas das pessoas somam R$ 6.000; a do funil é R$ 20.000.'
    );
  });
});

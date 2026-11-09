import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';
import LivreDestinatarios from '../components/LivreDestinatarios.vue';
import { doAlvoDoGatilho } from '../catalogo';
import { fraseDoGatilho } from '../frases';
import { useEscolhasDosGatilhos } from '../useEscolhasDosGatilhos';
import { useGatilhosNovos } from '../useGatilhosNovos';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';

// G32 (#2703) — a reunião deste card: a página de agendamento no gatilho de
// reunião, e "quem atende a reunião" no "avisar", só nos gatilhos de reunião.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// Os nomes das caixas (#2680) vêm do store; aqui a conta não tem nenhuma.
vi.mock('dashboard/composables/store', async () => {
  const vue = await import('vue');
  return { useMapGetter: () => vue.ref([]) };
});
const acesso = vi.hoisted(() => ({ agendamento: true }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => acesso.agendamento) };
});
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => true) }),
    };
  }
);
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: { payload: [{ id: 7, title: 'Renovação', slug: 'renovacao' }] },
      })
    ),
  },
}));

const t = (chave, valores) =>
  valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
const REUNIAO = [
  'card.reuniao_marcada',
  'card.reuniao_remarcada',
  'card.reuniao_cancelada',
];
const CATALOGO = {
  gatilhos: [
    {
      tipo: 'card.reuniao_marcada',
      alvo: 'Crm::Card',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_REUNIAO_MARCADA',
      grupo: 'reuniao',
      parametros: [
        {
          nome: 'pagina_id',
          peca: 'pagina',
          obrigatorio: false,
          frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.PAGINA_ID',
        },
      ],
    },
    {
      tipo: 'card.ganho',
      alvo: 'Crm::Card',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_GANHO',
      grupo: 'card',
      parametros: [],
    },
  ],
  alvos: { 'Crm::Card': ['card', 'conversa', 'contato', 'reuniao'] },
  operadores: [],
  unidades: [],
  valores: [
    { caminho: 'card.tem_reuniao_marcada', base: 'card' },
    { caminho: 'reuniao.inicio', base: 'reuniao', so_nos_gatilhos: REUNIAO },
  ],
  passos: [
    {
      tipo: 'avisar',
      grupo: 'EQUIPE',
      frase: 'AUTOMACAO_LIVRE.PASSOS.AVISAR',
      campos: [
        {
          nome: 'para',
          peca: 'destinatarios',
          rotulo: 'AUTOMACAO_LIVRE.CAMPOS.PARA',
        },
      ],
    },
  ],
};
const NOMES = { pagina: { 7: 'Renovação' } };

const PainelFalso = {
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
};
const montar = catalogo =>
  mount(LivreAlterar, {
    props: {
      catalogo,
      opcoes: { time: [], pessoa: [] },
      atributosDaPeca: () => [],
      atributosDo: () => [],
      gatilhos: CATALOGO.gatilhos,
      escolhasDoGatilho: {
        paginas: [{ value: 7, label: 'Renovação' }],
        nomes: NOMES,
      },
    },
    global: {
      stubs: { SidePanel: PainelFalso },
      mocks: { $t: chave => chave },
    },
  });
const avisar = { id: 'a', tipo: 'avisar', texto: [], para: {} };

describe('G32 — a reunião deste card', () => {
  it('a frase do gatilho diz a página; sem página, fica como era', () => {
    expect(
      fraseDoGatilho(
        { tipo: 'card.reuniao_marcada', pagina_id: 7 },
        CATALOGO,
        t,
        NOMES
      )
    ).toBe(
      'AUTOMACAO_LIVRE.GATILHO_NA_PAGINA AUTOMACAO_LIVRE.GATILHOS.CARD_REUNIAO_MARCADA Renovação'
    );
    expect(
      fraseDoGatilho({ tipo: 'card.reuniao_marcada' }, CATALOGO, t, NOMES)
    ).toBe('AUTOMACAO_LIVRE.GATILHOS.CARD_REUNIAO_MARCADA');
    // Página sem nome na tela: a frase ainda diz que há filtro.
    expect(
      fraseDoGatilho(
        { tipo: 'card.reuniao_marcada', pagina_id: 99 },
        CATALOGO,
        t,
        NOMES
      )
    ).toBe(
      'AUTOMACAO_LIVRE.GATILHO_NA_PAGINA AUTOMACAO_LIVRE.GATILHOS.CARD_REUNIAO_MARCADA AUTOMACAO_LIVRE.GATILHO_DE_REUNIAO.PAGINA_SEM_NOME'
    );
  });

  it('a página só aparece com o agendamento novo e quem lê as páginas', async () => {
    const pedePagina = async (flags, podeLer) => {
      acesso.agendamento = podeLer;
      CrmBookingPagesAPI.get.mockClear();
      let resultado;
      mount({
        setup() {
          resultado = useGatilhosNovos(
            flag => flags.includes(flag),
            ref(CATALOGO)
          );
          return {};
        },
        template: '<div />',
      });
      await flushPromises();
      const reuniao = resultado.gatilhos.value.find(
        item => item.tipo === 'card.reuniao_marcada'
      );
      return {
        temPeca: reuniao.parametros.some(item => item.peca === 'pagina'),
        leu: CrmBookingPagesAPI.get.mock.calls.length > 0,
      };
    };

    expect(await pedePagina(['crm_booking_v2'], true)).toEqual({
      temPeca: true,
      leu: true,
    });
    expect(await pedePagina([], true)).toEqual({ temPeca: false, leu: false });
    expect(await pedePagina(['crm_booking_v2'], false)).toEqual({
      temPeca: false,
      leu: false,
    });
    acesso.agendamento = true;
  });

  it('as escolhas trazem as páginas de agendamento pelo título', async () => {
    const { escolhas, carregar } = useEscolhasDosGatilhos();
    await carregar(['pagina']);

    expect(escolhas.value.paginas).toEqual([{ value: 7, label: 'Renovação' }]);
    expect(escolhas.value.nomes.pagina).toEqual({ 7: 'Renovação' });
  });

  it('o gatilho de reunião oferece a página e a grava como pagina_id', async () => {
    const wrapper = montar(CATALOGO);
    wrapper.vm.abrir({
      tipo: 'gatilho',
      valor: { tipo: 'card.reuniao_marcada' },
    });
    await flushPromises();

    const pagina = wrapper.find('[data-pagina]').findComponent({
      name: 'ChoiceSelect',
    });
    expect(pagina.props('options')).toEqual([
      {
        value: '',
        label: 'AUTOMACAO_LIVRE.GATILHO_DE_REUNIAO.QUALQUER_PAGINA',
      },
      { value: 7, label: 'Renovação' },
    ]);
    pagina.vm.$emit('update:modelValue', 7);
    await flushPromises();
    await wrapper.find('[data-salvar]').trigger('click');

    expect(wrapper.emitted('salvar')[0][0].valor).toMatchObject({
      tipo: 'card.reuniao_marcada',
      pagina_id: 7,
    });
  });

  it('o catálogo do alvo leva o tipo do gatilho', () => {
    expect(doAlvoDoGatilho(CATALOGO, 'card.ganho').gatilho).toBe('card.ganho');
  });

  // G61: fora dos gatilhos de reunião vale a próxima reunião marcada do contato.
  it('"quem atende a reunião" aparece em qualquer gatilho e libera o salvar', async () => {
    const noGanho = montar(doAlvoDoGatilho(CATALOGO, 'card.ganho'));
    noGanho.vm.abrir({ tipo: 'passo', valor: avisar });
    await flushPromises();
    expect(noGanho.find('[data-da-reuniao]').exists()).toBe(true);

    const naReuniao = montar(doAlvoDoGatilho(CATALOGO, 'card.reuniao_marcada'));
    naReuniao.vm.abrir({ tipo: 'passo', valor: avisar });
    await flushPromises();
    expect(
      naReuniao.find('[data-salvar]').attributes('disabled')
    ).toBeDefined();

    naReuniao
      .findComponent(LivreDestinatarios)
      .find('[data-da-reuniao]')
      .findComponent({ name: 'Switch' })
      .vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(
      naReuniao.find('[data-salvar]').attributes('disabled')
    ).toBeUndefined();
    await naReuniao.find('[data-salvar]').trigger('click');
    expect(naReuniao.emitted('salvar')[0][0].valor.para).toEqual({
      da_reuniao: true,
    });
  });

  it('marcado, a chave tira quem atende a reunião sem mexer no resto', () => {
    const wrapper = mount(LivreDestinatarios, {
      props: {
        rotulo: 'PARA',
        opcoes: { time: [], pessoa: [] },
        modelValue: { da_reuniao: true, responsavel: true },
      },
      global: { mocks: { $t: chave => chave } },
    });
    const chave = wrapper
      .find('[data-da-reuniao]')
      .findComponent({ name: 'Switch' });

    chave.vm.$emit('update:modelValue', false);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { responsavel: true },
    ]);
  });
});

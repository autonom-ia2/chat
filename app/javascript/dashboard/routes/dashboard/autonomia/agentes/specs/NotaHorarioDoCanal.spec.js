// #1619 — Agentes › Onde e quando com a flag horario_unico_caixa: com horário, a linha do fuso da
// conta e "Mudar o horário do canal"; sem horário, "Definir o horário do canal". Sem a flag, nada muda.
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import NotaHorarioDoCanal from '../components/NotaHorarioDoCanal.vue';
import OndeQuandoEscolha from '../components/OndeQuandoEscolha.vue';
import GavetaOndeQuando from '../components/pagina/GavetaOndeQuando.vue';

withFullI18n('pt_BR');

const permissoes = vi.hoisted(() => ({ conectar: true }));
vi.mock('../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => permissoes.conectar),
      podeEscolherQuemRecebe: computed(() => false),
      crmLigado: computed(() => false),
    }),
  };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: rota => ({
      href: `/app/${rota.name}/${rota.params?.inboxId}/${rota.params?.tab}`,
    }),
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/channels', () => ({
  default: { connect: vi.fn(), disconnect: vi.fn() },
}));

const HORARIO = 'seg. a sex., das 9h às 18h';

const criarStore = flag => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ id: 1, accounts: [] }),
      'accounts/isFeatureEnabledonAccount': () => (_, nome) =>
        flag && nome === 'horario_unico_caixa',
      'accounts/getAccount': () => () => ({
        id: 1,
        custom_attributes: { timezone: 'America/Sao_Paulo' },
      }),
      getUISettings: () => ({}),
    },
  });
  store.dispatch = vi.fn();
  return store;
};

const montarNota = ({ flag = true, ...props }) => {
  const store = criarStore(flag);
  const wrapper = mount(NotaHorarioDoCanal, {
    props: { inboxId: 10, ...props },
    global: { plugins: [store] },
  });
  return { wrapper, store };
};

describe('NotaHorarioDoCanal', () => {
  beforeEach(() => {
    permissoes.conectar = true;
  });

  it('canal com horário: fuso da conta e "Mudar o horário do canal" em outra aba', () => {
    const { wrapper } = montarNota({ horario: HORARIO });
    expect(wrapper.find('[data-fuso]').text()).toBe(
      'O horário é o do canal, no fuso da conta (America/Sao Paulo).'
    );
    expect(wrapper.text()).not.toContain('Brasília');
    const link = wrapper.find('[data-link-horario]');
    expect(link.text()).toContain('Mudar o horário do canal');
    expect(link.attributes()).toMatchObject({
      href: '/app/settings_inbox_show/10/business-hours',
      target: '_blank',
    });
  });

  it('canal sem horário: só "Definir o horário do canal"', () => {
    const { wrapper } = montarNota({ horario: null });
    expect(wrapper.find('[data-fuso]').exists()).toBe(false);
    expect(wrapper.find('[data-link-horario]').text()).toContain(
      'Definir o horário do canal'
    );
  });

  it('sem permissão de caixa: mostra o fuso, sem o link', () => {
    permissoes.conectar = false;
    const { wrapper } = montarNota({ horario: HORARIO });
    expect(wrapper.find('[data-fuso]').exists()).toBe(true);
    expect(wrapper.find('[data-link-horario]').exists()).toBe(false);
  });

  it('caixa fora do mapa de horários: nada', () => {
    const { wrapper } = montarNota({ horario: undefined });
    expect(wrapper.find('[data-horario-do-canal]').exists()).toBe(false);
  });

  it('sem a flag: nada', () => {
    const { wrapper } = montarNota({ flag: false, horario: HORARIO });
    expect(wrapper.find('[data-horario-do-canal]').exists()).toBe(false);
  });

  it('ao voltar da aba do canal, relê as caixas uma vez', async () => {
    const { wrapper, store } = montarNota({ horario: null });
    await wrapper.find('[data-link-horario]').trigger('click');
    document.dispatchEvent(new Event('visibilitychange'));
    document.dispatchEvent(new Event('visibilitychange'));
    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(store.dispatch).toHaveBeenCalledWith('inboxes/get');
  });
});

const CANAIS = [
  { inbox_id: 10, name: 'WhatsApp Vendas', occupied_by: null },
  { inbox_id: 11, name: 'Instagram da loja', occupied_by: null },
];

const montarEscolha = ({ flag, onde }) =>
  mount(OndeQuandoEscolha, {
    props: {
      canais: CANAIS,
      agenteId: 5,
      nome: 'Lia',
      onde,
      quando: 'always',
      horarios: { 10: HORARIO, 11: null },
    },
    global: { plugins: [criarStore(flag)] },
  });

describe('OndeQuandoEscolha com o horário do canal', () => {
  it.each([
    [true, 10, true, 'Mudar o horário do canal'],
    [true, 11, false, 'Definir o horário do canal'],
  ])(
    'flag=%s, caixa %s: fuso=%s e link "%s"',
    (flag, onde, temFuso, rotulo) => {
      const wrapper = montarEscolha({ flag, onde });
      expect(wrapper.find('[data-fuso]').exists()).toBe(temFuso);
      expect(wrapper.find('[data-link-horario]').text()).toContain(rotulo);
    }
  );

  it('flag desligada: como hoje, sem fuso nem link', () => {
    const comHorario = montarEscolha({ flag: false, onde: 10 });
    const semHorario = montarEscolha({ flag: false, onde: 11 });
    expect(comHorario.find('[data-horario-do-canal]').exists()).toBe(false);
    expect(semHorario.find('[data-horario-do-canal]').exists()).toBe(false);
    expect(semHorario.text()).toContain(
      'Este canal ainda não tem horário de atendimento.'
    );
  });
});

describe('GavetaOndeQuando parado com o horário do canal', () => {
  const montarGaveta = flag =>
    mount(GavetaOndeQuando, {
      attachTo: document.body,
      props: {
        agente: {
          id: 7,
          name: 'Lia',
          status: 'paused',
          enabled: false,
          config: { response_window: 'always' },
        },
        nome: 'Lia',
        atendendo: false,
        canais: CANAIS,
        atuais: [CANAIS[0]],
        horarios: { 10: HORARIO, 11: null },
      },
      global: { plugins: [criarStore(flag)] },
    });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('flag ligada: a linha do fuso e "Mudar o horário do canal"', async () => {
    montarGaveta(true);
    await flushPromises();
    expect(document.querySelector('[data-parado]')).not.toBeNull();
    expect(document.querySelector('[data-fuso]').textContent).toContain(
      'no fuso da conta (America/Sao Paulo)'
    );
    expect(document.querySelector('[data-link-horario]').textContent).toContain(
      'Mudar o horário do canal'
    );
  });

  it('flag desligada: como hoje', async () => {
    montarGaveta(false);
    await flushPromises();
    expect(document.querySelector('[data-parado]')).not.toBeNull();
    expect(document.querySelector('[data-horario-do-canal]')).toBeNull();
  });
});

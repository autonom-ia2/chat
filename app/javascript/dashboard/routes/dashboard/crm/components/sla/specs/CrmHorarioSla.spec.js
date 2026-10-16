// #1619 — CRM › SLA com a flag horario_unico_caixa: "Horário de cada pessoa" (editor do calendário
// com dono pessoa) e "Horário dos canais" (só leitura, com o caminho até a tela do canal).
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import CrmHorarioPessoas from '../CrmHorarioPessoas.vue';
import CrmHorarioCanais from '../CrmHorarioCanais.vue';

withFullI18n('pt_BR');

const api = vi.hoisted(() => ({ get: vi.fn(), create: vi.fn() }));
vi.mock('dashboard/api/crmServiceSchedules', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const linha = (dia, abre, fecha) => ({
  day_of_week: dia,
  closed_all_day: false,
  open_all_day: false,
  open_hour: Math.floor(abre / 60),
  open_minutes: abre % 60,
  close_hour: Math.floor(fecha / 60),
  close_minutes: fecha % 60,
});

const CAIXAS = [
  {
    id: 1,
    name: 'WhatsApp Vendas',
    channel_type: 'Channel::Whatsapp',
    working_hours_enabled: true,
    working_hours: [1, 2, 3, 4, 5].map(d => linha(d, 540, 1080)),
  },
  {
    id: 2,
    name: 'Instagram da loja',
    channel_type: 'Channel::Instagram',
    working_hours_enabled: false,
    working_hours: [],
  },
];

const PESSOAS = [
  { id: 11, name: 'Ana Souza', available_name: 'Ana Souza' },
  { id: 12, name: 'Bruno Lima', available_name: 'Bruno Lima' },
  { id: 13, name: 'Carla Dias', available_name: 'Carla Dias' },
];

// Como no painel: o administrador traz 'administrator' nas permissões da conta.
const montar = (
  componente,
  { papel = 'administrator', permissoes = ['administrator'] } = {}
) => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => papel,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 1, role: papel, permissions: permissoes }],
      }),
      'accounts/isFeatureEnabledonAccount': () => () => true,
      'accounts/getAccount': () => () => ({
        id: 1,
        settings: { reporting_timezone: 'America/Cuiaba' },
      }),
      'agents/getAgents': () => PESSOAS,
      'inboxes/getInboxes': () => CAIXAS,
    },
  });
  store.dispatch = vi.fn();
  return mount(componente, {
    attachTo: document.body,
    global: {
      plugins: [store],
      stubs: {
        'router-link': {
          props: ['to'],
          template:
            '<a data-link :data-name="to.name" :data-inbox="to.params.inboxId" :data-tab="to.params.tab"><slot /></a>',
        },
        Teleport: true,
      },
    },
  });
};

describe('CrmHorarioPessoas', () => {
  beforeEach(() => {
    api.get.mockReset();
  });

  it('mostra o horário de cada pessoa, com almoço, e quem segue o canal', async () => {
    api.get.mockResolvedValue({
      data: {
        payload: [
          {
            owner_type: 'User',
            owner_id: 11,
            enabled: true,
            timezone: 'America/Cuiaba',
            blocks: [1, 2, 3, 4, 5].map(d => ({
              day_of_week: d,
              start_minute: 480,
              end_minute: 1020,
            })),
          },
          {
            owner_type: 'User',
            owner_id: 13,
            enabled: true,
            timezone: 'America/Cuiaba',
            blocks: [1, 2, 3, 4, 5].flatMap(d => [
              { day_of_week: d, start_minute: 540, end_minute: 720 },
              { day_of_week: d, start_minute: 780, end_minute: 1080 },
            ]),
          },
          // Calendário de caixa não entra aqui.
          { owner_type: 'Inbox', owner_id: 12, enabled: true, blocks: [] },
        ],
      },
    });
    const wrapper = montar(CrmHorarioPessoas);
    await flushPromises();

    const linhas = wrapper.findAll('[data-pessoa]').map(item => item.text());
    expect(linhas[0]).toContain('Seg. a sex., das 8h às 17h');
    expect(linhas[0]).toContain('Alterar');
    expect(linhas[1]).toContain(
      'Sem horário próprio: segue o horário do canal'
    );
    expect(linhas[1]).toContain('Definir horário');
    expect(linhas[2]).toContain('Seg. a sex., das 9h às 12h e das 13h às 18h');
  });

  it('abre o editor da pessoa no fuso da conta', async () => {
    api.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar(CrmHorarioPessoas);
    await flushPromises();

    await wrapper.findAll('[data-pessoa] button')[1].trigger('click');
    const editor = wrapper.findComponent({ name: 'CrmScheduleEditor' });
    expect(editor.props()).toMatchObject({
      ownerType: 'User',
      ownerId: 12,
      ownerName: 'Bruno Lima',
      defaultTimezone: 'America/Cuiaba',
    });
  });

  it('leitura falhou: avisa e não deixa editar por cima', async () => {
    api.get.mockRejectedValue(new Error('500'));
    const wrapper = montar(CrmHorarioPessoas);
    await flushPromises();

    expect(wrapper.find('[data-erro]').text()).toContain(
      'Não deu para ler o horário das pessoas.'
    );
    expect(wrapper.find('[data-pessoa]').exists()).toBe(false);
  });
});

describe('CrmHorarioCanais', () => {
  it('mostra o horário de cada canal no fuso da conta e leva à tela do canal', () => {
    const wrapper = montar(CrmHorarioCanais);
    expect(wrapper.text()).toContain('no fuso da conta (America/Cuiaba).');
    expect(wrapper.text()).not.toContain('Brasília');

    const [vendas, insta] = wrapper.findAll('[data-canal]');
    expect(vendas.text()).toContain('WhatsApp Vendas');
    expect(vendas.text()).toContain('Seg. a sex., das 9h às 18h');
    expect(vendas.find('[data-link]').text()).toBe('Ver horário do canal');
    expect(vendas.find('[data-link]').attributes()).toMatchObject({
      'data-name': 'settings_inbox_show',
      'data-inbox': '1',
      'data-tab': 'business-hours',
    });
    expect(insta.text()).toContain('Sem horário: atende a qualquer hora');
    expect(insta.find('[data-link]').text()).toBe('Definir horário do canal');
    // Só leitura: nada de editar aqui.
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('sem permissão de caixa, mostra o horário sem o link', () => {
    const wrapper = montar(CrmHorarioCanais, {
      papel: 'agent',
      permissoes: ['sla_manage'],
    });
    expect(wrapper.findAll('[data-canal]')).toHaveLength(2);
    expect(wrapper.find('[data-link]').exists()).toBe(false);
  });
});

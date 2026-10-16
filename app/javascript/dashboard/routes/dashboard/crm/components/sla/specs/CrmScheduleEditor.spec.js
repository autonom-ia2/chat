// #1619 — editor do calendário de SLA. Com a flag horario_unico_caixa, não há escolha de fuso: uma
// linha só de leitura com o fuso da conta, e salvar grava o fuso da conta. Sem a flag, como hoje.
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import CrmScheduleEditor from '../CrmScheduleEditor.vue';

withFullI18n('pt_BR');

const api = vi.hoisted(() => ({ create: vi.fn() }));
vi.mock('dashboard/api/crmServiceSchedules', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const CALENDARIO = {
  owner_type: 'User',
  owner_id: 12,
  enabled: true,
  timezone: 'America/Sao_Paulo',
  blocks: [{ day_of_week: 1, start_minute: 540, end_minute: 1080 }],
};

const montar = flag => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => (_, nome) =>
        flag && nome === 'horario_unico_caixa',
      'accounts/getAccount': () => () => ({
        id: 1,
        custom_attributes: { timezone: 'America/Cuiaba' },
      }),
    },
  });
  return mount(CrmScheduleEditor, {
    props: {
      ownerType: 'User',
      ownerId: 12,
      ownerName: 'Bruno Lima',
      schedule: CALENDARIO,
    },
    global: {
      plugins: [store],
      stubs: {
        Teleport: true,
        ComboBox: { name: 'ComboBox', template: '<i />' },
      },
    },
  });
};

const salvar = async wrapper => {
  api.create.mockResolvedValue({ data: { payload: CALENDARIO } });
  const botao = wrapper
    .findAll('button')
    .find(item => item.text() === 'Salvar calendário');
  await botao.trigger('click');
  await flushPromises();
  return api.create.mock.calls[0][0].service_schedule;
};

describe('CrmScheduleEditor', () => {
  it('com a flag: fuso da conta só para ler, e salva no fuso da conta', async () => {
    const wrapper = montar(true);
    expect(wrapper.find('[data-fuso-da-conta]').text()).toBe(
      'No fuso da conta: America/Cuiaba'
    );
    expect(wrapper.findComponent({ name: 'ComboBox' }).exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Brasilia');

    const enviado = await salvar(wrapper);
    expect(enviado.timezone).toBe('America/Cuiaba');
    expect(enviado.blocks).toEqual([
      { day_of_week: 1, start_minute: 540, end_minute: 1080 },
    ]);
  });

  it('sem a flag: a escolha de fuso de hoje, e salva o fuso escolhido', async () => {
    const wrapper = montar(false);
    expect(wrapper.find('[data-fuso-da-conta]').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'ComboBox' }).exists()).toBe(true);

    const enviado = await salvar(wrapper);
    expect(enviado.timezone).toBe('America/Sao_Paulo');
  });
});

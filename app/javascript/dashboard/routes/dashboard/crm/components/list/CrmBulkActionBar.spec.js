import { mount } from '@vue/test-utils';
import { flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmBulkActionBar from './CrmBulkActionBar.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt-BR' } }),
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { upcomingMeetings: vi.fn() },
}));

// #1874 — cada botão da ação em massa só aparece para quem pode a ação.
const montar = permissions =>
  mount(CrmBulkActionBar, {
    props: { count: 2, permissions },
    global: {
      stubs: {
        SelectMenu: {
          props: ['label'],
          template: '<div :data-label="label" />',
        },
        ComboBox: { template: '<div data-owner />' },
        Button: {
          props: ['label'],
          template: '<button :data-label="label" />',
        },
        Dialog: true,
        Transition: false,
      },
    },
  });

const rotulos = wrapper =>
  wrapper
    .findAll('[data-label]')
    .map(node => node.attributes('data-label'))
    .concat(wrapper.find('[data-owner]').exists() ? ['ASSIGN'] : []);

describe('CrmBulkActionBar', () => {
  it('sem a permissão, não mostra nenhuma ação', () => {
    expect(rotulos(montar(undefined))).toEqual(['CRM_KANBAN.BULK.CLEAR']);
  });

  it('com tudo, mostra todas as ações', () => {
    expect(
      rotulos(montar({ move: true, assign: true, status: true, archive: true }))
    ).toEqual([
      'CRM_KANBAN.BULK.MOVE',
      'CRM_KANBAN.BULK.STATUS',
      'CRM_KANBAN.BULK.DELETE',
      'CRM_KANBAN.BULK.CLEAR',
      'ASSIGN',
    ]);
  });

  it('sem arquivar, some só o Arquivar', () => {
    expect(
      rotulos(
        montar({ move: true, assign: true, status: true, archive: false })
      )
    ).toEqual([
      'CRM_KANBAN.BULK.MOVE',
      'CRM_KANBAN.BULK.STATUS',
      'CRM_KANBAN.BULK.CLEAR',
      'ASSIGN',
    ]);
  });

  it('só com mover, fica mover e limpar', () => {
    expect(
      rotulos(
        montar({ move: true, assign: false, status: false, archive: false })
      )
    ).toEqual(['CRM_KANBAN.BULK.MOVE', 'CRM_KANBAN.BULK.CLEAR']);
  });
  // #2091: arquivar em lote avisa que as reuniões marcadas continuam.
  it('o diálogo de arquivar avisa quantos cards têm reunião marcada', async () => {
    CrmKanbanAPI.upcomingMeetings.mockResolvedValue({
      data: {
        payload: {
          timezone: 'America/Sao_Paulo',
          cards: [{ card_id: 4, starts_at: '2026-10-24T10:00:00-03:00' }],
        },
      },
    });
    const wrapper = mount(CrmBulkActionBar, {
      props: { count: 2, ids: [4, 5], permissions: { archive: true } },
      global: {
        stubs: {
          SelectMenu: true,
          ComboBox: true,
          Button: {
            props: ['label'],
            emits: ['click'],
            template:
              '<button :data-label="label" @click="$emit(\'click\')" />',
          },
          Dialog: {
            template: '<div data-dialogo><slot /></div>',
            methods: { open() {}, close() {} },
          },
          Transition: false,
        },
      },
    });

    await wrapper
      .find('[data-label="CRM_KANBAN.BULK.DELETE"]')
      .trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.upcomingMeetings).toHaveBeenCalledWith([4, 5]);
    expect(wrapper.find('[data-aviso-reuniao]').text()).toBe(
      'CRM_KANBAN.BULK.DELETE_MEETINGS'
    );
  });

  it('o Arquivar do diálogo espera o aviso chegar', async () => {
    let responder;
    CrmKanbanAPI.upcomingMeetings.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const wrapper = mount(CrmBulkActionBar, {
      props: { count: 2, ids: [4, 5], permissions: { archive: true } },
      global: {
        stubs: {
          SelectMenu: true,
          ComboBox: true,
          Button: {
            props: ['label'],
            emits: ['click'],
            template:
              '<button :data-label="label" @click="$emit(\'click\')" />',
          },
          Dialog: {
            name: 'Dialog',
            props: ['isLoading'],
            emits: ['confirm'],
            template: '<div data-dialogo :data-carregando="isLoading" />',
            methods: { open() {}, close() {} },
          },
          Transition: false,
        },
      },
    });
    await wrapper
      .find('[data-label="CRM_KANBAN.BULK.DELETE"]')
      .trigger('click');
    const dialogo = wrapper.findComponent({ name: 'Dialog' });

    expect(dialogo.props('isLoading')).toBe(true);
    dialogo.vm.$emit('confirm');
    expect(wrapper.emitted('archive')).toBeUndefined();

    responder({ data: { payload: { cards: [] } } });
    await flushPromises();
    expect(dialogo.props('isLoading')).toBe(false);
    dialogo.vm.$emit('confirm');
    expect(wrapper.emitted('archive')).toHaveLength(1);
  });
});

import { mount } from '@vue/test-utils';
import CrmBulkActionBar from './CrmBulkActionBar.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
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
});

// Apagar contato (#2138): a janela avisa que as conversas e mensagens do contato saem junto (Contact has_many
// :conversations e :messages, dependent: :destroy_async). A nota dos cards só aparece com o CRM ligado.
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ConfirmContactDeleteDialog from '../ConfirmContactDeleteDialog.vue';

const features = ref({});

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: nome =>
    ({
      getCurrentAccountId: ref(1),
      'accounts/getAccount': ref(() => ({ features: features.value })),
      getCurrentRole: ref('agent'),
    })[nome],
}));

const descricao = () =>
  mount(ConfirmContactDeleteDialog, {
    props: { selectedContact: { id: 5, name: 'Ana' } },
    global: {
      stubs: {
        Dialog: {
          props: ['description'],
          template: '<p>{{ description }}</p>',
        },
        ExcluirContatoDialogo: true,
      },
    },
  }).text();

describe('ConfirmContactDeleteDialog', () => {
  it('avisa que as conversas e mensagens também são apagadas', () => {
    features.value = {};

    expect(descricao()).toBe(
      'CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.DESCRIPTION APAGAR_CONTATO.UM'
    );
  });

  it('com o CRM ligado, soma a nota dos cards depois do aviso', () => {
    features.value = { crm: true };

    expect(descricao()).toBe(
      'CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.DESCRIPTION APAGAR_CONTATO.UM CRM_EXCLUIR.CONTATO.NOTA_CARDS'
    );
  });
});

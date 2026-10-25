// Apagar contato (#1618): depois de apagar, o modal mandava para
// 'contacts_dashboard', rota que não existe; o router.push falhava e caía no
// catch, que mostrava erro mesmo com o contato apagado. A lista de contatos se
// chama 'contacts_dashboard_index', e o nome é conferido nas rotas reais.
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ContactDeleteModal from '../ContactDeleteModal.vue';
import { routes as contactRoutes } from 'dashboard/routes/dashboard/contacts/routes';

const push = vi.fn();
const dispatch = vi.fn();
const alerta = vi.fn();
const rotaAtual = { name: 'contacts_edit' };

// O aviso de #2138 sai do catálogo real em pt_BR; as outras chaves continuam como a própria chave.
vi.mock('vue-i18n', async () => {
  const { default: ptBR } = await import(
    'dashboard/i18n/locale/pt_BR/painelDoContato.json'
  );
  const doCatalogo = key =>
    key.split('.').reduce((nivel, parte) => nivel?.[parte], ptBR);
  return {
    useI18n: () => ({
      t: key => (typeof doCatalogo(key) === 'string' ? doCatalogo(key) : key),
    }),
  };
});
vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-router', () => ({
  useRoute: () => rotaAtual,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: msg => alerta(msg) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({ isDeleting: false }),
}));

const nomesDasRotas = rotas =>
  rotas.flatMap(rota => [
    ...(rota.name ? [rota.name] : []),
    ...nomesDasRotas(rota.children || []),
  ]);

const montar = () =>
  mount(ContactDeleteModal, {
    props: { contact: { id: 5, name: 'Ana' } },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Popover: {
          template: '<div><slot name="content" :hide="() => {}" /></div>',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const apagar = async () => {
  const wrapper = montar();
  const sim = wrapper
    .findAll('button')
    .find(botao => botao.text() === 'DELETE_CONTACT.CONFIRM.YES');
  await sim.trigger('click');
  await Promise.resolve();
};

describe('ContactDeleteModal', () => {
  beforeEach(() => {
    push.mockReset();
    alerta.mockReset();
    dispatch.mockResolvedValue();
  });

  it('depois de apagar, volta para a lista de contatos pela rota que existe', async () => {
    await apagar();

    expect(push).toHaveBeenCalledWith({ name: 'contacts_dashboard_index' });
    expect(nomesDasRotas(contactRoutes)).toContain('contacts_dashboard_index');
    expect(alerta).toHaveBeenCalledWith('DELETE_CONTACT.API.SUCCESS_MESSAGE');
  });

  // #2138: as conversas e mensagens do contato saem junto; o aviso diz isso antes do "Sim".
  it('avisa que as conversas e mensagens também são apagadas', () => {
    expect(montar().text()).toContain(
      'O contato, as conversas e as mensagens dele serão apagados. Não dá para desfazer.'
    );
  });
});

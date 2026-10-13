import { mount } from '@vue/test-utils';
import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';

// #1459 — na página do contato, o painel lateral (o de celular) fecha com Esc
// e com clique fora. A gaveta de Nova conversa abre por cima dele: mexer
// dentro dela, ou fechá-la com Esc, não pode fechar o painel por baixo.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { contactId: '9' } }),
}));

const montar = () =>
  mount(ContactsDetailsLayout, {
    attachTo: document.body,
    props: { selectedContact: { id: 9, name: 'Ana' } },
    slots: { sidebar: '<div data-painel>Detalhes</div>' },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        Button: { template: '<button><slot /></button>' },
        Breadcrumb: true,
        VoiceCallButton: true,
        ComposeConversation: true,
      },
    },
  });

// O mesmo que a gaveta põe no <body>: o fundo e o diálogo.
const abrirGaveta = () => {
  document.body.insertAdjacentHTML(
    'beforeend',
    `<div data-nova-conversa-fundo></div>
     <div data-nova-conversa-gaveta><button data-dentro>Enviar</button></div>`
  );
  return () =>
    document
      .querySelectorAll(
        '[data-nova-conversa-fundo], [data-nova-conversa-gaveta]'
      )
      .forEach(item => item.remove());
};

// A detecção de clique fora só olha um clique por vez: espera a vez passar.
const clicar = async alvo => {
  ['pointerdown', 'pointerup', 'click'].forEach(tipo =>
    alvo.dispatchEvent(new MouseEvent(tipo, { bubbles: true }))
  );
  await new Promise(resolve => {
    setTimeout(resolve, 0);
  });
};

const apertarEsc = () =>
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

describe('painel do contato com a gaveta de Nova conversa aberta', () => {
  let wrapper;
  let fecharGaveta;

  const botao = () => wrapper.find('[data-contact-sidebar-toggle]');
  const painelAberto = () => botao().attributes('aria-expanded') === 'true';

  beforeEach(async () => {
    wrapper = montar();
    await botao().trigger('click');
    expect(painelAberto()).toBe(true);
    fecharGaveta = abrirGaveta();
  });

  afterEach(() => {
    fecharGaveta();
    wrapper.unmount();
  });

  it('Esc com a gaveta aberta não fecha o painel por baixo', async () => {
    apertarEsc();
    await wrapper.vm.$nextTick();
    expect(painelAberto()).toBe(true);

    // Sem a gaveta, Esc volta a fechar o painel.
    fecharGaveta();
    apertarEsc();
    await wrapper.vm.$nextTick();
    expect(painelAberto()).toBe(false);
  });

  it('clicar dentro da gaveta ou no fundo dela não fecha o painel', async () => {
    await clicar(document.querySelector('[data-dentro]'));
    expect(painelAberto()).toBe(true);
    await clicar(document.querySelector('[data-nova-conversa-fundo]'));
    expect(painelAberto()).toBe(true);

    // Clique fora de verdade continua fechando.
    await clicar(document.body);
    expect(painelAberto()).toBe(false);
  });
});

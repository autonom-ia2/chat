import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { ref } from 'vue';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import EnviarModeloDaConversa from '../conversa/EnviarModeloDaConversa.vue';

// A jornada da conversa (#1716) com a API dos Modelos falsa: gaveta, ordem,
// nome do cliente sozinho, catálogo relido no enviar, sem catálogo e foto
// grande demais. O Dialog nativo e a gaveta viram peças simples.
const api = vi.hoisted(() => ({
  obterCatalogo: vi.fn(),
  conferirProdutos: vi.fn(),
  subirArquivoDaCampanha: vi.fn(),
}));
vi.mock('../conversa/apiDaConversa', () => ({ default: api }));
const perfil = vi.hoisted(() => ({ lerPerfilDoModelo: vi.fn() }));
vi.mock('../conversa/perfilDoModelo', () => perfil);
vi.mock('../conversa/useCompletaNaConversa', () => ({
  useCompletaNaConversa: () => ({ podeSubirFoto: ref(true), opcoes: ref({}) }),
}));
const emitter = vi.hoisted(() => ({ emit: vi.fn() }));
vi.mock('shared/helpers/mitt', () => ({ emitter }));

const DialogFalso = {
  emits: ['confirm', 'close'],
  props: ['title', 'description'],
  template: `<form data-dialogo @submit.prevent="$emit('confirm')">
    <h3>{{ title }}</h3><slot /><slot name="footer" /></form>`,
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
};
const GavetaFalsa = {
  name: 'GavetaDeProdutos',
  props: ['caixa', 'pedido', 'escolhidos', 'fonte'],
  emits: ['usar', 'fechar'],
  template: '<div data-gaveta />',
};

const corpo = { type: 'BODY', text: 'Oi {{1}}, veja {{2}}.' };
const varios = {
  name: 'vitrine_da_semana',
  language: 'pt_BR',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'TEXT', text: 'Novidades' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'MPM', text: 'Ver itens' }] },
  ],
};
const fotos = {
  name: 'ofertas_da_semana',
  language: 'pt_BR',
  category: 'MARKETING',
  components: [
    { type: 'BODY', text: 'Ofertas da semana.' },
    {
      type: 'CAROUSEL',
      cards: [0, 1].map(() => ({
        components: [
          { type: 'HEADER', format: 'IMAGE' },
          { type: 'BODY', text: 'Leve {{1}}' },
        ],
      })),
    },
  ],
};
const tenis = {
  id: 'tenis',
  nome: 'Tênis',
  preco: 'R$ 249,90',
  precoAntes: 'R$ 299,90',
  foto: '',
  disponivel: true,
};
const mochila = {
  id: 'mochila',
  nome: 'Mochila',
  preco: 'R$ 99',
  precoAntes: '',
  foto: '',
  disponivel: true,
};

const montar = () =>
  mount(EnviarModeloDaConversa, {
    props: { caixa: 7 },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        createStore({
          getters: {
            getSelectedChat: () => ({
              meta: { sender: { name: 'Marina Costa' } },
            }),
          },
        }),
      ],
      stubs: {
        Dialog: DialogFalso,
        GavetaDeProdutos: GavetaFalsa,
        BicoDoBalao: true,
        Icon: true,
      },
    },
  });

const escolherVarios = async wrapper => {
  await wrapper.vm.abrir(varios);
  await flushPromises();
  wrapper.findComponent(GavetaFalsa).vm.$emit('usar', [tenis, mochila]);
  await flushPromises();
};

beforeEach(() => {
  vi.clearAllMocks();
  api.obterCatalogo.mockResolvedValue({ nome: 'Loja', produtos: 3 });
  perfil.lerPerfilDoModelo.mockResolvedValue({
    campos: { 1: 'cliente.primeiro_nome' },
    galeria: [{ url: 'https://s/a.jpg', referencia: 'b1', nome: 'a.jpg' }],
    falhou: false,
  });
});

describe('EnviarModeloDaConversa: produtos (#1716)', () => {
  it('a ordem dos toques, subir e descer, o nome do cliente sozinho e o envio do processed_params', async () => {
    api.conferirProdutos.mockResolvedValue([tenis, mochila]);
    const wrapper = montar();
    await escolherVarios(wrapper);

    const nome = wrapper.find('[data-campo-da-mensagem="1"] input');
    expect(nome.element.value).toBe('Marina');
    await wrapper
      .find('[data-campo-da-mensagem="2"] input')
      .setValue('a vitrine');
    expect(wrapper.text()).toContain('R$ 299,90');
    await wrapper
      .find('[data-produto-escolhido="tenis"] [data-descer]')
      .trigger('click');
    await wrapper.find('[data-enviar-modelo]').trigger('click');
    await flushPromises();

    expect(api.conferirProdutos).toHaveBeenCalledWith(7, ['mochila', 'tenis']);
    const [[envio]] = wrapper.emitted('enviar');
    expect(envio.message).toBe('Oi Marina, veja a vitrine.');
    expect(envio.templateParams.processed_params).toEqual({
      body: { 1: 'Marina', 2: 'a vitrine' },
      products: {
        retailer_ids: ['mochila', 'tenis'],
        names: { mochila: 'Mochila', tenis: 'Tênis' },
      },
    });
  });

  it('Enter num campo não envia ao cliente (só o botão Enviar)', async () => {
    api.conferirProdutos.mockResolvedValue([tenis, mochila]);
    const wrapper = montar();
    await escolherVarios(wrapper);
    await wrapper.find('[data-campo-da-mensagem="2"] input').setValue('tudo');
    await wrapper.find('[data-dialogo]').trigger('submit');
    await flushPromises();

    expect(api.conferirProdutos).not.toHaveBeenCalled();
    expect(wrapper.emitted('enviar')).toBeUndefined();
  });

  it('produto que acabou depois de escolhido: relê o catálogo, marca e não envia', async () => {
    api.conferirProdutos.mockResolvedValue([{ ...mochila, disponivel: false }]);
    const wrapper = montar();
    await escolherVarios(wrapper);
    await wrapper.find('[data-campo-da-mensagem="2"] input').setValue('tudo');
    await wrapper.find('[data-enviar-modelo]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('enviar')).toBeUndefined();
    expect(wrapper.find('[data-aviso-do-envio]').text()).toContain(
      'These products sold out in the catalog: Tênis, Mochila'
    );
    expect(wrapper.findAll('[data-produto-acabou]')).toHaveLength(2);
    expect(
      wrapper.find('[data-enviar-modelo]').attributes('disabled')
    ).toBeDefined();
  });

  it('catálogo desligado: mostra o que fazer e não abre a gaveta', async () => {
    api.obterCatalogo.mockResolvedValue(null);
    const wrapper = montar();
    await wrapper.vm.abrir(varios);
    await flushPromises();

    expect(wrapper.find('[data-sem-catalogo]').exists()).toBe(true);
    expect(wrapper.find('[data-gaveta]').exists()).toBe(false);
    expect(wrapper.text()).toContain('This WhatsApp has no product catalog');
  });

  it('o catálogo que some no enviar também leva ao "sem catálogo"', async () => {
    api.conferirProdutos.mockRejectedValue({ codigo: 'catalog_missing' });
    const wrapper = montar();
    await escolherVarios(wrapper);
    await wrapper.find('[data-campo-da-mensagem="2"] input').setValue('tudo');
    await wrapper.find('[data-enviar-modelo]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-sem-catalogo]').exists()).toBe(true);
    expect(wrapper.emitted('enviar')).toBeUndefined();
  });
});

describe('EnviarModeloDaConversa: carrossel de fotos (#1716)', () => {
  it('cartão a cartão: foto acima de 5 MB recusada com o motivo; foto do modelo e texto liberam o próximo', async () => {
    const wrapper = montar();
    await wrapper.vm.abrir(fotos);
    await flushPromises();
    expect(wrapper.text()).toContain('Card 1 of 2');
    expect(
      wrapper.find('[data-proximo-cartao]').attributes('disabled')
    ).toBeDefined();

    const grande = new File(['x'], 'grande.jpg', { type: 'image/jpeg' });
    Object.defineProperty(grande, 'size', { value: 12.7 * 1024 * 1024 });
    const seletor = wrapper.find('[data-arquivo-do-cartao]');
    Object.defineProperty(seletor.element, 'files', { value: [grande] });
    await seletor.trigger('change');
    expect(wrapper.find('[data-erro-da-foto]').text()).toContain(
      'This photo is 12.7 MB, and WhatsApp accepts up to 5 MB.'
    );
    expect(api.subirArquivoDaCampanha).not.toHaveBeenCalled();

    await wrapper.find('[data-foto-da-galeria="a.jpg"]').trigger('click');
    await wrapper.find('[data-campo-do-cartao="1"] input').setValue('o tênis');
    expect(
      wrapper.find('[data-proximo-cartao]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.find('[data-proximo-cartao]').trigger('click');
    expect(wrapper.text()).toContain('Card 2 of 2');
  });

  it('foto do computador que termina de subir depois do "Próximo" fica no cartão que a pediu', async () => {
    let terminar;
    api.subirArquivoDaCampanha.mockReturnValue(
      new Promise(resolve => {
        terminar = resolve;
      })
    );
    global.URL.createObjectURL = vi.fn(() => 'blob:local');
    const wrapper = montar();
    await wrapper.vm.abrir(fotos);
    await flushPromises();
    await wrapper.find('[data-foto-da-galeria="a.jpg"]').trigger('click');
    await wrapper.find('[data-campo-do-cartao="1"] input').setValue('o tênis');

    const foto = new File(['x'], 'nova.jpg', { type: 'image/jpeg' });
    const seletor = wrapper.find('[data-arquivo-do-cartao]');
    Object.defineProperty(seletor.element, 'files', { value: [foto] });
    await seletor.trigger('change');
    await wrapper.find('[data-proximo-cartao]').trigger('click');
    expect(wrapper.text()).toContain('Card 2 of 2');
    terminar({ referencia: 'nova', nome: 'nova.jpg' });
    await flushPromises();

    expect(wrapper.find('[data-foto-do-computador]').exists()).toBe(false);
    expect(
      wrapper.find('[data-proximo-cartao]').attributes('disabled')
    ).toBeDefined();
  });
});

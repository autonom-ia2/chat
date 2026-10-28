import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import BlocoEtiquetas from '../etiquetas/BlocoEtiquetas.vue';
import { criarI18n, criarStore } from './apoio';

// #2202 (PR 3) — etiquetas da conversa no painel novo: o bloco aparece só quando
// a conversa tem etiqueta, cada uma com cor e nome; quem opera toca e abre a
// escolha; quem só lê vê sem botão. A escolha tem o spec dela
// (EtiquetasDaConversaDialog.spec.js).

enableAutoUnmount(afterEach);

const CONVERSA = { id: 42, inbox_id: 1, meta: {} };
const ETIQUETAS_DA_CONTA = [
  { id: 1, title: 'vip', color: '#ff0000' },
  { id: 2, title: 'retorno', color: '#00aa00' },
  { id: 3, title: 'boleto', color: '#0000ff' },
];

const abrir = vi.fn();
const EscolhaStub = {
  template: '<div data-escolha />',
  methods: { abrir },
};

const montarBloco = ({
  etiquetas = [],
  podeOperar = true,
  focarAoSumir = vi.fn(),
} = {}) => {
  const apoio = criarStore({
    conversaSelecionada: CONVERSA,
    etiquetasDaConta: ETIQUETAS_DA_CONTA,
    etiquetasDaConversa: { 42: etiquetas },
  });
  const wrapper = mount(BlocoEtiquetas, {
    attachTo: document.body,
    props: { podeOperar, focarAoSumir },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: { EtiquetasDaConversaDialog: EscolhaStub },
    },
  });
  return { wrapper, focarAoSumir, ...apoio };
};

beforeEach(() => vi.clearAllMocks());

describe('BlocoEtiquetas', () => {
  it('conversa sem etiqueta: o bloco não aparece', () => {
    const { wrapper } = montarBloco();
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('Etiquetas');
  });

  it('com etiqueta: título, nome e cor de cada uma', () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip', 'retorno'] });
    const bloco = wrapper.get('[data-test-id="bloco-etiquetas"]');
    expect(bloco.get('h3').text()).toBe('Etiquetas desta conversa');
    const itens = bloco.findAll('[data-test-id="etiqueta"]');
    expect(itens.map(item => item.text())).toEqual(['vip', 'retorno']);
    expect(itens[0].get('span').attributes('style')).toContain(
      'background-color: rgb(255, 0, 0)'
    );
    expect(bloco.text()).not.toContain('boleto');
  });

  it('quem opera toca nas etiquetas e abre a escolha', async () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip'] });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    expect(alvo.element.tagName).toBe('BUTTON');
    // O leitor de tela ouve quais etiquetas a conversa tem, não só "mudar".
    expect(alvo.attributes('aria-label')).toBe(
      'Mudar as etiquetas desta conversa: vip'
    );
    expect(alvo.find('ul').exists()).toBe(false);
    expect(alvo.classes()).toContain('min-h-11');
    await alvo.trigger('click');
    expect(abrir).toHaveBeenCalledTimes(1);
  });

  it('quem só lê vê as etiquetas sem botão e sem a escolha', async () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip'], podeOperar: false });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    expect(alvo.element.tagName).toBe('DIV');
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('[data-escolha]').exists()).toBe(false);
    await alvo.trigger('click');
    expect(abrir).not.toHaveBeenCalled();
  });

  it('tirar a última etiqueta some com o bloco, mas não com a escolha', async () => {
    const { wrapper, dados } = montarBloco({ etiquetas: ['vip'] });
    dados.etiquetasDaConversa = { 42: [] };
    await flushPromises();
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-escolha]').exists()).toBe(true);
  });

  it('ao fechar a escolha, o foco volta para o bloco', async () => {
    const { wrapper, focarAoSumir } = montarBloco({ etiquetas: ['vip'] });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    await alvo.trigger('click');
    const [devolverFoco] = abrir.mock.calls[0];
    devolverFoco();
    expect(document.activeElement).toBe(alvo.element);
    expect(focarAoSumir).not.toHaveBeenCalled();
  });

  it('se o bloco sumiu (tirou a última), o foco vai para onde o painel manda', async () => {
    const { wrapper, dados, focarAoSumir } = montarBloco({
      etiquetas: ['vip'],
    });
    await wrapper
      .get('[data-test-id="etiquetas-da-conversa"]')
      .trigger('click');
    const [devolverFoco] = abrir.mock.calls[0];
    dados.etiquetasDaConversa = { 42: [] };
    await flushPromises();
    devolverFoco();
    expect(focarAoSumir).toHaveBeenCalledTimes(1);
  });
});

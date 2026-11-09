import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import MobileSidebarLauncher from '../MobileSidebarLauncher.vue';
import {
  ATRASO_PARA_VOLTAR_MS,
  TEMPO_MAXIMO_ESCONDIDO_MS,
} from '../useEscondeAoRolar';

// #2211 — no celular, a conversa vazia ("Escrever" na busca da lista) é tela de conversa: o botão do menu
// some, como numa conversa aberta. Só com a chave lista_quem_espera; desligada, fica como na main.
const rota = { name: 'home', query: { comecar: '3' } };
const listaNova = ref(true);
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useListaNova',
  () => ({ useListaNova: () => listaNova })
);

const montar = (props = {}) =>
  mount(MobileSidebarLauncher, {
    props,
    attachTo: document.body,
    global: { stubs: { Button: true, ButtonGroup: true } },
  });
let montado;
const botao = () => {
  montado = montar();
  return montado.find('#mobile-sidebar-launcher');
};

describe('MobileSidebarLauncher com a conversa vazia (#2211)', () => {
  afterEach(() => montado?.unmount());

  it('chave ligada: na conversa vazia, o botão do menu some', () => {
    listaNova.value = true;
    expect(botao().exists()).toBe(false);
  });

  it('chave desligada: ?comecar= não muda nada, o botão continua', () => {
    listaNova.value = false;
    expect(botao().exists()).toBe(true);
  });
});

// #2207 — no celular, o botão some enquanto a página rola e volta quando a rolagem para. O painel rola numa
// div interna (o <main> é overflow-hidden), então o botão ouve a rolagem de qualquer elemento.
describe('MobileSidebarLauncher ao rolar (#2207)', () => {
  let wrapper;
  let lista;
  const escondido = () =>
    wrapper.find('#mobile-sidebar-launcher').classes().includes('opacity-0');
  const rolar = () => lista.dispatchEvent(new Event('scroll'));

  beforeEach(() => {
    vi.useFakeTimers();
    rota.name = 'contacts_dashboard_index';
    rota.query = {};
    lista = document.createElement('div');
    document.body.appendChild(lista);
  });

  afterEach(() => {
    wrapper?.unmount();
    lista.remove();
    vi.useRealTimers();
  });

  it('some enquanto uma lista interna rola e volta quando a rolagem para', async () => {
    wrapper = montar();
    expect(escondido()).toBe(false);

    rolar();
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(true);

    vi.advanceTimersByTime(ATRASO_PARA_VOLTAR_MS - 1);
    rolar();
    vi.advanceTimersByTime(ATRASO_PARA_VOLTAR_MS - 1);
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(true);

    vi.advanceTimersByTime(1);
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(false);
  });

  it('a rolagem da página inteira (document) também esconde', async () => {
    wrapper = montar();
    document.dispatchEvent(new Event('scroll'));
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(true);
  });

  it('rolagem sem fim não esconde o botão para sempre', async () => {
    wrapper = montar();
    const passo = ATRASO_PARA_VOLTAR_MS / 2;
    for (let t = 0; t < TEMPO_MAXIMO_ESCONDIDO_MS; t += passo) {
      rolar();
      vi.advanceTimersByTime(passo);
    }
    rolar();
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(false);
  });

  it('escondido, continua no teclado (guarda de classe: não sai da ordem de tabulação)', async () => {
    wrapper = montar();
    rolar();
    await wrapper.vm.$nextTick();
    const caixa = wrapper.find('#mobile-sidebar-launcher').classes();
    expect(caixa).not.toContain('invisible');
    expect(caixa).not.toContain('hidden');
    expect(caixa).toContain('focus-within:opacity-100');
  });

  it('com o foco no botão, a rolagem não o esconde', async () => {
    wrapper = montar();
    const caixa = wrapper.find('#mobile-sidebar-launcher').element;
    const alvo = document.createElement('button');
    caixa.appendChild(alvo);
    alvo.focus();
    rolar();
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(false);
  });

  it('com o menu aberto, a rolagem não esconde o botão', async () => {
    wrapper = montar({ isMobileSidebarOpen: true });
    rolar();
    await wrapper.vm.$nextTick();
    expect(escondido()).toBe(false);
  });

  it('respeita quem pediu menos movimento (guarda de classe: sem transição)', () => {
    wrapper = montar();
    expect(wrapper.find('#mobile-sidebar-launcher').classes()).toContain(
      'motion-reduce:transition-none'
    );
  });

  it('ao sair da tela, para de ouvir a rolagem e não deixa relógio', async () => {
    const remover = vi.spyOn(document, 'removeEventListener');
    wrapper = montar();
    rolar();
    wrapper.unmount();
    wrapper = null;
    expect(remover).toHaveBeenCalledWith('scroll', expect.any(Function), {
      capture: true,
    });
    expect(vi.getTimerCount()).toBe(0);
    remover.mockRestore();
  });
});

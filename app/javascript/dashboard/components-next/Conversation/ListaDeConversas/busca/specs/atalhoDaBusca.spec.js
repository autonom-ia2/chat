import { mount, enableAutoUnmount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import conversationRoutes from 'dashboard/routes/dashboard/conversation/conversation.routes';
import {
  ROTAS_DE_CONVERSAS,
  focoAtendido,
  pedidoDeFoco,
  useAtalhoDaBusca,
} from '../atalhoDaBusca';

// #2211 (decisão do Rodrigo) — ⌘/Ctrl+K foca o campo da lista só na tela de Conversas. Fora dela,
// ou sem a chave, o ⌘K segue para a barra de comandos (o evento passa), sem navegar.
const rota = reactive({ name: 'home' });
const ligada = ref(true);
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock('../../useListaNova', () => ({ useListaNova: () => ligada }));
vi.mock('dashboard/store', () => ({ default: { getters: {} } }));

enableAutoUnmount(afterEach);

const montar = () =>
  mount({ template: '<div />', setup: () => useAtalhoDaBusca() });

// O que a barra de comandos (que escuta depois) recebe.
const barraDeComandos = vi.fn();
const apertar = (extras = {}) => {
  const evento = new KeyboardEvent('keydown', {
    code: 'KeyK',
    key: 'k',
    metaKey: true,
    bubbles: true,
    cancelable: true,
    ...extras,
  });
  document.body.dispatchEvent(evento);
  return evento;
};

// O jsdom não mede: o campo "visível" tem retângulo.
const campoNaTela = (visivel = true) => {
  document.body.innerHTML = '<input data-campo-da-busca />';
  document.querySelector('[data-campo-da-busca]').getClientRects = () =>
    visivel ? [{ width: 1 }] : [];
};

describe('useAtalhoDaBusca', () => {
  beforeEach(() => {
    rota.name = 'home';
    ligada.value = true;
    document.body.innerHTML = '';
    barraDeComandos.mockReset();
    document.addEventListener('keydown', barraDeComandos);
  });
  afterEach(() => document.removeEventListener('keydown', barraDeComandos));

  it('em Conversas, com o campo na tela: pede foco e a barra de comandos não abre', () => {
    campoNaTela();
    montar();
    const antes = pedidoDeFoco.value;
    const evento = apertar({ metaKey: false, ctrlKey: true });
    expect(evento.defaultPrevented).toBe(true);
    expect(pedidoDeFoco.value).toBe(antes + 1);
    expect(barraDeComandos).not.toHaveBeenCalled();
  });

  it('na conversa aberta também (rota da conversa)', () => {
    rota.name = 'inbox_conversation';
    campoNaTela();
    montar();
    expect(apertar().defaultPrevented).toBe(true);
  });

  it('em Configurações: a barra de comandos abre, sem pedir foco', () => {
    rota.name = 'general_settings_index';
    montar();
    const antes = pedidoDeFoco.value;
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(false);
    expect(barraDeComandos).toHaveBeenCalledTimes(1);
    expect(pedidoDeFoco.value).toBe(antes);
  });

  it('em Conversas com o campo escondido (filtro avançado, pasta): a barra abre e nada fica pendente', () => {
    campoNaTela(false);
    montar();
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(false);
    expect(barraDeComandos).toHaveBeenCalledTimes(1);
    expect(focoAtendido.value).toBe(pedidoDeFoco.value);
  });

  it('barra de comandos já aberta: o ⌘K fica com ela e o foco não vai para a busca atrás', () => {
    campoNaTela();
    const barra = document.createElement('ninja-keys');
    barra.visible = true;
    document.body.appendChild(barra);
    montar();
    const antes = pedidoDeFoco.value;
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(false);
    expect(barraDeComandos).toHaveBeenCalledTimes(1);
    expect(pedidoDeFoco.value).toBe(antes);
    expect(focoAtendido.value).toBe(pedidoDeFoco.value);

    // Fechada, o ⌘K volta a focar a busca.
    barra.visible = false;
    expect(apertar().defaultPrevented).toBe(true);
    expect(pedidoDeFoco.value).toBe(antes + 1);
  });

  it('sem a chave lista_quem_espera, igual à main: o ⌘K passa para a barra de comandos', () => {
    ligada.value = false;
    campoNaTela();
    montar();
    const antes = pedidoDeFoco.value;
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(false);
    expect(barraDeComandos).toHaveBeenCalledTimes(1);
    expect(pedidoDeFoco.value).toBe(antes);
  });

  it('⌘⇧K não é o atalho', () => {
    campoNaTela();
    montar();
    expect(apertar({ shiftKey: true }).defaultPrevented).toBe(false);
  });

  it('a lista de rotas é a das telas de Conversas (conversation.routes)', () => {
    const daLista = conversationRoutes.routes.map(r => r.name).filter(Boolean);
    expect([...ROTAS_DE_CONVERSAS].sort()).toEqual(
      [...new Set(daLista)].sort()
    );
  });
});

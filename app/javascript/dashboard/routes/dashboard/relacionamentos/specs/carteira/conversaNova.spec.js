import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import ConversaNova from '../../components/carteira/ConversaNova.vue';

// #3057 (2ª rodada) — "Conversar" com quem ainda não tem conversa abre a "Nova
// conversa" da casa já com a pessoa: a ponte NovaConversaEntrada com
// `contact-id`, o mesmo caminho do "Enviar mensagem" da página do contato. A
// ponte é de mentira aqui (abre pelo clique no gatilho, como as de verdade); a
// loja e a regra de quem pode começar conversa também.
const loja = vi.hoisted(() => ({ dispatch: null }));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ dispatch: (...args) => loja.dispatch(...args) }),
}));
const quem = vi.hoisted(() => ({ podeComecar: true }));
vi.mock(
  'dashboard/components-next/NovaConversa/usePodeComecarConversa',
  async () => {
    const { computed } = await import('vue');
    return { usePodeComecarConversa: () => computed(() => quem.podeComecar) };
  }
);
const ponte = vi.hoisted(() => ({ aberturas: [] }));
vi.mock(
  'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue',
  () => ({
    default: defineComponent({
      name: 'NovaConversaEntrada',
      props: { contactId: { type: String, default: null } },
      setup(props, { slots }) {
        const aberta = ref(false);
        const alternar = () => {
          aberta.value = !aberta.value;
          if (aberta.value) ponte.aberturas.push(props.contactId);
        };
        return () =>
          h('span', { 'data-ponte': '', onClick: alternar }, slots.trigger?.());
      },
    }),
  })
);

let aberta;
const montar = () => {
  aberta = mount(ConversaNova, { attachTo: document.body });
  return aberta;
};

beforeEach(() => {
  loja.dispatch = vi.fn().mockResolvedValue({});
  quem.podeComecar = true;
  ponte.aberturas = [];
});
afterEach(() => {
  aberta?.unmount();
  aberta = null;
});

describe('ConversaNova', () => {
  it('busca o contato e abre a "Nova conversa" já com ele', async () => {
    const w = montar();

    const abriu = await w.vm.abrir(23);
    await flushPromises();

    expect(abriu).toBe(true);
    expect(loja.dispatch).toHaveBeenCalledWith('contacts/show', { id: 23 });
    expect(ponte.aberturas).toEqual(['23']);
    expect(
      w.getComponent({ name: 'NovaConversaEntrada' }).props('contactId')
    ).toBe('23');
  });

  it('o gatilho fica fora da vista e fora do Tab', async () => {
    const w = montar();
    await w.vm.abrir(23);

    const gatilho = w.get('[data-carteira="abrir-conversa-nova"]');
    expect(gatilho.classes()).toContain('sr-only');
    expect(gatilho.attributes('tabindex')).toBe('-1');
    expect(gatilho.attributes('aria-hidden')).toBe('true');
  });

  it('quem só lê conversas: não abre e devolve false', async () => {
    quem.podeComecar = false;
    const w = montar();

    expect(await w.vm.abrir(23)).toBe(false);
    expect(loja.dispatch).not.toHaveBeenCalled();
    expect(ponte.aberturas).toEqual([]);
  });

  it('o contato não veio: não abre e devolve false', async () => {
    loja.dispatch.mockRejectedValue(new Error('404'));
    const w = montar();

    expect(await w.vm.abrir(23)).toBe(false);
    expect(ponte.aberturas).toEqual([]);
  });
});

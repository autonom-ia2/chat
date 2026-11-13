import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import RamoNaPagina from '../../components/pagina/RamoNaPagina.vue';

// #2976 — na página do agente que nasceu de um agente pronto por ramo e já atende: o que ele pergunta e os documentos
// que pede, com as mesmas gavetas da Confira. A mudança vai ao servidor pelo agente, com a lista inteira. Cópia real.
const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ getters: {}, dispatch: store.dispatch }),
    // A gaveta abre num TeleportWithDirection, que lê a direção do texto na store.
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

withFullI18n('pt_BR');

const PERGUNTAS = [
  { id: 'p1', texto: 'Qual o CNPJ da empresa?', tirada: false },
  { id: 'p2', texto: 'Qual o valor da garantia?', tirada: true },
];
const DOCUMENTOS = [{ id: 'd1', texto: 'Edital ou contrato.', tirada: false }];
const AGENTE = {
  id: 7,
  listas_do_ramo: { perguntas: PERGUNTAS, documentos: DOCUMENTOS },
};

const montadas = [];
const montar = (props = {}) => {
  const wrapper = mount(RamoNaPagina, {
    props: { agente: AGENTE, nome: 'Bia', podeMudar: true, ...props },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};
const linha = (wrapper, chave) => wrapper.get(`[data-linha="${chave}"]`);
const gaveta = () => document.body.querySelector('[role="dialog"]');
// Abre as perguntas, edita a primeira e salva.
const editarAPrimeira = async (wrapper, texto) => {
  await linha(wrapper, 'perguntas').get('button').trigger('click');
  gaveta().querySelector('[data-item="p1"] [data-editar-item]').click();
  await flushPromises();
  const campo = gaveta().querySelector('[data-editando] textarea');
  campo.value = texto;
  campo.dispatchEvent(new Event('input'));
  await flushPromises();
  gaveta().querySelector('[data-salvar-item]').click();
  await flushPromises();
};

beforeEach(() => {
  store.dispatch.mockReset().mockResolvedValue(null);
  alerta.mockReset();
});

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('RamoNaPagina', () => {
  it('shows what the agent asks and requests, counting only what the owner kept, with no tools line', () => {
    const wrapper = montar();

    expect(wrapper.get('h2').text()).toBe('O que Bia pergunta e pede');
    expect(wrapper.get('[data-nota-do-ramo]').text()).toBe(
      'O que você mudar aqui, Bia já segue na próxima mensagem do cliente.'
    );
    expect(linha(wrapper, 'perguntas').text()).toContain(
      'Perguntas ao cliente, uma por vez: 1'
    );
    expect(linha(wrapper, 'documentos').text()).toContain(
      'Documentos que pede: 1'
    );
    expect(wrapper.find('[data-linha="ferramentas"]').exists()).toBe(false);
  });

  it('does not show for an agent that was not born from a ready-made agent', () => {
    const wrapper = montar({ agente: { id: 9 } });

    expect(wrapper.find('[data-pronto-do-ramo]').exists()).toBe(false);
  });

  it('sends the whole new list to the server through the agent', async () => {
    const wrapper = montar();

    await linha(wrapper, 'perguntas').get('button').trigger('click');
    gaveta().querySelector('[data-item="p1"] [data-tirar-item]').click();
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/mudarModeloPronto',
      {
        agentId: 7,
        listas: {
          perguntas: [{ ...PERGUNTAS[0], tirada: true }, PERGUNTAS[1]],
        },
      }
    );
    expect(alerta).not.toHaveBeenCalled();
  });

  it('warns in a short line when the server refuses the change', async () => {
    store.dispatch.mockRejectedValue(new Error('recusado'));
    const wrapper = montar();

    await linha(wrapper, 'documentos').get('button').trigger('click');
    gaveta().querySelector('[data-item="d1"] [data-tirar-item]').click();
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      'Não consegui guardar a mudança. Tente de novo.'
    );
  });

  it('closes the edit field once the server keeps the change', async () => {
    const wrapper = montar();

    await editarAPrimeira(wrapper, 'Qual o CNPJ de quem contrata?');

    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/mudarModeloPronto',
      {
        agentId: 7,
        listas: {
          perguntas: [
            { ...PERGUNTAS[0], texto: 'Qual o CNPJ de quem contrata?' },
            PERGUNTAS[1],
          ],
        },
      }
    );
    expect(gaveta().querySelector('[data-editando]')).toBeNull();
    expect(alerta).not.toHaveBeenCalled();
  });

  it('when the server refuses, warns and keeps the edit field open with what the owner typed', async () => {
    store.dispatch.mockRejectedValue(new Error('recusado'));
    const wrapper = montar();

    await editarAPrimeira(wrapper, 'Qual o CNPJ de quem contrata?');

    expect(alerta).toHaveBeenCalledWith(
      'Não consegui guardar a mudança. Tente de novo.'
    );
    expect(gaveta().querySelector('[data-editando] textarea').value).toBe(
      'Qual o CNPJ de quem contrata?'
    );
    // O pedido terminou: dá para tentar de novo.
    expect(
      gaveta().querySelector('[data-salvar-item]').getAttribute('aria-disabled')
    ).toBeNull();
  });

  it('opens the lists read-only, with no note, for who can only see', async () => {
    const wrapper = montar({ podeMudar: false });

    expect(wrapper.find('[data-nota-do-ramo]').exists()).toBe(false);
    await linha(wrapper, 'perguntas').get('button').trigger('click');

    expect(gaveta().querySelectorAll('[data-item]')).toHaveLength(2);
    expect(gaveta().textContent).toContain('uma coisa por vez, nesta ordem');
    expect(gaveta().textContent).not.toContain('Você pode tirar');
    expect(gaveta().querySelector('[data-tirar-item]')).toBeNull();
    expect(gaveta().querySelector('[data-incluir-item]')).toBeNull();
  });
});

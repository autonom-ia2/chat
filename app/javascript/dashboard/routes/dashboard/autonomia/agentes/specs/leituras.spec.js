import { defineComponent, h } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useNumerosDaSemana } from '../composables/useNumerosDaSemana';
import { useCanaisOcupados } from '../composables/useCanaisOcupados';

const api = vi.hoisted(() => ({ semana: vi.fn(), canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));

// Monta um componente mínimo que usa o composable, como as telas fazem.
const montarCom = usar => {
  let exposto;
  const Casca = defineComponent({
    setup() {
      exposto = usar();
      return () => h('div');
    },
  });
  const wrapper = mount(Casca);
  return { wrapper, exposto: () => exposto };
};

describe('useNumerosDaSemana (L1)', () => {
  beforeEach(() => {
    api.semana.mockResolvedValue({
      data: {
        range: '7d',
        payload: [
          { agent_id: 1, answered: 12, handed: 3 },
          { agent_id: 2, answered: 0, handed: 0 },
        ],
      },
    });
  });

  it('does not call the API when nobody mounts it', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    useNumerosDaSemana();
    expect(api.semana).not.toHaveBeenCalled();
  });

  it('starts loading and then returns the numbers of each agent', async () => {
    const { exposto } = montarCom(() => useNumerosDaSemana());
    expect(exposto().estado.value).toBe('carregando');
    await flushPromises();

    expect(api.semana).toHaveBeenCalledTimes(1);
    expect(api.semana).toHaveBeenCalledWith({});
    expect(exposto().estado.value).toBe('pronto');
    expect(exposto().numerosDe(1)).toEqual({ respondidas: 12, passadas: 3 });
  });

  it('gives zero to an agent the reading does not list', async () => {
    const { exposto } = montarCom(() => useNumerosDaSemana());
    await flushPromises();
    expect(exposto().numerosDe(99)).toEqual({ respondidas: 0, passadas: 0 });
  });

  it('asks for one agent when given one', async () => {
    montarCom(() => useNumerosDaSemana({ agentId: 2 }));
    await flushPromises();
    expect(api.semana).toHaveBeenCalledWith({ agentId: 2 });
  });

  it('turns a failure into "erro" and gives no numbers', async () => {
    api.semana.mockRejectedValue(new Error('500'));
    const { exposto } = montarCom(() => useNumerosDaSemana());
    await flushPromises();

    expect(exposto().estado.value).toBe('erro');
    expect(exposto().numerosDe(1)).toBeNull();
  });
});

describe('useCanaisOcupados (L2)', () => {
  const payload = [
    { inbox_id: 10, name: 'WhatsApp', occupied_by: null },
    { inbox_id: 11, name: 'Site', occupied_by: { kind: 'external' } },
  ];

  beforeEach(() => {
    api.canaisOcupados.mockResolvedValue({ data: { payload } });
  });

  it('does not call the API when nobody mounts it', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    useCanaisOcupados();
    expect(api.canaisOcupados).not.toHaveBeenCalled();
  });

  it('loads the inboxes with who answers them', async () => {
    const { exposto } = montarCom(() => useCanaisOcupados());
    expect(exposto().estado.value).toBe('carregando');
    await flushPromises();

    expect(api.canaisOcupados).toHaveBeenCalledTimes(1);
    expect(exposto().estado.value).toBe('pronto');
    expect(exposto().canais.value).toEqual(payload);
  });

  it('turns a failure into "erro" with an empty list', async () => {
    api.canaisOcupados.mockRejectedValue(new Error('500'));
    const { exposto } = montarCom(() => useCanaisOcupados());
    await flushPromises();

    expect(exposto().estado.value).toBe('erro');
    expect(exposto().canais.value).toEqual([]);
  });

  it('reloads on demand', async () => {
    const { exposto } = montarCom(() => useCanaisOcupados());
    await flushPromises();
    await exposto().carregar();
    expect(api.canaisOcupados).toHaveBeenCalledTimes(2);
  });
});

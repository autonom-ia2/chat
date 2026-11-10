import { mount } from '@vue/test-utils';
import { computed, defineComponent, ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import { useProntasDoConstrutor } from '../../vitrine/useProntasDoConstrutor';

// #2858 F3 — o "Começar" inclui as prontas que ficaram no "Já vem com", pela pessoa real e com a permissão dela. O que
// a pessoa tirou, o que a conta não tem liberado e o que o agente já tem não entram. Sem a chave, nada é incluído e
// a tela explica.
withFullI18n('pt_BR');

const vitrine = vi.hoisted(() => ({
  carregar: vi.fn(),
  tem: vi.fn(),
  incluir: vi.fn(),
  fontes: null,
}));
vi.mock('../../vitrine/useVitrine', () => ({ useVitrine: () => vitrine }));
const ligada = vi.hoisted(() => ({ construtor: null, naConta: null }));
vi.mock('../../vitrine/useVitrineLigada', () => ({
  useVitrineLigada: () => ({
    construtor: ligada.construtor,
    construtorNaConta: ligada.naConta,
  }),
}));

const montadas = [];
// useI18n pede um componente: o composable roda no setup de um componente vazio.
const usar = (sugeridas = ['fipe', 'cep', 'cpf']) => {
  let prontas;
  const wrapper = mount(
    defineComponent({
      setup() {
        prontas = useProntasDoConstrutor({
          agenteId: computed(() => 7),
          sugeridas: ref(sugeridas),
        });
        return () => null;
      },
    })
  );
  montadas.push(wrapper);
  return prontas;
};

afterEach(() => montadas.splice(0).forEach(wrapper => wrapper.unmount()));

beforeEach(() => {
  ligada.construtor = ref(true);
  ligada.naConta = ref(true);
  vitrine.fontes = ref(['fipe', 'cep', 'cpf']);
  vitrine.carregar.mockReset().mockResolvedValue();
  vitrine.tem.mockReset().mockReturnValue(false);
  vitrine.incluir.mockReset().mockResolvedValue({});
});

describe('useProntasDoConstrutor', () => {
  it('includes what stayed, with the "Use when" sentence of each tool', async () => {
    const prontas = usar();
    prontas.tirar('cep');

    expect(prontas.visiveis.value).toEqual(['fipe', 'cpf']);
    expect(await prontas.incluirTodas()).toEqual([]);
    expect(vitrine.incluir).toHaveBeenCalledTimes(2);
    expect(vitrine.incluir).toHaveBeenCalledWith({
      fonte: 'fipe',
      agenteId: 7,
      usarQuando:
        'Use quando o cliente quiser saber quanto vale um carro, moto ou caminhão.',
    });
  });

  it('skips what the agent already has and what the account no longer releases; reports failures', async () => {
    vitrine.fontes = ref(['fipe', 'cep']);
    vitrine.tem.mockImplementation((_, id) => id === 'fipe');
    vitrine.incluir.mockRejectedValue(new Error('GERAL'));
    const prontas = usar();

    expect(await prontas.incluirTodas()).toEqual(['cep']);
    expect(vitrine.incluir).toHaveBeenCalledTimes(1);
  });

  it('ignores unknown keys and an empty list ("none fits")', () => {
    expect(usar(['inventada', 'fipe']).visiveis.value).toEqual(['fipe']);
    expect(usar([]).visiveis.value).toEqual([]);
  });

  it('without the tools key: nothing included, the screen explains', async () => {
    ligada.construtor = ref(false);
    const prontas = usar();

    expect(prontas.visiveis.value).toEqual([]);
    expect(prontas.semPermissao.value).toBe(true);
    expect(prontas.escolhidas.value).toEqual(['fipe', 'cep', 'cpf']);
    expect(await prontas.incluirTodas()).toEqual([]);
    expect(vitrine.incluir).not.toHaveBeenCalled();
  });

  it('without the Construtor flag on the account: nothing at all', () => {
    ligada.construtor = ref(false);
    ligada.naConta = ref(false);
    const prontas = usar();

    expect(prontas.escolhidas.value).toEqual([]);
    expect(prontas.semPermissao.value).toBe(false);
  });
});

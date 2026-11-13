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
  erro: null,
}));
const api = vi.hoisted(() => ({ dispensar: vi.fn() }));
vi.mock('dashboard/api/autonomia/ferramentasProntas', () => ({
  default: api,
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
const usar = (
  sugeridas = ['fipe', 'cep', 'cpf'],
  tambem = [],
  frases = undefined,
  ficaramFora = undefined
) => {
  let prontas;
  const wrapper = mount(
    defineComponent({
      setup() {
        prontas = useProntasDoConstrutor({
          agenteId: computed(() => 7),
          sugeridas: ref(sugeridas),
          tambem: ref(tambem),
          frases,
          ficaramFora,
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
  vitrine.erro = ref('');
  api.dispensar.mockReset().mockResolvedValue({});
  vitrine.carregar.mockReset().mockResolvedValue();
  vitrine.tem.mockReset().mockReturnValue(false);
  vitrine.incluir.mockReset().mockResolvedValue({});
});

describe('useProntasDoConstrutor', () => {
  it('never shows nor includes an internal-use source from an old draft', async () => {
    const prontas = usar(
      ['fipe', 'produtos_seguradoras'],
      ['produtos_seguradoras', 'cep']
    );

    expect(prontas.visiveis.value).toEqual(['fipe']);
    expect(prontas.combinaTambem.value).toEqual(['cep']);
    await prontas.incluirTodas();
    expect(vitrine.incluir).not.toHaveBeenCalledWith(
      expect.objectContaining({ fonte: 'produtos_seguradoras' })
    );
  });

  it('includes what stayed, with the "Use when" sentence of each tool', async () => {
    const prontas = usar();
    prontas.tirar('cep');

    expect(prontas.visiveis.value).toEqual(['fipe', 'cpf']);
    expect(await prontas.incluirTodas()).toEqual([]);
    expect(api.dispensar).toHaveBeenCalledWith(7, 'cep');
    expect(vitrine.incluir).toHaveBeenCalledTimes(2);
    expect(vitrine.incluir).toHaveBeenCalledWith({
      fonte: 'fipe',
      agenteId: 7,
      usarQuando:
        'Use quando o cliente quiser saber quanto vale um carro, moto ou caminhão. Se a consulta pela placa estiver disponível, use também quando ele informar a placa.',
    });
  });

  // #2881 — agente pronto por ramo: a frase que vai com a ferramenta é a do ramo (ou a que o dono alterou).
  it('with a line-of-insurance model, includes each tool with the sentence of the line, also the "also fits" ones', async () => {
    vitrine.fontes = ref(['cnpj', 'cep', 'cidades']);
    const frases = ref({
      cnpj: 'Use quando o cliente informar o CNPJ da empresa que vai contratar a garantia.',
      cidades: 'Use quando o cliente disser a cidade da licitação.',
    });
    const prontas = usar(['cnpj', 'cep'], ['cidades'], frases);
    prontas.incluirTambem();

    expect(await prontas.incluirTodas()).toEqual([]);
    expect(vitrine.incluir).toHaveBeenCalledWith({
      fonte: 'cnpj',
      agenteId: 7,
      usarQuando:
        'Use quando o cliente informar o CNPJ da empresa que vai contratar a garantia.',
    });
    expect(vitrine.incluir).toHaveBeenCalledWith({
      fonte: 'cidades',
      agenteId: 7,
      usarQuando: 'Use quando o cliente disser a cidade da licitação.',
    });
    // Sem frase do ramo para a fonte, vai a geral da vitrine.
    const doCep = vitrine.incluir.mock.calls.find(
      ([pedido]) => pedido.fonte === 'cep'
    )[0];
    expect(doCep.usarQuando.startsWith('Use quando')).toBe(true);
    expect(doCep.usarQuando).not.toBe(frases.value.cnpj);
  });

  it('the sentence follows what the owner changed up to the "Start"', async () => {
    const frases = ref({ fipe: 'Use quando o cliente disser o modelo.' });
    const prontas = usar(['fipe'], [], frases);
    frases.value = { fipe: 'Use quando o cliente disser a placa.' };

    await prontas.incluirTodas();

    expect(vitrine.incluir).toHaveBeenCalledWith(
      expect.objectContaining({
        usarQuando: 'Use quando o cliente disser a placa.',
      })
    );
  });

  // #2881 — no ramo, o que o dono tirou volta do servidor no "Também combina": o que ficou fora do "Já vem com" vira
  // "Agora não" no "Começar", para o cartão "pode ganhar" não oferecer de volta.
  it('with a line-of-insurance model, "Start" records as "Not now" the tools of the line left out of the "comes with" list', async () => {
    vitrine.fontes = ref(['cnpj', 'cep', 'cidades']);
    const ficaramFora = ref(['cidades']);
    const prontas = usar(['cnpj', 'cep'], ['cidades'], undefined, ficaramFora);
    // O dono tirou o CNPJ no meio do caminho: o servidor passou a devolvê-lo no "Também combina".
    ficaramFora.value = ['cnpj', 'cidades'];

    await prontas.incluirTodas();

    expect(api.dispensar.mock.calls).toEqual([
      [7, 'cnpj'],
      [7, 'cidades'],
    ]);
  });

  it('without a line-of-insurance model, the "also fits" tools nobody removed are not recorded as "Not now"', async () => {
    const prontas = usar(['fipe'], ['cep']);

    await prontas.incluirTodas();

    expect(api.dispensar).not.toHaveBeenCalled();
  });

  it('says whether this person can include tools', () => {
    expect(usar().podeIncluir.value).toBe(true);
    ligada.construtor = ref(false);
    expect(usar().podeIncluir.value).toBe(false);
  });

  it('removing every tool still records each removal on "Start"', async () => {
    const prontas = usar(['fipe', 'cep']);
    prontas.tirar('fipe');
    prontas.tirar('cep');

    expect(await prontas.incluirTodas()).toEqual([]);
    expect(api.dispensar).toHaveBeenCalledWith(7, 'fipe');
    expect(api.dispensar).toHaveBeenCalledWith(7, 'cep');
    expect(vitrine.incluir).not.toHaveBeenCalled();
  });

  it('records the removals even when the showcase cannot be read', async () => {
    vitrine.carregar.mockImplementation(async () => {
      vitrine.erro.value = 'REDE';
    });
    const prontas = usar();
    prontas.tirar('cep');

    expect(await prontas.incluirTodas()).toEqual(['fipe', 'cpf']);
    expect(api.dispensar).toHaveBeenCalledWith(7, 'cep');
  });

  it('does not show again what the agent already has', () => {
    vitrine.tem.mockImplementation((_, id) => id === 'fipe');

    expect(usar().visiveis.value).toEqual(['cep', 'cpf']);
  });

  it('reports what did not go in: a failed include and a source the account no longer releases', async () => {
    vitrine.fontes = ref(['fipe', 'cep']);
    vitrine.incluir.mockImplementation(({ fonte }) =>
      fonte === 'cep' ? Promise.reject(new Error('GERAL')) : Promise.resolve()
    );
    const prontas = usar();

    expect(await prontas.incluirTodas()).toEqual(['cpf', 'cep']);
    expect(vitrine.incluir).toHaveBeenCalledTimes(2);
  });

  it('when the showcase cannot be read, nothing silent: every shown tool is reported', async () => {
    vitrine.carregar.mockImplementation(async () => {
      vitrine.erro.value = 'REDE';
    });
    const prontas = usar();

    expect(await prontas.incluirTodas()).toEqual(['fipe', 'cep', 'cpf']);
    expect(vitrine.incluir).not.toHaveBeenCalled();
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

  it('"Add these too" joins the "also fits" tools to the list, and the "Start" includes them', async () => {
    vitrine.fontes = ref(['fipe', 'cep', 'cpf', 'cnpj', 'feriados']);
    const prontas = usar(['fipe', 'cep'], ['cnpj', 'fipe', 'feriados']);

    expect(prontas.combinaTambem.value).toEqual(['cnpj', 'feriados']);
    prontas.incluirTambem();

    expect(prontas.visiveis.value).toEqual(['fipe', 'cep', 'cnpj', 'feriados']);
    expect(prontas.combinaTambem.value).toEqual([]);
    expect(await prontas.incluirTodas()).toEqual([]);
    expect(vitrine.incluir).toHaveBeenCalledTimes(4);
  });

  it('"also fits" leaves out what the agent already has and what the person removed', () => {
    vitrine.tem.mockImplementation((_, id) => id === 'cnpj');
    const prontas = usar(['fipe'], ['cnpj', 'feriados']);
    prontas.incluirTambem();
    prontas.tirar('feriados');

    expect(prontas.visiveis.value).toEqual(['fipe']);
    expect(prontas.combinaTambem.value).toEqual([]);
  });

  it('without the tools key: no "also fits"', () => {
    ligada.construtor = ref(false);

    expect(usar(['fipe'], ['cnpj']).combinaTambem.value).toEqual([]);
  });

  it('without the Construtor flag on the account: nothing at all', () => {
    ligada.construtor = ref(false);
    ligada.naConta = ref(false);
    const prontas = usar();

    expect(prontas.escolhidas.value).toEqual([]);
    expect(prontas.semPermissao.value).toBe(false);
  });
});

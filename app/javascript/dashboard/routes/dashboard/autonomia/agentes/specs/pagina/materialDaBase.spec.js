import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import {
  ESTADO_MATERIAL,
  estadoDoMaterial,
  progressoDoMaterial,
} from '../../utils/estadoDoMaterial';
import { criarMaterialFalso } from '../../prototipo/materialFalso';
import {
  RELEITURA_MS,
  useMaterialDoAgente,
} from '../../composables/useMaterialDoAgente';
import UmProblemaPorVez from '../../components/pagina/UmProblemaPorVez.vue';
import TesteDoAgente from '../../components/pagina/TesteDoAgente.vue';

// #1426/#1427 (mockup dos temas 4 e 5): "Pronto" só depois da revisão, reprovação sem recarregar,
// progresso do material grande, autoteste 8 + 2, um problema por vez e o clipe no Testar.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: () => computed(() => ({ name: 'Lanches da Bia' })),
  };
});

const revisado = status => ({ status, reviewed_at: '2026-10-19T12:00:00Z' });

describe('estadoDoMaterial', () => {
  it('não chama de Pronto o que foi lido mas ainda não revisado', () => {
    expect(
      estadoDoMaterial({ status: 'ready', review: { status: 'needs_review' } })
    ).toBe(ESTADO_MATERIAL.REVISANDO);
  });

  it('pronto só com a revisão aprovada e sem problema aberto', () => {
    const fonte = { id: 1, status: 'ready', review: revisado('accepted') };
    expect(estadoDoMaterial(fonte)).toBe(ESTADO_MATERIAL.PRONTO);
    expect(estadoDoMaterial(fonte, [{ fontes: [1] }])).toBe(
      ESTADO_MATERIAL.ATENCAO
    );
  });

  it('reprovado, lendo e falha', () => {
    expect(
      estadoDoMaterial({ status: 'ready', review: revisado('needs_resend') })
    ).toBe(ESTADO_MATERIAL.ATENCAO);
    expect(estadoDoMaterial({ status: 'processing' })).toBe(
      ESTADO_MATERIAL.LENDO
    );
    expect(estadoDoMaterial({ status: 'failed' })).toBe(ESTADO_MATERIAL.FALHA);
  });

  it('progresso por página ou lote, sem passar do total', () => {
    expect(
      progressoDoMaterial({ progresso: { feito: 90, total: 80 } })
    ).toEqual({
      feito: 80,
      total: 80,
      unidade: 'pagina',
    });
    expect(
      progressoDoMaterial({
        progresso: { feito: 2, total: 9, unidade: 'lote' },
      }).unidade
    ).toBe('lote');
    expect(progressoDoMaterial({})).toBeNull();
  });
});

describe('adaptador falso do material', () => {
  const comRelogio = () => {
    const agora = { ms: 0 };
    const fonte = criarMaterialFalso({ relogio: () => agora.ms, espera: 0 });
    return { agora, fonte };
  };
  const achar = (retrato, id) => retrato.fontes.find(item => item.id === id);

  it('a reprovação chega numa releitura, depois de "lido"', async () => {
    const { agora, fonte } = comRelogio();
    let retrato = await fonte.ler();
    expect(estadoDoMaterial(achar(retrato, 6), retrato.problemas)).toBe(
      'revisando'
    );
    agora.ms = 5000;
    retrato = await fonte.ler();
    expect(estadoDoMaterial(achar(retrato, 6), retrato.problemas)).toBe(
      'atencao'
    );
    expect(retrato.problemas.map(p => p.tipo)).toContain('sem_cabecalho');
  });

  it('cobre as conferências pedidas: vazio, foto ilegível, duplicado, contradição e autoteste', async () => {
    const { fonte } = comRelogio();
    const { problemas } = await fonte.ler();
    expect(problemas.map(p => p.tipo)).toEqual([
      'vazio',
      'ocr',
      'duplicado',
      'contradicao',
      'autoteste',
    ]);
  });

  it('o catálogo grande mostra o progresso por página e, revisado, refaz o autoteste', async () => {
    const { agora, fonte } = comRelogio();
    agora.ms = 1200;
    let retrato = await fonte.ler();
    expect(achar(retrato, 7).progresso).toEqual({
      feito: 8,
      total: 80,
      unidade: 'pagina',
    });
    agora.ms = 11 * 1200 + 4000;
    retrato = await fonte.ler();
    expect(estadoDoMaterial(achar(retrato, 7), retrato.problemas)).toBe(
      'pronto'
    );
    expect(retrato.autoteste).toMatchObject({
      estado: 'rodando',
      quando: 'base_mudou',
    });
    agora.ms += 10 * 700;
    retrato = await fonte.ler();
    expect(retrato.autoteste).toMatchObject({
      estado: 'pronto',
      total: 10,
      doMaterial: 8,
      deFora: 2,
      certasDoMaterial: 7,
      certasDeFora: 2,
    });
    expect(retrato.autoteste.resultados).toHaveLength(10);
  });

  it('ficar com um só tira o duplicado da base', async () => {
    const { fonte } = comRelogio();
    const retrato = await fonte.resolver('duplicado-4-5', 'um_so');
    expect(achar(retrato, 5)).toBeUndefined();
    expect(
      retrato.problemas.find(p => p.id === 'duplicado-4-5')
    ).toBeUndefined();
  });

  it('o Testar responde sobre a foto só quando ela vai', async () => {
    const { fonte } = comRelogio();
    const comFoto = await fonte.testar({
      message: 'Olha',
      images: ['data:image/png;base64,AA=='],
    });
    const semFoto = await fonte.testar({ message: 'Abre sábado?' });
    expect(comFoto.reply).not.toBe(semFoto.reply);
  });
});

describe('useMaterialDoAgente', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('relê sozinho enquanto algo está em andamento e para quando nada está', async () => {
    let revisando = true;
    const fonte = {
      ler: vi.fn(async () => ({
        fontes: [
          {
            id: 1,
            status: 'ready',
            review: revisando ? { status: null } : revisado('accepted'),
          },
        ],
        problemas: [],
        autoteste: null,
      })),
    };
    const material = useMaterialDoAgente({ fonte });
    await material.ler();
    expect(material.emAndamento.value).toBe(true);
    revisando = false;
    await vi.advanceTimersByTimeAsync(RELEITURA_MS);
    expect(fonte.ler).toHaveBeenCalledTimes(2);
    expect(material.estadoDe(material.fontes.value[0])).toBe('pronto');
    await vi.advanceTimersByTimeAsync(RELEITURA_MS * 3);
    expect(fonte.ler).toHaveBeenCalledTimes(2);
    material.parar();
  });
});

describe('UmProblemaPorVez', () => {
  const problemas = [
    { id: 'a', tipo: 'vazio', fontes: [8], nome: 'ficha.pdf' },
    {
      id: 'b',
      tipo: 'contradicao',
      fontes: [2, 4],
      assunto: 'horário',
      opcoes: [
        { valor: 2, onde: 'site', diz: '9h às 13h' },
        { valor: 4, onde: 'horarios.pdf', diz: '9h às 12h' },
      ],
    },
  ];
  const montar = () =>
    mount(UmProblemaPorVez, {
      props: { problemas, nome: 'Bia', podeGerenciar: true },
    });

  it('mostra um problema de cada vez e pular passa para o próximo', async () => {
    const wrapper = montar();
    expect(wrapper.findAll('[data-um-problema]')).toHaveLength(1);
    expect(wrapper.find('[data-um-problema]').attributes('data-tipo')).toBe(
      'vazio'
    );
    await wrapper.find('[data-pular]').trigger('click');
    expect(wrapper.find('[data-um-problema]').attributes('data-tipo')).toBe(
      'contradicao'
    );
  });

  it('na contradição, "Usar este" espera a escolha e manda o valor', async () => {
    const wrapper = montar();
    await wrapper.find('[data-pular]').trigger('click');
    await wrapper.find('[data-acao="usar"]').trigger('click');
    expect(wrapper.emitted('resolver')).toBeUndefined();
    await wrapper.findAll('[role="radio"]')[1].trigger('click');
    await wrapper.find('[data-acao="usar"]').trigger('click');
    expect(wrapper.emitted('resolver')[0]).toEqual(['b', 4]);
  });

  it('vazio: mandar outro aponta o arquivo', async () => {
    const wrapper = montar();
    await wrapper.find('[data-acao="mandar-outro"]').trigger('click');
    expect(wrapper.emitted('mandarOutro')[0]).toEqual([8]);
  });

  it('quem só vê não tem as ações', () => {
    const wrapper = mount(UmProblemaPorVez, {
      props: { problemas, nome: 'Bia', podeGerenciar: false },
    });
    expect(wrapper.find('[data-acoes]').exists()).toBe(false);
  });
});

describe('TesteDoAgente com o clipe (#1427)', () => {
  const montar = (props = {}) => {
    const teste = {
      mensagens: ref([]),
      digitando: ref(false),
      aviso: ref(null),
      ultima: ref(null),
      atualizado: ref(false),
      enviar: vi.fn(),
      limpar: vi.fn(),
      tentarDeNovo: vi.fn(),
    };
    const wrapper = mount(TesteDoAgente, {
      props: { teste, nome: 'Bia', comClipe: true, ...props },
    });
    return { wrapper, teste };
  };
  const anexar = async (wrapper, arquivos) => {
    const seletor = wrapper.find('input[type="file"]');
    Object.defineProperty(seletor.element, 'files', {
      value: arquivos,
      configurable: true,
    });
    await seletor.trigger('change');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
  };

  beforeAll(() => {
    globalThis.URL.createObjectURL = vi.fn(() => 'blob:x');
    globalThis.URL.revokeObjectURL = vi.fn();
  });

  it('sem o clipe, o Testar é o de hoje', () => {
    const { wrapper } = montar({ comClipe: false });
    expect(wrapper.find('[data-anexar]').exists()).toBe(false);
  });

  it('foto vai ao agente só no teste, sem perguntar se aprende', async () => {
    const { wrapper, teste } = montar();
    const foto = new File(['x'], 'lanche.jpg', { type: 'image/jpeg' });
    await anexar(wrapper, [foto]);
    expect(teste.enviar).toHaveBeenCalledWith('', [foto]);
    expect(wrapper.find('[data-aprender]').exists()).toBe(false);
  });

  it('arquivo pergunta "Quer que aprenda?" e o sim manda para a base', async () => {
    const { wrapper, teste } = montar();
    const pdf = new File(['x'], 'cardapio.pdf', { type: 'application/pdf' });
    await anexar(wrapper, [pdf]);
    expect(teste.enviar).not.toHaveBeenCalled();
    expect(wrapper.find('[data-aprender]').exists()).toBe(true);
    await wrapper.find('[data-aprender-sim]').trigger('click');
    expect(wrapper.emitted('aprender')[0]).toEqual([pdf]);
    expect(wrapper.find('[data-aprender]').exists()).toBe(false);
    expect(wrapper.find('[data-ver-material]').exists()).toBe(true);
  });

  it('o não descarta o arquivo, sem mandar para a base', async () => {
    const { wrapper } = montar();
    await anexar(wrapper, [
      new File(['x'], 'a.pdf', { type: 'application/pdf' }),
    ]);
    await wrapper.find('[data-aprender-nao]').trigger('click');
    expect(wrapper.emitted('aprender')).toBeUndefined();
    expect(wrapper.find('[data-ver-material]').exists()).toBe(false);
  });
});

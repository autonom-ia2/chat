import { nextTick, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import UmProblemaPorVez from '../../components/pagina/UmProblemaPorVez.vue';
import {
  RELEITURA_DEPOIS_DA_BASE_MS,
  useConferenciasDoMaterial,
} from '../../composables/useConferenciasDoMaterial';
import {
  ESTADO_MATERIAL,
  estadoDoMaterial,
  precisaDeVoce,
} from '../../utils/estadoDoMaterial';

// #1426 (tema 4b, mockup aprovado em 19/10) — "um problema por vez" (sempre com "Pular por agora", nada trava, a pessoa
// decide) e a releitura depois que a base muda. #3200: o teste automático do material saiu.
withFullI18n('pt_BR');

const no = (wrapper, seletor) => wrapper.find(seletor);

const montarProblemas = (problemas, props = {}) =>
  mount(UmProblemaPorVez, {
    props: { problemas, nome: 'Bia', podeGerenciar: true, ...props },
  });

const VAZIO = {
  id: 'vazio-8',
  tipo: 'vazio',
  fontes: [8],
  nome: 'ficha.pdf',
};
const CONTRADICAO = {
  id: 'contradicao-a',
  tipo: 'contradicao',
  fontes: [2, 4],
  assunto: 'horário de sábado',
  opcoes: [
    { valor: 2, onde: 'site', diz: 'das 9h às 13h' },
    { valor: 4, onde: 'horarios.pdf', diz: 'das 9h às 12h' },
  ],
};

describe('UmProblemaPorVez', () => {
  it('mostra um cartão por vez, com a contagem e "Pular por agora" sempre', async () => {
    const wrapper = montarProblemas([VAZIO, CONTRADICAO]);

    expect(no(wrapper, '[data-contagem]').text()).toBe(
      'Precisa de você · 1 de 2'
    );
    expect(no(wrapper, '[data-titulo]').text()).toBe('ficha.pdf está vazio');

    await no(wrapper, '[data-pular]').trigger('click');
    expect(no(wrapper, '[data-contagem]').text()).toBe(
      'Precisa de você · 2 de 2'
    );
    expect(no(wrapper, '[data-tipo]').attributes('data-tipo')).toBe(
      'contradicao'
    );
  });

  it('com um problema só, "Pular por agora" também está lá e tira o cartão da frente', async () => {
    const wrapper = montarProblemas([VAZIO]);

    await no(wrapper, '[data-pular]').trigger('click');

    expect(no(wrapper, '[data-um-problema]').exists()).toBe(false);
  });

  it('contradição: a pessoa escolhe qual vale; sem escolha, "Usar este" fica inativo', async () => {
    const wrapper = montarProblemas([CONTRADICAO]);

    expect(no(wrapper, '[data-titulo]').text()).toBe(
      'Dois materiais dizem coisas diferentes sobre o horário de sábado'
    );
    const usar = no(wrapper, '[data-acao="usar"]');
    await usar.trigger('click');
    expect(wrapper.emitted('resolver')).toBeUndefined();

    await wrapper.findAll('[role="radio"]')[1].trigger('click');
    await no(wrapper, '[data-acao="usar"]').trigger('click');
    expect(wrapper.emitted('resolver')).toEqual([['contradicao-a', 4]]);
  });

  it('duplicado: ficar com um só (pelo Tirar, com confirmação) ou manter os dois', async () => {
    const wrapper = montarProblemas([
      {
        id: 'duplicado-4-5',
        tipo: 'duplicado',
        fontes: [4, 5],
        nome: 'horarios.pdf',
        outro: 'horarios (1).pdf',
        manter: 4,
        tirar: 5,
      },
    ]);

    expect(no(wrapper, '[data-acao="um-so"]').text()).toBe(
      'Ficar só com horarios.pdf'
    );
    await no(wrapper, '[data-acao="um-so"]').trigger('click');
    expect(wrapper.emitted('tirar')).toEqual([[5]]);
    expect(wrapper.emitted('resolver')).toBeUndefined();
    await no(wrapper, '[data-acao="os-dois"]').trigger('click');
    expect(wrapper.emitted('resolver')).toEqual([['duplicado-4-5', 'os_dois']]);
  });

  it('leitura ruim: foto e arquivo têm texto próprio; mandar outro troca o material', async () => {
    const foto = montarProblemas([
      { id: 'ocr-3', tipo: 'ocr', fontes: [3], nome: 'tabela.jpg', foto: true },
    ]);
    expect(no(foto, '[data-titulo]').text()).toBe(
      'Não deu para ler a foto tabela.jpg'
    );
    await no(foto, '[data-acao="mandar-outro"]').trigger('click');
    expect(foto.emitted('mandarOutro')).toEqual([[3]]);

    const arquivo = montarProblemas([
      { id: 'ocr-9', tipo: 'ocr', fontes: [9], nome: 'escaneado.pdf' },
    ]);
    expect(no(arquivo, '[data-titulo]').text()).toBe(
      'Não deu para ler escaneado.pdf'
    );
    expect(no(arquivo, '[data-acao="mandar-outro"]').text()).toBe(
      'Mandar outro'
    );
  });

  it('tabela sem cabeçalho mostra a primeira linha', () => {
    const wrapper = montarProblemas([
      {
        id: 'sem_cabecalho-6',
        tipo: 'sem_cabecalho',
        fontes: [6],
        nome: 'bebidas.xlsx',
        amostra: ['Coca 350', '6,00'],
      },
    ]);

    expect(wrapper.findAll('[data-amostra] li').map(li => li.text())).toEqual([
      'Coca 350',
      '6,00',
    ]);
  });

  // #1426 (t4e): no material grande a tabela sem cabeçalho é só aviso; o material continua em uso.
  it('aviso do material grande diz que o agente já usa o material', () => {
    const tabela = {
      id: 'sem_cabecalho-6',
      tipo: 'sem_cabecalho',
      fontes: [6],
      nome: 'manual.pdf',
      amostra: ['Cláusula 63'],
    };

    expect(no(montarProblemas([tabela]), '[data-continua]').text()).toBe(
      'Bia continua atendendo com o resto do material.'
    );
    expect(
      no(
        montarProblemas([{ ...tabela, aviso: true }]),
        '[data-continua]'
      ).text()
    ).toBe(
      'Bia já usa este material; o aviso só ajuda a deixar a tabela mais clara.'
    );
  });

  it('páginas de fora: quantas foram lidas, do total, de qual arquivo e por quê, sem código', async () => {
    const wrapper = montarProblemas([
      {
        id: 'paginas-7',
        tipo: 'paginas_de_fora',
        fontes: [7],
        nome: 'catalogo.pdf',
        total: 40,
        lidas: 27,
        motivos: ['limite', 'grande', 'falha'],
      },
    ]);

    expect(no(wrapper, '[data-titulo]').text()).toBe(
      'Li 27 das 40 páginas de catalogo.pdf'
    );
    const texto = no(wrapper, '[data-texto]').text();
    expect(texto).toBe(
      'Bia usa o que foi lido. O resto ficou de fora porque o arquivo passa do número de páginas que dá para ler de ' +
        'uma vez, algumas páginas são grandes demais para ler e algumas páginas não puderam ser lidas.'
    );
    ['ocr', 'teto', 'alem_do_teto'].forEach(codigo =>
      expect(texto).not.toContain(codigo)
    );
    await no(wrapper, '[data-acao="mandar-novo"]').trigger('click');
    expect(wrapper.emitted('mandarNovo')).toHaveLength(1);
  });

  it('páginas de fora sem o total conhecido falam sem números', () => {
    const wrapper = montarProblemas([
      {
        id: 'paginas-7',
        tipo: 'paginas_de_fora',
        fontes: [7],
        nome: 'antigo.pdf',
        motivos: ['tempo'],
      },
    ]);

    expect(no(wrapper, '[data-titulo]').text()).toBe(
      'Parte de antigo.pdf ficou de fora'
    );
    expect(no(wrapper, '[data-texto]').text()).toContain(
      'a leitura levou mais tempo do que o permitido'
    );
  });

  it('quem só vê lê o cartão, sem as ações', () => {
    const wrapper = montarProblemas([CONTRADICAO], { podeGerenciar: false });

    expect(no(wrapper, '[data-acoes]').exists()).toBe(false);
    expect(wrapper.find('[role="radiogroup"]').exists()).toBe(false);
  });
});

describe('useConferenciasDoMaterial', () => {
  const resposta = problemas => ({ data: { problemas } });

  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('lê os problemas, sem se reler sozinho', async () => {
    const api = { get: vi.fn().mockResolvedValue(resposta([VAZIO])) };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    await conferencias.ler();
    expect(conferencias.problemas.value).toEqual([VAZIO]);
    expect(conferencias.lido.value).toBe(true);

    await vi.advanceTimersByTimeAsync(RELEITURA_DEPOIS_DA_BASE_MS * 2);
    expect(api.get).toHaveBeenCalledTimes(1);
  });

  it('resolver vai à API e aplica a resposta', async () => {
    const api = { resolver: vi.fn().mockResolvedValue(resposta([VAZIO])) };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    await conferencias.resolver('contradicao-a', 4);

    expect(api.resolver).toHaveBeenCalledWith(7, 'contradicao-a', 4);
    expect(conferencias.problemas.value).toEqual([VAZIO]);
  });

  it('a base mudou: lê agora e mais uma vez depois da espera das conferências (uma só, mesmo em rajada)', async () => {
    const api = { get: vi.fn().mockResolvedValue(resposta([])) };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    conferencias.lerDepoisDaMudanca();
    conferencias.lerDepoisDaMudanca();
    await flushPromises();
    expect(api.get).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(RELEITURA_DEPOIS_DA_BASE_MS);
    expect(api.get).toHaveBeenCalledTimes(3);

    conferencias.lerDepoisDaMudanca();
    conferencias.parar();
    await vi.advanceTimersByTimeAsync(RELEITURA_DEPOIS_DA_BASE_MS);
    expect(api.get).toHaveBeenCalledTimes(4);
  });

  it('falha na leitura: marca o erro sem apagar o que já estava na tela', async () => {
    const api = {
      get: vi
        .fn()
        .mockResolvedValueOnce(resposta([VAZIO]))
        .mockRejectedValueOnce(new Error('rede')),
    };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    await conferencias.ler();
    await conferencias.ler();

    expect(conferencias.erro.value).toBe(true);
    expect(conferencias.problemas.value).toEqual([VAZIO]);
  });
});

describe('estadoDoMaterial com os problemas das conferências', () => {
  const fonte = {
    id: 4,
    status: 'ready',
    review: { status: 'accepted', reviewed_at: '2026-10-19T12:00:00Z' },
  };

  // Achado na conferência visual: a linha dizia "não usa este material até você mandar outro" num material em uso.
  it('duplicado, contradição e páginas de fora não mudam a linha: o material segue em uso', () => {
    expect(estadoDoMaterial(fonte)).toBe(ESTADO_MATERIAL.PRONTO);
    expect(precisaDeVoce(fonte)).toBe(false);
    expect(
      estadoDoMaterial({
        ...fonte,
        review: { ...fonte.review, status: 'needs_resend' },
      })
    ).toBe(ESTADO_MATERIAL.ATENCAO);
  });
});

// Guarda contra regressão do contrato do componente: o cartão não depende de nada além dos dados do problema.
it('o cartão aceita a lista mudando por baixo (resolvido em outro lugar)', async () => {
  const lista = ref([VAZIO, CONTRADICAO]);
  const wrapper = montarProblemas(lista.value);

  await wrapper.setProps({ problemas: [CONTRADICAO] });
  await nextTick();
  await flushPromises();

  expect(no(wrapper, '[data-tipo]').attributes('data-tipo')).toBe(
    'contradicao'
  );
});

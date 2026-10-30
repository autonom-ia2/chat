import { nextTick, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import UmProblemaPorVez from '../../components/pagina/UmProblemaPorVez.vue';
import AutotesteDoMaterial from '../../components/pagina/AutotesteDoMaterial.vue';
import {
  RELEITURA_DEPOIS_DA_BASE_MS,
  RELEITURA_DO_AUTOTESTE_MS,
  useConferenciasDoMaterial,
} from '../../composables/useConferenciasDoMaterial';
import {
  ESTADO_MATERIAL,
  estadoDoMaterial,
  precisaDeVoce,
} from '../../utils/estadoDoMaterial';

// #1426 (tema 4b, mockup aprovado em 19/10) — "um problema por vez" (sempre com "Pular por agora", nada trava, a pessoa
// decide), o autoteste 8 + 2 e a releitura que traz o resultado sem recarregar.
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

  it('autoteste: resposta errada com o que o material diz; corrigir leva pergunta e resposta', async () => {
    const wrapper = montarProblemas([
      {
        id: 'autoteste-r-0',
        tipo: 'autoteste',
        fontes: [],
        pergunta: 'Entregam no Centro?',
        resposta: 'Não entregamos.',
        esperado: 'Entregamos no Centro.',
        onde: 'cardapio.pdf',
      },
    ]);

    expect(no(wrapper, '[data-autoteste]').text()).toContain(
      'cardapio.pdf diz: "Entregamos no Centro."'
    );
    await no(wrapper, '[data-acao="corrigir"]').trigger('click');
    expect(wrapper.emitted('corrigir')).toEqual([
      [{ pergunta: 'Entregam no Centro?', resposta: 'Não entregamos.' }],
    ]);
    await no(wrapper, '[data-acao="certa"]').trigger('click');
    expect(wrapper.emitted('resolver')).toEqual([['autoteste-r-0', 'certa']]);
  });

  // #1426 (t4d): "De onde o agente tirou" — os trechos usados na resposta, com o arquivo e as páginas.
  it('autoteste: mostra de onde o agente tirou a resposta, ou que não usou trecho nenhum', () => {
    const ERRADA = {
      id: 'autoteste-r-0',
      tipo: 'autoteste',
      fontes: [],
      pergunta: 'Tem carro reserva?',
      resposta: 'Não tem.',
    };
    const comTrechos = montarProblemas([
      {
        ...ERRADA,
        trechos: [
          {
            onde: 'condicoes.pdf',
            paginas: [226, 250],
            texto: 'Carro reserva por 7 dias.',
          },
          { onde: 'tabela.xlsx', texto: 'Plano básico: sem carro reserva.' },
        ],
      },
    ]);

    expect(comTrechos.text()).toContain('De onde Bia tirou');
    expect(comTrechos.findAll('[data-onde]').map(o => o.text())).toEqual([
      'condicoes.pdf, páginas 226 a 250',
      'tabela.xlsx',
    ]);
    expect(no(comTrechos, '[data-trechos]').text()).toContain(
      'Carro reserva por 7 dias.'
    );

    const semTrecho = montarProblemas([{ ...ERRADA, trechos: [] }]);
    expect(no(semTrecho, '[data-sem-trecho]').text()).toBe(
      'Bia não usou nenhum trecho do material para responder.'
    );

    const rodadaAntiga = montarProblemas([ERRADA]);
    expect(rodadaAntiga.text()).not.toContain('De onde Bia tirou');
  });

  it('autoteste de fora: a resposta inventada vira cartão com as mesmas saídas', () => {
    const wrapper = montarProblemas([
      {
        id: 'autoteste-r-9',
        tipo: 'autoteste_fora',
        fontes: [],
        pergunta: 'Vende bolo?',
        resposta: 'Sim, R$ 90.',
      },
    ]);

    expect(no(wrapper, '[data-titulo]').text()).toBe(
      'No teste automático, Bia inventou uma resposta'
    );
    expect(no(wrapper, '[data-acao="corrigir"]').exists()).toBe(true);
    expect(no(wrapper, '[data-acao="certa"]').exists()).toBe(true);
  });

  it('quem só vê lê o cartão, sem as ações', () => {
    const wrapper = montarProblemas([CONTRADICAO], { podeGerenciar: false });

    expect(no(wrapper, '[data-acoes]').exists()).toBe(false);
    expect(wrapper.find('[role="radiogroup"]').exists()).toBe(false);
  });
});

const autoteste = extra => ({
  estado: 'pronto',
  quando: 'pedido',
  feitas: 10,
  total: 10,
  doMaterial: 8,
  deFora: 2,
  certasDoMaterial: 7,
  certasDeFora: 2,
  resultados: [{ pergunta: 'Abre sábado?', origem: 'material', ok: true }],
  ...extra,
});

describe('AutotesteDoMaterial', () => {
  const montar = (dados, props = {}) =>
    mount(AutotesteDoMaterial, {
      props: { autoteste: dados, nome: 'Bia', podeGerenciar: true, ...props },
    });

  it('pronto: quantas acertou, em palavras, e a recusa nas de fora', () => {
    const wrapper = montar(autoteste());

    expect(no(wrapper, '[data-resultado]').text()).toBe(
      'Bia acertou 7 de 8 perguntas sobre o seu material.'
    );
    expect(no(wrapper, '[data-fora]').text()).toContain(
      'disse que não sabia e passou para a equipe'
    );
    expect(no(wrapper, '[data-testar-de-novo]').text()).toBe('Testar de novo');
    expect(no(wrapper, '[data-aviso-amostra]').text()).toBe(
      'O teste é uma amostra; confira as respostas.'
    );
  });

  it('singular quando há uma pergunta só: sem "Nas 1 perguntas"', () => {
    const wrapper = montar(autoteste({ deFora: 1, certasDeFora: 1 }));

    expect(no(wrapper, '[data-fora]').text()).toBe(
      'Na pergunta que não está no material, Bia disse que não sabia e passou para a equipe.'
    );
    expect(no(wrapper, '[data-perguntas] summary').text()).toBe(
      'Ver a pergunta'
    );
  });

  it('inventou numa de fora: aviso âmbar', () => {
    const wrapper = montar(autoteste({ certasDeFora: 1 }));

    expect(no(wrapper, '[data-fora]').text()).toBe(
      'Em perguntas que não estão no material, Bia inventou resposta.'
    );
  });

  it('rodando: progresso, sem botão', () => {
    const wrapper = montar(
      autoteste({ estado: 'rodando', feitas: 3, quando: 'base_mudou' })
    );

    expect(no(wrapper, '[data-rodando]').text()).toBe(
      'Testando Bia com 10 perguntas… 3 de 10'
    );
    expect(wrapper.text()).toContain(
      'O material mudou, então Bia está sendo testado de novo.'
    );
    expect(no(wrapper, '[data-testar-de-novo]').exists()).toBe(false);
  });

  it('parado (teto ou falha): "Não consegui terminar o teste agora" e tentar de novo', async () => {
    const wrapper = montar(autoteste({ estado: 'parado' }));

    expect(no(wrapper, '[data-parado]').text()).toBe(
      'Não consegui terminar o teste agora.'
    );
    expect(no(wrapper, '[data-testar-de-novo]').text()).toBe('Tentar de novo');
    await no(wrapper, '[data-testar-de-novo]').trigger('click');
    expect(wrapper.emitted('testarDeNovo')).toHaveLength(1);
  });

  it('nunca rodou: convida a testar', () => {
    const wrapper = montar(
      autoteste({ estado: 'nunca', resultados: [], doMaterial: 0, deFora: 0 })
    );

    expect(no(wrapper, '[data-nunca]').text()).toBe(
      'Bia ainda não foi testado com o seu material.'
    );
    expect(no(wrapper, '[data-testar-de-novo]').text()).toBe('Testar agora');
    expect(no(wrapper, '[data-perguntas]').exists()).toBe(false);
    expect(no(wrapper, '[data-aviso-amostra]').exists()).toBe(false);
  });
});

describe('useConferenciasDoMaterial', () => {
  const resposta = (problemas, salvo) => ({
    data: { problemas, autoteste: salvo },
  });

  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('lê problemas e autoteste e se relê enquanto o autoteste roda; para quando termina', async () => {
    const api = {
      get: vi
        .fn()
        .mockResolvedValueOnce(
          resposta([], { estado: 'rodando', feitas: 2, total: 10 })
        )
        .mockResolvedValueOnce(
          resposta([VAZIO], {
            estado: 'pronto',
            do_material: 8,
            de_fora: 2,
            certas_do_material: 8,
            certas_de_fora: 2,
            resultados: [],
          })
        ),
    };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    await conferencias.ler();
    expect(conferencias.autoteste.value).toMatchObject({
      estado: 'rodando',
      feitas: 2,
    });

    await vi.advanceTimersByTimeAsync(RELEITURA_DO_AUTOTESTE_MS);
    expect(api.get).toHaveBeenCalledTimes(2);
    expect(conferencias.problemas.value).toEqual([VAZIO]);
    expect(conferencias.autoteste.value).toMatchObject({
      estado: 'pronto',
      doMaterial: 8,
      certasDeFora: 2,
    });

    await vi.advanceTimersByTimeAsync(RELEITURA_DO_AUTOTESTE_MS * 3);
    expect(api.get).toHaveBeenCalledTimes(2);
  });

  it('resolver e pedir o autoteste vão à API e aplicam a resposta', async () => {
    const api = {
      resolver: vi.fn().mockResolvedValue(resposta([], null)),
      pedirAutoteste: vi
        .fn()
        .mockResolvedValue(resposta([], { estado: 'rodando' })),
      get: vi.fn().mockResolvedValue(resposta([], { estado: 'pronto' })),
    };
    const conferencias = useConferenciasDoMaterial({ agentId: () => 7, api });

    await conferencias.resolver('contradicao-a', 4);
    expect(api.resolver).toHaveBeenCalledWith(7, 'contradicao-a', 4);

    await conferencias.pedirAutoteste();
    expect(api.pedirAutoteste).toHaveBeenCalledWith(7);
    expect(conferencias.autoteste.value.estado).toBe('rodando');
    conferencias.parar();
  });

  it('a base mudou: lê agora e mais uma vez depois da espera das conferências (uma só, mesmo em rajada)', async () => {
    const api = { get: vi.fn().mockResolvedValue(resposta([], null)) };
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
        .mockResolvedValueOnce(resposta([VAZIO], null))
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

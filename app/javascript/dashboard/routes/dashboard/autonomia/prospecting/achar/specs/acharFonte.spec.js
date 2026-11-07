import * as demoDados from '../demo/acharDemo';
import { criarFonte, demoPedido, montarPedido } from '../utils/acharFonte';
import { empresaDoLead } from '../utils/acharLead';
import { naoVao } from '../utils/acharConfiraEstados';
import { permissoesDoPapel, papelValido } from '../utils/acharPapeis';

const carregarDemo = () => Promise.resolve(demoDados);

const apiFalsa = () => ({
  getSearch: vi.fn().mockResolvedValue({
    data: {
      payload: {
        id: 9,
        query: 'Padarias',
        location_label: 'Taquaral, Campinas, SP',
        results_count: 1,
        crm_count: 0,
        leads: [
          {
            id: 1,
            name: 'Padaria Exemplo',
            category: 'Padaria',
            neighborhood: 'Taquaral',
            priority_score: 62,
            human_insight: 'Nota boa.',
            whatsapp_verification_status: 'verified',
            research: {
              decision_status: 'confirmed',
              decision: { name: 'Ana', role: 'sócia' },
            },
          },
        ],
      },
    },
  }),
  createCrmCards: vi.fn(),
  createSearch: vi.fn(),
});

describe('demoPedido', () => {
  it('lê o estado do endereço só quando a demonstração é permitida', () => {
    expect(demoPedido({ demo: 'confira' }, true)).toBe('confira');
    expect(demoPedido({ demo: 'confira' }, false)).toBeNull();
    expect(demoPedido({}, true)).toBeNull();
    expect(demoPedido({ demo: ['a'] }, true)).toBeNull();
  });
});

describe('papéis da demonstração', () => {
  it('só Ver não busca nem manda; agente não troca o dono', () => {
    expect(permissoesDoPapel('so-ver')).toMatchObject({
      buscar: false,
      funil: false,
      lista: false,
    });
    expect(permissoesDoPapel('agente').trocarDono).toBe(false);
    expect(permissoesDoPapel('gestora').trocarDono).toBe(true);
    expect(papelValido('qualquer')).toBe('dono');
  });
});

describe('fonte da demonstração', () => {
  it('a lista fecha a conta da jornada: 16 que podem ir, 4 de fora, 2 tiradas', async () => {
    const fonte = criarFonte({ demo: 'confira-tirou', carregarDemo });
    const { empresas, tiradas } = await fonte.busca('demo');

    expect(fonte.usaDemo).toBe(true);
    expect(empresas).toHaveLength(demoDados.LIMITE);
    expect(empresas.filter(empresa => !empresa.fora)).toHaveLength(16);
    expect(empresas.filter(empresa => empresa.fora)).toHaveLength(4);
    expect(tiradas).toHaveLength(2);
  });

  it('antes de tirar (chegando, confira) ninguém vem em "Não vai"', async () => {
    const chegando = await criarFonte({
      demo: 'chegando',
      carregarDemo,
    }).busca();
    const confira = await criarFonte({ demo: 'confira', carregarDemo }).busca();
    const folha = await criarFonte({ demo: 'folha', carregarDemo }).busca();

    expect(chegando.tiradas).toEqual([]);
    expect(confira.tiradas).toEqual([]);
    expect(folha.tiradas).toHaveLength(2);
  });

  it('os números da demonstração fecham entre si', () => {
    const { NUMEROS } = demoDados;
    const naoVaoTotal = naoVao(demoDados.empresas(), NUMEROS.tiradas).reduce(
      (soma, item) => soma + item.n,
      0
    );

    expect(NUMEROS.podemIr + NUMEROS.fora).toBe(NUMEROS.achadas);
    expect(NUMEROS.vao + naoVaoTotal).toBe(NUMEROS.achadas);
    expect(NUMEROS.vao).toBe(14);
    expect(NUMEROS.entramNaLista).toBe(12);
    expect(NUMEROS.noFunilDepois).toBe(16);
    expect(demoDados.BUSCAS[0].noFunil).toBe(NUMEROS.noFunilDepois);
  });

  it('mandar para o funil só simula: não chama a API', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({
      demo: 'folha-funil',
      carregarDemo,
      api,
      atraso: 0,
    });
    const progresso = vi.fn();
    const resumo = await fonte.mandarParaFunil({
      ids: [1, 2, 3],
      onProgresso: progresso,
    });

    expect(resumo.created).toEqual([1, 2, 3]);
    expect(api.createCrmCards).not.toHaveBeenCalled();
    expect(progresso).toHaveBeenLastCalledWith(3);
  });

  it('o erro da demonstração vem como falha de cada empresa', async () => {
    const fonte = criarFonte({ demo: 'folha-erro', carregarDemo, atraso: 0 });
    const resumo = await fonte.mandarParaFunil({ ids: [5, 6] });

    expect(resumo.failed).toEqual([5, 6]);
  });

  it('sem a demonstração carregada (produção), usa a API', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ demo: 'confira', carregarDemo: null, api });
    const { busca, empresas } = await fonte.busca(9);

    expect(fonte.usaDemo).toBe(false);
    expect(api.getSearch).toHaveBeenCalledWith(9);
    expect(busca).toMatchObject({ oQue: 'Padarias', achadas: 1 });
    expect(empresas[0]).toMatchObject({
      nome: 'Padaria Exemplo',
      chance: 'boa',
      whatsapp: 'tem',
      dono: { estado: 'confirmado', nome: 'Ana', cargo: 'sócia' },
      fora: null,
    });
  });
});

describe('empresaDoLead', () => {
  it('lead já no funil fica de fora com o nome do funil', () => {
    const empresa = empresaDoLead({
      id: 3,
      name: 'Loja',
      priority_score: 10,
      crm_presence: { pipeline_name: 'Vendas', stage_name: 'Novo' },
    });

    expect(empresa.fora).toEqual({ motivo: 'no_funil', funil: 'Vendas' });
    expect(empresa.chance).toBe('pouca');
  });
});

describe('montarPedido', () => {
  it('manda o modo geral, o raio em metros e os filtros de "Quais empresas?"', () => {
    const pedido = montarPedido({
      oQue: ' Escritórios ',
      lugar: {
        rotulo: 'Centro, Campinas, SP',
        placeId: 'abc',
        latitude: -22.9,
        longitude: -47.06,
      },
      como: { km: 3, n: 20, quais: 'telefone' },
    });

    expect(pedido).toMatchObject({
      query: 'Escritórios',
      radius: 3000,
      requested_limit: 20,
      metadata: {
        score_mode: 'general',
        advanced_filters: { has_phone: 'yes' },
      },
    });
  });
});

describe('papel que o estado da demonstração já diz', () => {
  it('leitura e só Ver valem como só Ver; o &papel= do endereço vale mais', () => {
    expect(papelValido(undefined, 'leitura')).toBe('so-ver');
    expect(papelValido(undefined, 'fila-sem-funil')).toBe('vendedor-sem-funil');
    expect(papelValido('gestora', 'leitura')).toBe('gestora');
    expect(papelValido(undefined, 'confira')).toBe('dono');
  });
});

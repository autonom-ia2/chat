import * as demoDados from '../demo/acharDemo';
import { criarFonte, demoPedido } from '../utils/acharFonte';
import { empresaDoLead } from '../utils/acharLead';
import { atualizarDaBusca, naoVao } from '../utils/acharConfiraEstados';
import {
  permissoesDoPapel,
  papelValido,
  podeApagarBusca,
} from '../utils/acharPapeis';
import { fraseDaPessoa } from '../composables/useGavetaDaLista';
import { soNaDemo } from '../acharRoutes';

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
  adoptOwner: vi.fn().mockResolvedValue({
    data: {
      payload: {
        id: 1,
        name: 'Padaria Exemplo',
        priority_score: 62,
        research: {
          company_status: 'confirmed',
          decision_status: 'confirmed',
          decision: { name: 'Bruno Lima', role: 'Sócio' },
          owners: [
            { name: 'Ana', qualification: 'Sócia-Administradora' },
            { name: 'Bruno Lima', qualification: 'Sócio' },
          ],
        },
      },
      contact_outcome: 'shared_with_other_lead',
      shared_lead_name: 'Padaria Vizinha',
    },
  }),
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

    expect(resumo.created.map(item => item.id)).toEqual([1, 2, 3]);
    expect(api.createCrmCards).not.toHaveBeenCalled();
    expect(progresso).toHaveBeenLastCalledWith(3);
  });

  it('o erro da demonstração vem como falha de cada empresa', async () => {
    const fonte = criarFonte({ demo: 'folha-erro', carregarDemo, atraso: 0 });
    const resumo = await fonte.mandarParaFunil({ ids: [5, 6] });

    expect(resumo.failed.map(item => item.id)).toEqual([5, 6]);
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
  it('lead descartado vira "Não serve", com o motivo do descarte e sem dizer onde', () => {
    const lead = { id: 4, name: 'Loja', priority_score: 50 };

    expect(
      empresaDoLead({
        ...lead,
        status: 'discarded',
        discard_reason: 'Fora do perfil',
      }).fora
    ).toEqual({ motivo: 'nao_serve', razao: 'Fora do perfil' });
    expect(empresaDoLead({ ...lead, status: 'discarded' }).fora).toEqual({
      motivo: 'nao_serve',
      razao: '',
    });
  });

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

describe('papel que o estado da demonstração já diz', () => {
  it('leitura e só Ver valem como só Ver; o &papel= do endereço vale mais', () => {
    expect(papelValido(undefined, 'leitura')).toBe('so-ver');
    expect(papelValido(undefined, 'fila-sem-funil')).toBe('vendedor-sem-funil');
    expect(papelValido('gestora', 'leitura')).toBe('gestora');
    expect(papelValido(undefined, 'confira')).toBe('dono');
  });
});

describe('"Usar esta pessoa" (P1)', () => {
  const empresa = {
    id: 1,
    dono: { estado: 'confirmado', nome: 'Ana', cargo: 'sócia' },
    socios: [{ nome: 'Bruno Lima', cargo: 'Sócio' }],
  };

  it('na API chama adopt_owner com o nome do sócio e traz o desfecho do contato', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ carregarDemo: null, api });
    const resposta = await fonte.usarPessoa({ empresa, nome: 'Bruno Lima' });

    expect(api.adoptOwner).toHaveBeenCalledWith(1, 'Bruno Lima');
    expect(resposta.resultado).toBe('shared_with_other_lead');
    expect(resposta.outra).toBe('Padaria Vizinha');
    expect(resposta.empresa.dono).toEqual({
      estado: 'confirmado',
      nome: 'Bruno Lima',
      cargo: 'Sócio',
    });
    // O dono novo sai da lista; o antigo vira um dos outros sócios.
    expect(resposta.empresa.socios).toEqual([
      { nome: 'Ana', cargo: 'Sócia-Administradora' },
    ]);
  });

  it('na demonstração não chama a API e devolve um dos três desfechos', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ demo: 'gaveta', carregarDemo, api, atraso: 0 });
    const resposta = await fonte.usarPessoa({ empresa, nome: 'Bruno Lima' });

    expect(api.adoptOwner).not.toHaveBeenCalled();
    expect(resposta.resultado).toBe('updated');
    expect(resposta.empresa.dono.nome).toBe('Bruno Lima');
    expect(resposta.empresa.socios.map(socio => socio.nome)).toEqual(['Ana']);
  });

  it('uma frase leiga para cada desfecho', () => {
    const t = (chave, valores) => `${chave} ${JSON.stringify(valores)}`;
    const nome = 'Bruno Lima';

    expect(fraseDaPessoa(t, { resultado: 'updated', nome })).toContain(
      'OUTRAS.FEITO '
    );
    expect(
      fraseDaPessoa(t, {
        resultado: 'shared_with_other_lead',
        nome,
        outra: 'Padaria Vizinha',
      })
    ).toContain('OUTRAS.FEITO_DIVIDIDO {');
    expect(
      fraseDaPessoa(t, { resultado: 'shared_with_other_lead', nome })
    ).toContain('OUTRAS.FEITO_DIVIDIDO_SEM_NOME');
    expect(
      fraseDaPessoa(t, { resultado: 'kept_existing_contact', nome })
    ).toContain('OUTRAS.FEITO_MANTIDO');
  });
});

describe('empresaDoLead lê o lead como o servidor manda', () => {
  it('os outros sócios não incluem o dono atual', () => {
    const empresa = empresaDoLead({
      id: 1,
      name: 'Loja',
      research: {
        company_status: 'confirmed',
        decision_status: 'possible',
        decision: { name: 'Ana  Souza', role: 'Sócia' },
        owners: [
          { name: 'Ana Souza', qualification: 'Sócia' },
          { name: 'Caio Souza', qualification: 'Sócio' },
        ],
      },
    });

    expect(empresa.dono.estado).toBe('possivel');
    expect(empresa.socios).toEqual([{ nome: 'Caio Souza', cargo: 'Sócio' }]);
  });

  it('sem pesquisa, o nome que a IA achou aparece como "Pode ser o dono"', () => {
    const empresa = empresaDoLead({
      id: 2,
      name: 'Loja',
      decision_name: 'Rita',
      decision_role: 'gerente',
      research: { company_status: 'not_researched', owners: [] },
    });

    expect(empresa.dono).toEqual({
      estado: 'possivel',
      nome: 'Rita',
      cargo: 'gerente',
    });
  });

  it('com a pesquisa feita, o nome da IA não volta; pesquisa na fila é "procurando"', () => {
    const semDecisor = empresaDoLead({
      id: 3,
      name: 'Loja',
      decision_name: 'Rita',
      research: { company_status: 'no_result', owners: [] },
    });
    const naFila = empresaDoLead({
      id: 4,
      name: 'Loja',
      research: { company_status: 'queued', owners: [] },
    });

    expect(semDecisor.dono.estado).toBe('nenhum');
    expect(naFila.dono.estado).toBe('procurando');
  });

  it('WhatsApp na fila da verificação é "conferindo"', () => {
    const lead = { id: 5, name: 'Loja' };

    expect(
      empresaDoLead({ ...lead, whatsapp_verification_status: 'queued' })
        .whatsapp
    ).toBe('conferindo');
    expect(
      empresaDoLead({ ...lead, whatsapp_verification_status: 'not_whatsapp' })
        .whatsapp
    ).toBe('sem');
  });
});

describe('"Apagar" só na busca de quem está logado', () => {
  it('com quem fez a busca, compara com o usuário', () => {
    expect(podeApagarBusca({ busca: { feitaPorId: 7 }, usuarioId: 7 })).toBe(
      true
    );
    expect(podeApagarBusca({ busca: { feitaPorId: 8 }, usuarioId: 7 })).toBe(
      false
    );
  });

  it('busca antiga sem dono não tem "Apagar" fora da demonstração', () => {
    const busca = { feitaPorId: null, feitaPor: '' };

    expect(podeApagarBusca({ busca, usuarioId: 7 })).toBe(false);
  });
});

describe('rota da fila "Para chamar" (fase 5)', () => {
  it('fora da demonstração leva para as buscas', () => {
    expect(soNaDemo({ query: {}, params: { accountId: '3' } })).toEqual({
      name: 'autonomia_prospecting_achar_buscas',
      params: { accountId: '3' },
    });
  });
});

describe('empresa atualizada pelo servidor durante a busca', () => {
  it('fica no grupo da busca e, se foi mandada pela gaveta, segue "você já mandou"', () => {
    const antiga = { id: 1, prioridade: 90, chance: 'boa', mandada: 'Vendas' };
    const nova = empresaDoLead({
      id: 1,
      name: 'Loja',
      priority_score: 10,
      crm_presence: { pipeline_name: 'Vendas', stage_name: 'Novo' },
    });
    const junta = atualizarDaBusca(antiga, nova);

    expect(junta).toMatchObject({
      prioridade: 90,
      chance: 'boa',
      mandada: 'Vendas',
      fora: null,
    });
    expect(junta.noFunil).toMatchObject({ funil: 'Vendas' });
    expect(
      atualizarDaBusca({ ...antiga, mandada: undefined }, nova).fora
    ).toEqual({ motivo: 'no_funil', funil: 'Vendas' });
  });
});

import { ref } from 'vue';
import { FILTROS_VAZIOS } from '../../lista/filtros';
import {
  mesmaConsulta,
  mesmosFiltros,
  useMeusGrupos,
} from '../../lista/useMeusGrupos';
import {
  esquecerGruposGuardados,
  gruposGuardadosFonte,
} from '../../fonte/gruposGuardados';

// #3168 — "Meus grupos": os grupos guardados na memória da demonstração e o
// que a lista faz com eles. O grupo guarda o que a pessoa via: a visão, a
// pílula, a busca e os filtros.
const listaFalsa = () => {
  const grupo = ref('todos');
  const busca = ref('');
  const filtros = ref({ ...FILTROS_VAZIOS });
  return {
    grupo,
    busca,
    filtros,
    mudarFiltros: vi.fn(novos => {
      filtros.value = { ...FILTROS_VAZIOS, ...novos };
    }),
    mudarConsulta: vi.fn(nova => {
      grupo.value = nova.grupo ?? grupo.value;
      busca.value = nova.busca ?? busca.value;
      filtros.value = { ...FILTROS_VAZIOS, ...(nova.filtros ?? {}) };
    }),
  };
};

const montar = (opcoes = {}, visao = ref('conversa')) => {
  const lista = listaFalsa();
  const meus = useMeusGrupos({
    fonte: gruposGuardadosFonte({ demo: true, ...opcoes }),
    lista,
    visaoNaTela: () => visao.value,
    ordemDaVisao: nova => `ordem_de_${nova}`,
    aoFalhar: vi.fn(),
  });
  return { lista, meus, visao };
};

beforeEach(esquecerGruposGuardados);

describe('gruposGuardadosFonte', () => {
  it('começa vazia; com `exemplo`, com os três grupos inventados uma vez só', async () => {
    expect(await gruposGuardadosFonte({ demo: true }).listar()).toEqual([]);
    gruposGuardadosFonte({ demo: true, exemplo: true });
    const guardados = await gruposGuardadosFonte({
      demo: true,
      exemplo: true,
    }).listar();
    expect(guardados.map(({ nome }) => nome)).toEqual([
      'Clientes de Campinas',
      'Sumiram há mais de 90 dias',
      'Vieram da feira',
    ]);
    expect(guardados[0]).toMatchObject({
      visao: 'conversa',
      grupo: 'clientes',
      busca: '',
    });
    expect(guardados[0].filtros.cidade).toBe('Campinas');
  });
});

describe('useMeusGrupos', () => {
  it('guardar grava a visão, a pílula, a busca e os filtros da tela', async () => {
    const { lista, meus } = montar({}, ref('compra'));
    lista.grupo.value = 'compra_fieis';
    lista.busca.value = 'ana';
    lista.filtros.value = { ...FILTROS_VAZIOS, cidade: 'Santos' };
    expect(await meus.guardarComoGrupo('Fiéis de Santos')).toBe(true);
    expect(meus.grupo.value).toMatchObject({
      nome: 'Fiéis de Santos',
      visao: 'compra',
      grupo: 'compra_fieis',
      busca: 'ana',
      filtros: { ...FILTROS_VAZIOS, cidade: 'Santos' },
    });
    expect(lista.mudarConsulta).not.toHaveBeenCalled();
    expect(meus.semMudanca.value).toBe(true);
    expect(meus.mudou.value).toBe(false);
  });

  it('mudar a busca, a pílula ou os filtros deixa o grupo "mudado"', async () => {
    const { lista, meus } = montar();
    lista.filtros.value = { ...FILTROS_VAZIOS, cidade: 'Santos' };
    await meus.guardarComoGrupo('Gente de Santos');
    lista.busca.value = 'ana';
    expect(meus.mudou.value).toBe(true);
    lista.busca.value = '';
    lista.grupo.value = 'clientes';
    expect(meus.mudou.value).toBe(true);
    lista.grupo.value = 'todos';
    lista.filtros.value = { ...FILTROS_VAZIOS, cidade: 'Bauru' };
    expect(meus.mudou.value).toBe(true);
  });

  it('entrar reaplica tudo do primeiro grupo; a ordem só muda com a visão', async () => {
    const { lista, meus } = montar({ exemplo: true });
    await meus.carregar();
    meus.entrar('conversa');
    expect(meus.grupo.value.nome).toBe('Clientes de Campinas');
    expect(lista.mudarConsulta).toHaveBeenLastCalledWith({
      grupo: 'clientes',
      busca: '',
      filtros: meus.grupo.value.filtros,
      ordem: undefined,
    });
    meus.escolher(meus.guardados.value[2].id, 'compra');
    expect(lista.mudarConsulta.mock.lastCall[0].ordem).toBe(
      'ordem_de_conversa'
    );
    expect(meus.semMudanca.value).toBe(true);
  });

  it('sem nenhum guardado, entrar não escolhe nada nem mexe na lista', async () => {
    const { lista, meus } = montar();
    await meus.carregar();
    meus.entrar('conversa');
    expect(meus.escolhido.value).toBe('');
    expect(lista.mudarConsulta).not.toHaveBeenCalled();
  });

  it('"Voltar ao que era" reaplica o grupo escolhido', async () => {
    const { lista, meus } = montar({ exemplo: true });
    await meus.carregar();
    meus.entrar('conversa');
    lista.busca.value = 'ana';
    expect(meus.mudou.value).toBe(true);
    meus.voltar();
    expect(lista.busca.value).toBe('');
    expect(meus.semMudanca.value).toBe(true);
  });

  it('trocar o nome e guardar no grupo mudam só o escolhido', async () => {
    const { lista, meus } = montar({ exemplo: true });
    await meus.carregar();
    meus.escolher(meus.guardados.value[1].id);
    await meus.trocarNome('Sumiram faz tempo');
    const novos = { ...FILTROS_VAZIOS, etiqueta: 'site' };
    await meus.guardarNoGrupo(novos);
    expect(meus.guardados.value.map(({ nome }) => nome)).toEqual([
      'Clientes de Campinas',
      'Sumiram faz tempo',
      'Vieram da feira',
    ]);
    expect(meus.grupo.value.filtros).toEqual(novos);
    expect(lista.mudarFiltros).toHaveBeenLastCalledWith(novos);
  });

  it('guardar no grupo pela faixa grava a busca e a pílula da tela', async () => {
    const { lista, meus } = montar({ exemplo: true });
    await meus.carregar();
    meus.entrar('conversa');
    lista.busca.value = 'ana';
    await meus.guardarNoGrupo();
    expect(meus.grupo.value).toMatchObject({ grupo: 'clientes', busca: 'ana' });
    expect(lista.mudarFiltros).not.toHaveBeenCalled();
    expect(meus.semMudanca.value).toBe(true);
  });

  it('apagar volta para o primeiro que sobrou', async () => {
    const { meus } = montar({ exemplo: true });
    await meus.carregar();
    meus.escolher(meus.guardados.value[0].id);
    await meus.apagar();
    expect(meus.guardados.value).toHaveLength(2);
    expect(meus.grupo.value.nome).toBe('Sumiram há mais de 90 dias');
  });
});

describe('mesmosFiltros e mesmaConsulta', () => {
  it('compara só as chaves dos filtros, com o vazio no lugar do que falta', () => {
    expect(
      mesmosFiltros(
        { cidade: 'Santos' },
        { ...FILTROS_VAZIOS, cidade: 'Santos' }
      )
    ).toBe(true);
    expect(mesmosFiltros({ cidade: 'Santos' }, FILTROS_VAZIOS)).toBe(false);
  });

  it('a consulta também compara a pílula e a busca', () => {
    const tela = { grupo: 'todos', busca: '', filtros: FILTROS_VAZIOS };
    expect(mesmaConsulta(tela, { grupo: 'todos', filtros: {} })).toBe(true);
    expect(mesmaConsulta(tela, { ...tela, busca: 'ana' })).toBe(false);
    expect(mesmaConsulta(tela, { ...tela, grupo: 'clientes' })).toBe(false);
  });
});

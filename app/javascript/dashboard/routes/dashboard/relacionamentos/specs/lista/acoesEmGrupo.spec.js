import { effectScope, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useAcoesEmGrupo } from '../../lista/useAcoesEmGrupo';
import { useMarcados } from '../../lista/useMarcados';

// As ações em grupo da lista (#2894): "Marcar todas" sem aplicar resposta velha
// nem disparar duas cargas, e a volta depois de agir.
const PESSOAS = [{ id: 1 }, { id: 2 }, { id: 3 }];

const montar = ({ todosDoGrupo, grupo = 'todos' } = {}) => {
  const lista = {
    grupo: ref(grupo),
    busca: ref(''),
    filtros: ref({}),
    todosDoGrupo: todosDoGrupo ?? vi.fn().mockResolvedValue(PESSOAS),
    recarregar: vi.fn().mockResolvedValue(undefined),
  };
  const aba = ref('pessoas');
  const marcados = useMarcados();
  const aoFalhar = vi.fn();
  let acoes;
  effectScope().run(() => {
    acoes = useAcoesEmGrupo({ lista, marcados, aba, aoFalhar });
  });
  return { lista, aba, marcados, aoFalhar, acoes };
};

const adiada = () => {
  let resolver;
  let rejeitar;
  const promessa = new Promise((resolve, reject) => {
    resolver = resolve;
    rejeitar = reject;
  });
  return { promessa, resolver, rejeitar };
};

describe('marcarTodas', () => {
  it('marca o grupo inteiro e fica "marcando" só enquanto espera', async () => {
    const espera = adiada();
    const { acoes, marcados } = montar({ todosDoGrupo: () => espera.promessa });
    const andamento = acoes.marcarTodas();
    expect(acoes.marcandoTodas.value).toBe(true);
    espera.resolver(PESSOAS);
    await andamento;
    expect(acoes.marcandoTodas.value).toBe(false);
    expect(marcados.quantos.value).toBe(3);
  });

  it('clique duplo não dispara duas cargas', async () => {
    const espera = adiada();
    const todosDoGrupo = vi.fn(() => espera.promessa);
    const { acoes } = montar({ todosDoGrupo });
    const primeira = acoes.marcarTodas();
    const segunda = acoes.marcarTodas();
    espera.resolver(PESSOAS);
    await Promise.all([primeira, segunda]);
    expect(todosDoGrupo).toHaveBeenCalledTimes(1);
  });

  it.each([
    [
      'o grupo',
      ({ lista }) => {
        lista.grupo.value = 'clientes';
      },
    ],
    [
      'a busca',
      ({ lista }) => {
        lista.busca.value = 'ana';
      },
    ],
    [
      'os filtros',
      ({ lista }) => {
        lista.filtros.value = { cidade: 'Santos' };
      },
    ],
    [
      'a aba',
      ({ aba }) => {
        aba.value = 'empresas';
      },
    ],
  ])('descarta a resposta se mudou %s durante a espera', async (_o, mudar) => {
    const espera = adiada();
    const montado = montar({ todosDoGrupo: () => espera.promessa });
    const andamento = montado.acoes.marcarTodas();
    mudar(montado);
    espera.resolver(PESSOAS);
    await andamento;
    expect(montado.marcados.quantos.value).toBe(0);
    expect(montado.acoes.marcandoTodas.value).toBe(false);
  });

  it('avisa quando a fonte falha', async () => {
    const espera = adiada();
    const { acoes, aoFalhar, marcados } = montar({
      todosDoGrupo: () => espera.promessa,
    });
    const andamento = acoes.marcarTodas();
    espera.rejeitar(new Error('x'));
    await andamento;
    expect(aoFalhar).toHaveBeenCalledTimes(1);
    expect(marcados.quantos.value).toBe(0);
    expect(acoes.marcandoTodas.value).toBe(false);
  });

  it('não avisa de falha de uma consulta que já ficou para trás', async () => {
    const espera = adiada();
    const montado = montar({ todosDoGrupo: () => espera.promessa });
    const andamento = montado.acoes.marcarTodas();
    montado.lista.grupo.value = 'clientes';
    espera.rejeitar(new Error('x'));
    await andamento;
    expect(montado.aoFalhar).not.toHaveBeenCalled();
  });
});

describe('depoisDeAgir', () => {
  it('desmarca e recarrega lista, contagens e resumo', async () => {
    const { acoes, marcados, lista } = montar();
    marcados.marcarVarias(PESSOAS);
    await acoes.depoisDeAgir();
    await flushPromises();
    expect(marcados.quantos.value).toBe(0);
    expect(lista.recarregar).toHaveBeenCalledTimes(1);
  });

  it('se a ação parou no meio, só quem ela não tentou continua marcada', async () => {
    const { acoes, marcados, lista } = montar();
    marcados.marcarVarias(PESSOAS);
    await acoes.depoisDeAgir([PESSOAS[2]]);
    expect(marcados.pessoas.value).toEqual([PESSOAS[2]]);
    expect(lista.recarregar).toHaveBeenCalledTimes(1);
  });
});

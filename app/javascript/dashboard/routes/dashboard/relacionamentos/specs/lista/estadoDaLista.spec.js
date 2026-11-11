import { effectScope, nextTick, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { listaFonte } from '../../fonte/listaFonte';
import { acoesDaListaFonte } from '../../fonte/acoesDaListaFonte';
import { useLista } from '../../lista/useLista';
import { useMarcados } from '../../lista/useMarcados';

// O estado da lista (#2894): consulta, página, "mostrar mais", desmarcar ao
// mudar a consulta, resposta antiga que não pisa na nova.
const demo = () => listaFonte({ demo: 'cheio', atraso: 0 });

const montar = ({
  fonte = demo(),
  abaInicial = 'pessoas',
  aoMudarConsulta,
} = {}) => {
  const aba = ref(abaInicial);
  let lista;
  const escopo = effectScope();
  escopo.run(() => {
    lista = useLista({ fonte, aba, aoMudarConsulta });
  });
  return { aba, lista, parar: () => escopo.stop() };
};

// A fonte de demonstração espera num setTimeout (atraso 0): só um tempo de
// verdade deixa as respostas chegarem.
const assentar = async () => {
  await new Promise(resolve => {
    setTimeout(resolve, 30);
  });
  await flushPromises();
};

describe('useLista', () => {
  it('carrega resumo, contagens e a primeira página ao iniciar', async () => {
    const { lista } = montar();
    await lista.iniciar();
    expect(lista.resumo.value.total).toBe(280);
    expect(lista.contagens.value.clientes).toBe(120);
    expect(lista.itens.value).toHaveLength(25);
    expect(lista.total.value).toBe(280);
    expect(lista.temMais.value).toBe(true);
    expect(lista.carregando.value).toBe(false);
    expect(lista.erro.value).toBeNull();
  });

  it('"mostrar mais" soma mais 25 sem repetir ninguém', async () => {
    const { lista } = montar();
    await lista.iniciar();
    await lista.mostrarMais();
    expect(lista.itens.value).toHaveLength(50);
    expect(new Set(lista.itens.value.map(p => p.id)).size).toBe(50);
  });

  it('não pede mais quando já mostrou tudo', async () => {
    const { lista } = montar();
    await lista.iniciar();
    await lista.escolherGrupo('nao_quer_mensagens');
    expect(lista.itens.value).toHaveLength(9);
    expect(lista.temMais.value).toBe(false);
    await lista.mostrarMais();
    expect(lista.itens.value).toHaveLength(9);
  });

  it('trocar grupo volta para a página 1 e avisa para desmarcar', async () => {
    const aoMudarConsulta = vi.fn();
    const { lista } = montar({ aoMudarConsulta });
    await lista.iniciar();
    await lista.mostrarMais();
    await lista.escolherGrupo('clientes');
    expect(lista.itens.value).toHaveLength(25);
    expect(lista.total.value).toBe(120);
    expect(aoMudarConsulta).toHaveBeenCalledTimes(1);
  });

  it('busca, ordem e filtro também voltam à página 1 e avisam', async () => {
    const aoMudarConsulta = vi.fn();
    const { lista } = montar({ aoMudarConsulta });
    await lista.iniciar();
    await lista.mudarBusca('zzzzqx');
    expect(lista.itens.value).toEqual([]);
    await lista.mudarBusca('');
    await lista.mudarOrdem('nome');
    await lista.mudarFiltros({ cidade: 'Santos' });
    expect(lista.filtrosAtivos.value).toBe(1);
    await lista.limparFiltros();
    expect(lista.filtrosAtivos.value).toBe(0);
    expect(aoMudarConsulta).toHaveBeenCalledTimes(5);
  });

  it('não refaz o pedido quando a escolha é a mesma', async () => {
    const aoMudarConsulta = vi.fn();
    const { lista } = montar({ aoMudarConsulta });
    await lista.iniciar();
    await lista.escolherGrupo('todos');
    await lista.mudarOrdem('ultima_conversa');
    await lista.mudarBusca('');
    expect(aoMudarConsulta).not.toHaveBeenCalled();
  });

  it('trocar de aba escolhe o grupo padrão da aba, tira os filtros e recarrega', async () => {
    const aoMudarConsulta = vi.fn();
    const { aba, lista } = montar({ aoMudarConsulta });
    await lista.iniciar();
    await lista.escolherGrupo('clientes');
    await lista.mudarFiltros({ cidade: 'Santos' });
    aba.value = 'empresas';
    await nextTick();
    await assentar();
    expect(lista.grupo.value).toBe('todas');
    expect(lista.filtrosAtivos.value).toBe(0);
    expect(lista.contagens.value.com_clientes).toBe(14);
    expect(lista.total.value).toBe(38);
    expect(aoMudarConsulta).toHaveBeenCalled();
  });

  it('todosDoGrupo traz o grupo inteiro, não só a página', async () => {
    const { lista } = montar();
    await lista.iniciar();
    await lista.escolherGrupo('sumiu_1_a_3_meses');
    expect(await lista.todosDoGrupo()).toHaveLength(42);
  });

  it('guarda o erro da fonte e limpa quando recarrega com sucesso', async () => {
    const falha = Object.assign(new Error('x'), {
      name: 'FONTE_REAL_PENDENTE',
    });
    const { lista } = montar({ fonte: listaFonte({ demo: null }) });
    await lista.iniciar();
    expect(lista.erro.value).toMatchObject({ name: falha.name });
    expect(lista.resumo.value).toBeNull();
  });

  it('a resposta de um pedido antigo não pisa na do pedido novo', async () => {
    const respostas = {};
    const fonte = {
      ...demo(),
      listar: pedido =>
        new Promise(resolve => {
          respostas[pedido.grupo] = () =>
            resolve({
              itens: [{ id: pedido.grupo }],
              total: 1,
              temMais: false,
            });
        }),
    };
    const { lista } = montar({ fonte });
    const primeiro = lista.escolherGrupo('clientes');
    const segundo = lista.escolherGrupo('nunca_conversou');
    respostas.nunca_conversou();
    respostas.clientes();
    await Promise.all([primeiro, segundo]);
    expect(lista.itens.value).toEqual([{ id: 'nunca_conversou' }]);
    expect(lista.carregando.value).toBe(false);
  });
});

describe('useMarcados', () => {
  const ana = { id: 1, name: 'Ana' };
  const bia = { id: 2, name: 'Bia' };

  it('marca e desmarca sem mexer no mapa antigo', () => {
    const marcados = useMarcados();
    marcados.alternar(ana);
    expect(marcados.quantos.value).toBe(1);
    expect(marcados.ehMarcado(1)).toBe(true);
    marcados.alternar(ana);
    expect(marcados.ehMarcado(1)).toBe(false);
  });

  it('guarda a pessoa inteira para os diálogos', () => {
    const marcados = useMarcados();
    marcados.alternar(ana);
    marcados.alternar(bia);
    expect(marcados.pessoas.value).toEqual([ana, bia]);
  });

  it('marcarVarias troca tudo pelo grupo inteiro', () => {
    const marcados = useMarcados();
    marcados.alternar(ana);
    marcados.marcarVarias([bia]);
    expect(marcados.pessoas.value).toEqual([bia]);
  });

  it('limpar desmarca todo mundo', () => {
    const marcados = useMarcados();
    marcados.marcarVarias([ana, bia]);
    marcados.limpar();
    expect(marcados.quantos.value).toBe(0);
  });
});

describe('acoesDaListaFonte', () => {
  const acoes = () => acoesDaListaFonte({ demo: 'cheio', atraso: 0 });
  const pessoas = ids => ids.map(id => ({ id, name: `Pessoa ${id}` }));

  it('oferece funis fictícios com etapas e etiquetas', async () => {
    const funis = await acoes().funis();
    expect(funis.length).toBeGreaterThan(1);
    expect(funis.every(f => f.etapas.length > 0)).toBe(true);
    expect((await acoes().etiquetas()).length).toBeGreaterThan(0);
  });

  it('cria os cards e deixa de fora quem já tem, com o motivo', async () => {
    const resultado = await acoes().criarCards({
      pessoas: pessoas([1, 2, 9, 3]),
      funilId: 'vendas',
      etapaId: 'primeira-conversa',
    });
    expect(resultado.criados).toBe(3);
    expect(resultado.deFora).toEqual([
      { id: 9, nome: 'Pessoa 9', motivo: 'ja_tem_card' },
    ]);
  });

  it('simula etiqueta e apagar: só conta, não grava', async () => {
    expect(
      await acoes().aplicarEtiqueta({
        pessoas: pessoas([1, 2]),
        etiqueta: 'feira',
      })
    ).toEqual({ aplicadas: 2 });
    expect(await acoes().apagar({ pessoas: pessoas([1]) })).toEqual({
      apagadas: 1,
    });
  });

  it.each(['funis', 'etiquetas', 'criarCards', 'aplicarEtiqueta', 'apagar'])(
    '%s diz que a fonte real ainda não existe',
    async metodo => {
      await expect(
        acoesDaListaFonte({ demo: null })[metodo]({})
      ).rejects.toMatchObject({ name: 'FONTE_REAL_PENDENTE' });
    }
  );
});

import { effectScope, nextTick, ref } from 'vue';
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

// Uma fonte em que as leituras de `quais` são recusadas pelo servidor até
// `voltar()`; as outras respondem como a demonstração.
const fonteQueFalha = quais => {
  const recusado = Object.assign(
    new Error('Request failed with status code 500'),
    { response: { status: 500 } }
  );
  const boa = demo();
  let falhando = true;
  const leitura = metodo =>
    quais.includes(metodo)
      ? (...args) =>
          falhando ? Promise.reject(recusado) : boa[metodo](...args)
      : boa[metodo];
  return {
    recusado,
    voltar: () => {
      falhando = false;
    },
    fonte: {
      ...boa,
      resumo: leitura('resumo'),
      contagens: leitura('contagens'),
      listar: leitura('listar'),
    },
  };
};

// A fonte de demonstração espera num setTimeout (atraso 0): em vez de dormir,
// cada teste espera pela condição que lhe interessa.
const ate = verificacao => vi.waitFor(verificacao, { timeout: 5000 });

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
    await ate(() => expect(lista.total.value).toBe(38));
    await ate(() => expect(lista.contagens.value.com_clientes).toBe(14));
    expect(lista.grupo.value).toBe('todas');
    expect(lista.filtrosAtivos.value).toBe(0);
    expect(aoMudarConsulta).toHaveBeenCalled();
  });

  it('todosDoGrupo traz o grupo inteiro, não só a página', async () => {
    const { lista } = montar();
    await lista.iniciar();
    await lista.escolherGrupo('sumiu_1_a_3_meses');
    expect(await lista.todosDoGrupo()).toHaveLength(42);
  });

  it('guarda o erro da fonte e limpa quando recarrega com sucesso', async () => {
    const servidor = fonteQueFalha(['resumo', 'contagens', 'listar']);
    const { lista } = montar({ fonte: servidor.fonte });
    await lista.iniciar();
    expect(lista.erro.value).toBe(servidor.recusado);
    expect(lista.resumo.value).toBeNull();

    servidor.voltar();
    await lista.recarregar();
    expect(lista.erro.value).toBeNull();
    expect(lista.resumo.value.total).toBe(280);
    expect(lista.itens.value).toHaveLength(25);
  });

  // Fora da demonstração as três leituras são pedidos separados: uma pode
  // falhar e as outras responderem. O erro de uma não some com o sucesso da outra.
  it.each(['resumo', 'contagens'])(
    'o erro de %s continua de pé quando a lista responde',
    async leitura => {
      const servidor = fonteQueFalha([leitura]);
      const { lista } = montar({ fonte: servidor.fonte });
      await lista.iniciar();
      expect(lista.itens.value).toHaveLength(25);
      expect(lista.erro.value).toBe(servidor.recusado);

      await lista.escolherGrupo('clientes');
      expect(lista.erro.value).toBe(servidor.recusado);

      servidor.voltar();
      await lista.recarregar();
      expect(lista.erro.value).toBeNull();
    }
  );

  it('o erro da lista some quando o pedido seguinte da lista responde', async () => {
    const servidor = fonteQueFalha(['listar']);
    const { lista } = montar({ fonte: servidor.fonte });
    await lista.iniciar();
    expect(lista.erro.value).toBe(servidor.recusado);

    servidor.voltar();
    await lista.escolherGrupo('clientes');
    expect(lista.erro.value).toBeNull();
    expect(lista.total.value).toBe(120);
  });

  it('"mostrar mais" atropelado por um pedido da página 1 não deixa carregandoMais preso', async () => {
    const pendentes = [];
    const fonte = {
      ...demo(),
      listar: () =>
        new Promise(resolve => {
          pendentes.push(() =>
            resolve({ itens: [{ id: 1 }], total: 40, temMais: true })
          );
        }),
    };
    const { lista } = montar({ fonte });
    lista.temMais.value = true;
    const mais = lista.mostrarMais();
    expect(lista.carregandoMais.value).toBe(true);
    const primeira = lista.mudarBusca('ana');
    expect(lista.carregandoMais.value).toBe(false);
    pendentes.forEach(responder => responder());
    await Promise.all([mais, primeira]);
    expect(lista.carregandoMais.value).toBe(false);
    expect(lista.carregando.value).toBe(false);
  });

  it('busca e filtro refazem as contagens dos grupos; grupo e ordem não', async () => {
    const fonte = demo();
    const contagens = vi.spyOn(fonte, 'contagens');
    const { lista } = montar({ fonte });
    await lista.iniciar();
    expect(contagens).toHaveBeenCalledTimes(1);
    const { name } = lista.itens.value[0];
    await lista.mudarBusca(name);
    await ate(() => expect(contagens).toHaveBeenCalledTimes(2));
    await ate(() =>
      expect(lista.contagens.value.todos).toBe(lista.total.value)
    );
    expect(lista.contagens.value.todos).toBeLessThan(280);
    await lista.mudarFiltros({ cidade: 'Santos' });
    await ate(() => expect(contagens).toHaveBeenCalledTimes(3));
    await lista.escolherGrupo('clientes');
    await lista.mudarOrdem('nome');
    expect(contagens).toHaveBeenCalledTimes(3);
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

  it('as três escritas devolvem o mesmo formato da fonte real', async () => {
    const semNinguemDeFora = { deFora: [], faltam: [], erro: null };
    expect(
      await acoes().aplicarEtiqueta({
        pessoas: pessoas([1, 2]),
        etiqueta: 'feira',
      })
    ).toEqual({ aplicadas: 2, ...semNinguemDeFora });
    expect(await acoes().apagar({ pessoas: pessoas([1]) })).toEqual({
      apagadas: 1,
      ...semNinguemDeFora,
    });
    expect(
      await acoes().criarCards({
        pessoas: pessoas([1, 2]),
        funilId: 'vendas',
        etapaId: 'primeira-conversa',
      })
    ).toEqual({ criados: 2, ...semNinguemDeFora });
  });

  it('simula o andamento em fatias de 50, como a fonte real', async () => {
    const aoAndar = vi.fn();
    const muitas = pessoas(Array.from({ length: 120 }, (_, i) => i + 1));
    await acoes().apagar({ pessoas: muitas, aoAndar });
    expect(aoAndar.mock.calls.map(([passo]) => passo)).toEqual([
      { feitas: 50, total: 120 },
      { feitas: 100, total: 120 },
      { feitas: 120, total: 120 },
    ]);
  });

  it('para antes da próxima fatia quando pedem para parar', async () => {
    const muitas = pessoas(Array.from({ length: 120 }, (_, i) => i + 1));
    const aoAndar = vi.fn();
    const resultado = await acoes().apagar({
      pessoas: muitas,
      aoAndar,
      deveParar: () => aoAndar.mock.calls.length >= 1,
    });
    expect(resultado).toEqual({
      apagadas: 50,
      deFora: [],
      faltam: muitas.slice(50),
      erro: null,
    });
  });

  it('sem `?demo=` é a fonte real', () => {
    expect(acoesDaListaFonte({ demo: null }).usaDemo).toBe(false);
  });
});

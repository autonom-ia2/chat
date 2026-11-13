import { effectScope, nextTick, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import SeloDeEstado from '../../components/comum/SeloDeEstado.vue';
import AbasDaLista from '../../components/lista/AbasDaLista.vue';
import MenuMaisAcoes from '../../components/lista/MenuMaisAcoes.vue';
import { useApoliceNaUrl } from '../../carteira/useApoliceNaUrl';
import { useContaDeSeguros } from '../../carteira/useContaDeSeguros';
import { useSeguroAberto } from '../../carteira/useSeguroAberto';
import { ESTADOS_DOS_SEGUROS, useSegurosDe } from '../../carteira/useSegurosDe';
import {
  FILTROS_DE_SEGUROS_VAZIOS,
  contarFiltrosDeSeguros,
} from '../../fonte/carteiraFonte';
import { NAO_ACHEI, SEM_ACESSO } from '../../ficha/falhas';
import { useLista } from '../../lista/useLista';
import { recusa } from './apoio';

// O que a carteira de seguros (#2897) mudou em peças que já existiam (as abas,
// o "⋯", o selo e o estado da lista) e os composables pequenos dela.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
const conta = vi.hoisted(() => ({ atual: null }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: {
      get value() {
        return conta.atual;
      },
    },
  }),
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {} });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');

const rota = useRoute();
const roteador = useRouter();

// Uma resposta da fonte que só chega quando o teste manda.
const respostaNaMao = () => {
  const naMao = {};
  naMao.promessa = new Promise((resolver, recusar) => {
    naMao.resolver = resolver;
    naMao.recusar = recusar;
  });
  return naMao;
};

describe('as abas, com a aba Seguros', () => {
  const nomes = w => w.findAll('[role="tab"]').map(aba => aba.text());

  it('sem `comSeguros` continuam Pessoas e Empresas', () => {
    const w = mount(AbasDaLista, { props: { modelValue: 'pessoas' } });

    expect(nomes(w)).toEqual(['Pessoas', 'Empresas']);
  });

  it('com a carteira, Seguros entra por último', () => {
    const w = mount(AbasDaLista, {
      props: { modelValue: 'seguros', comSeguros: true },
    });
    const abas = w.findAll('[role="tab"]');

    expect(nomes(w)).toEqual(['Pessoas', 'Empresas', 'Seguros']);
    expect(abas.map(aba => aba.attributes('aria-selected'))).toEqual([
      'false',
      'false',
      'true',
    ]);
    expect(abas.map(aba => aba.attributes('tabindex'))).toEqual([
      '-1',
      '-1',
      '0',
    ]);
  });

  it('conta sem Empresas fica com Pessoas e Seguros', () => {
    const w = mount(AbasDaLista, {
      props: { modelValue: 'pessoas', comEmpresas: false, comSeguros: true },
    });

    expect(nomes(w)).toEqual(['Pessoas', 'Seguros']);
  });

  it.each([
    ['pessoas', 'End', 'seguros'],
    ['seguros', 'ArrowRight', 'pessoas'],
    ['pessoas', 'ArrowLeft', 'seguros'],
    ['empresas', 'ArrowRight', 'seguros'],
  ])('na aba %s, %s vai para %s', async (atual, tecla, destino) => {
    const w = mount(AbasDaLista, {
      props: { modelValue: atual, comSeguros: true },
    });

    await w.get('[role="tablist"]').trigger('keydown', { key: tecla });

    expect(w.emitted('update:modelValue')).toEqual([[destino]]);
  });
});

describe('o "⋯" com nome e tamanho de quem usa', () => {
  const ITENS = [{ id: 'um', rotulo: 'Um', icone: 'i-lucide-pencil' }];
  const gatilho = w => w.get('[aria-haspopup="menu"]');

  it('por padrão tem 44 px e o nome da barra de ação em grupo', () => {
    const w = mount(MenuMaisAcoes, { props: { itens: ITENS } });

    expect(gatilho(w).classes()).toContain('size-11');
    expect(gatilho(w).attributes('aria-label')).toBe('Mais ações');
  });

  it('`rotulo` troca o nome e `tamanho="lg"` acompanha os botões grandes', () => {
    const w = mount(MenuMaisAcoes, {
      props: {
        itens: ITENS,
        rotulo: 'Mais opções deste seguro',
        tamanho: 'lg',
      },
    });

    expect(gatilho(w).attributes('aria-label')).toBe(
      'Mais opções deste seguro'
    );
    expect(gatilho(w).classes()).not.toContain('size-11');
    expect(gatilho(w).classes()).toContain('h-12');
  });
});

describe('o selo, nos tons da carteira', () => {
  it.each([
    ['verde', 'text-n-teal-11'],
    ['ambar', 'text-n-amber-11'],
    ['vermelho', 'text-n-ruby-11'],
    ['neutro', 'text-n-slate-11'],
  ])('o tom %s é só cor, sem ícone', (tom, classe) => {
    const w = mount(SeloDeEstado, { props: { tom }, slots: { default: 'x' } });

    expect(w.attributes('data-selo')).toBe(tom);
    expect(w.classes()).toContain(classe);
    expect(w.find('[aria-hidden="true"]').exists()).toBe(false);
  });
});

describe('o estado da lista, com o que é da aba Seguros', () => {
  const fonteDeMentira = () => ({
    resumo: vi.fn().mockResolvedValue({ total: 1, vence7: 0 }),
    contagens: vi.fn().mockResolvedValue({ todos: 1 }),
    listar: vi.fn().mockResolvedValue({ itens: [], total: 0, temMais: false }),
  });
  const umaPagina = (itens, temMais) => ({ itens, total: 3, temMais });
  const montar = fonte => {
    let lista;
    const escopo = effectScope();
    escopo.run(() => {
      lista = useLista({
        fonte,
        aba: ref('seguros'),
        grupoPadrao: () => 'todos',
        ordemPadrao: 'vence_primeiro',
        filtrosVazios: FILTROS_DE_SEGUROS_VAZIOS,
        contar: contarFiltrosDeSeguros,
      });
    });
    return lista;
  };
  // Duas páginas à vista: a primeira com dois seguros e a segunda com um.
  const comDuasPaginas = async fonte => {
    fonte.listar
      .mockResolvedValueOnce(umaPagina([{ id: 1 }, { id: 2 }], true))
      .mockResolvedValueOnce(umaPagina([{ id: 3 }], false));
    const lista = montar(fonte);
    await lista.iniciar();
    await lista.mostrarMais();
    return lista;
  };

  it('começa no grupo, na ordem e nos filtros que recebeu', async () => {
    const fonte = fonteDeMentira();
    const lista = montar(fonte);

    await lista.iniciar();

    expect(fonte.listar).toHaveBeenCalledWith({
      aba: 'seguros',
      grupo: 'todos',
      busca: '',
      ordem: 'vence_primeiro',
      filtros: { tipo: '', seguradora: '' },
      pagina: 1,
    });
    expect(lista.filtrosAtivos.value).toBe(0);
  });

  it('filtrar completa com os filtros vazios da aba e conta os ligados', async () => {
    const fonte = fonteDeMentira();
    const lista = montar(fonte);

    await lista.mudarFiltros({ tipo: 'auto' });

    expect(lista.filtros.value).toEqual({ tipo: 'auto', seguradora: '' });
    expect(lista.filtrosAtivos.value).toBe(1);
    expect(fonte.contagens).toHaveBeenLastCalledWith('seguros', {
      busca: '',
      filtros: { tipo: 'auto', seguradora: '' },
    });

    await lista.limparFiltros();

    expect(lista.filtros.value).toEqual(FILTROS_DE_SEGUROS_VAZIOS);
    expect(lista.filtrosAtivos.value).toBe(0);
  });

  it('atualizar relê as páginas à vista sem ligar o carregando', async () => {
    const fonte = fonteDeMentira();
    const lista = await comDuasPaginas(fonte);
    fonte.listar.mockImplementation(async ({ pagina }) =>
      pagina === 1
        ? umaPagina([{ id: 1 }, { id: 2, mudou: true }], true)
        : umaPagina([{ id: 3 }], false)
    );

    const atualizando = lista.atualizar();

    expect(lista.carregando.value).toBe(false);
    expect(lista.carregandoMais.value).toBe(false);
    expect(lista.itens.value).toHaveLength(3);
    await atualizando;
    expect(lista.itens.value).toEqual([
      { id: 1 },
      { id: 2, mudou: true },
      { id: 3 },
    ]);
    expect(lista.temMais.value).toBe(false);
    expect(
      fonte.listar.mock.calls.slice(-2).map(([consulta]) => consulta.pagina)
    ).toEqual([1, 2]);
    expect(fonte.resumo).toHaveBeenCalledTimes(2);
    expect(fonte.contagens).toHaveBeenCalledTimes(2);
    // "Mostrar mais" continua de onde estava: não há terceira página.
    expect(lista.mostrarMais()).toBeUndefined();
  });

  it('se atualizar falha, o que estava à vista fica e o erro aparece', async () => {
    const fonte = fonteDeMentira();
    const lista = await comDuasPaginas(fonte);
    fonte.listar.mockRejectedValue(new Error('rede'));

    await lista.atualizar();

    expect(lista.itens.value).toEqual([{ id: 1 }, { id: 2 }, { id: 3 }]);
    expect(lista.erro.value).toBeInstanceOf(Error);
  });

  it('se a pessoa muda a consulta no meio, a resposta do atualizar é descartada', async () => {
    const fonte = fonteDeMentira();
    const lista = await comDuasPaginas(fonte);
    const velha = respostaNaMao();
    fonte.listar.mockReturnValue(velha.promessa);
    const atualizando = lista.atualizar();

    fonte.listar.mockResolvedValue(umaPagina([{ id: 9 }], false));
    await lista.escolherGrupo('vencido');
    velha.resolver(umaPagina([{ id: 1 }, { id: 2 }], false));
    await atualizando;

    expect(lista.itens.value).toEqual([{ id: 9 }]);
  });

  it('com outra leitura da lista em andamento, atualizar só relê os números', async () => {
    const fonte = fonteDeMentira();
    const lista = montar(fonte);
    const lenta = respostaNaMao();
    fonte.listar.mockReturnValue(lenta.promessa);
    const iniciando = lista.iniciar();

    await lista.atualizar();

    expect(fonte.listar).toHaveBeenCalledTimes(1);
    expect(fonte.resumo).toHaveBeenCalledTimes(2);
    lenta.resolver(umaPagina([{ id: 1 }], false));
    await iniciando;
    expect(lista.itens.value).toEqual([{ id: 1 }]);
  });
});

describe('o seguro aberto: cada resposta é da ação e do seguro que a pediram', () => {
  const SEGURO = { id: 7, canceladoEm: null };
  const CANCELADO = { id: 7, canceladoEm: 1 };
  const abrir = (fonte, id = ref(SEGURO.id)) => {
    let aberto;
    effectScope().run(() => {
      aberto = useSeguroAberto(fonte, id);
    });
    return aberto;
  };
  const fonteCom = resto => ({
    seguro: vi.fn().mockResolvedValue(SEGURO),
    historia: vi.fn().mockResolvedValue([]),
    ...resto,
  });

  it('a ação antiga que termina não desliga o "ocupado" da mais nova', async () => {
    const cancelando = respostaNaMao();
    const relendo = respostaNaMao();
    const aberto = abrir(
      fonteCom({
        cancelar: vi.fn(() => cancelando.promessa),
        seguro: vi.fn(() => relendo.promessa),
      })
    );

    const cancelar = aberto.cancelar();
    const reler = aberto.reler();
    expect(aberto.ocupado.value).toBe('reler');

    cancelando.resolver(CANCELADO);
    expect(await cancelar).toBe(true);
    expect(aberto.ocupado.value).toBe('reler');

    relendo.resolver(CANCELADO);
    expect(await reler).toBe(true);
    expect(aberto.ocupado.value).toBe('');
  });

  it('trocar de seguro zera o "ocupado", e a resposta do anterior não entra', async () => {
    const id = ref(SEGURO.id);
    const cancelando = respostaNaMao();
    const fonte = fonteCom({ cancelar: vi.fn(() => cancelando.promessa) });
    const aberto = abrir(fonte, id);

    const cancelar = aberto.cancelar();
    expect(aberto.ocupado.value).toBe('cancelar');
    id.value = 8;
    await nextTick();
    expect(aberto.ocupado.value).toBe('');

    cancelando.resolver(CANCELADO);

    // A ação deu certo (quem chama avisa a lista), mas o seguro não é o aberto.
    expect(await cancelar).toBe(true);
    expect(aberto.seguro.value).toBeNull();
    expect(fonte.historia).not.toHaveBeenCalled();
    expect(fonte.cancelar.mock.calls[0][0]).toBe(SEGURO.id);
  });

  it('a recusa que chega depois da troca não fica guardada', async () => {
    const id = ref(SEGURO.id);
    const cancelando = respostaNaMao();
    const aberto = abrir(
      fonteCom({ cancelar: vi.fn(() => cancelando.promessa) }),
      id
    );

    const cancelar = aberto.cancelar();
    id.value = 8;
    await nextTick();
    cancelando.recusar(recusa('ja_cancelado'));

    expect(await cancelar).toBe(false);
    expect(aberto.recusa.value).toBe('');
  });

  it('no mesmo seguro, a recusa fica guardada para quem escolhe a frase', async () => {
    const aberto = abrir(
      fonteCom({
        cancelar: vi.fn().mockRejectedValue(recusa('ja_cancelado')),
      })
    );

    expect(await aberto.cancelar()).toBe(false);
    expect(aberto.recusa.value).toBe('ja_cancelado');
    expect(aberto.ocupado.value).toBe('');
  });

  it('`receber` só guarda o seguro que está aberto', () => {
    const fonte = fonteCom();
    const aberto = abrir(fonte);

    expect(aberto.receber({ id: 8 })).toBe(false);
    expect(aberto.seguro.value).toBeNull();
    expect(aberto.receber(CANCELADO)).toBe(true);
    expect(aberto.seguro.value).toEqual(CANCELADO);
    expect(fonte.historia).toHaveBeenCalledWith(SEGURO.id);
  });
});

describe('o seguro aberto mora no endereço', () => {
  beforeEach(() => {
    rota.query = {};
  });

  it.each([
    [{ apolice: '12' }, 12],
    [{}, null],
    [{ apolice: 'abc' }, null],
    [{ apolice: '0' }, null],
    [{ apolice: '-3' }, null],
    [{ apolice: '1.5' }, null],
  ])('lê %o como %o', (query, esperado) => {
    rota.query = query;

    expect(useApoliceNaUrl().apolice.value).toBe(esperado);
  });

  it('abrir e fechar só trocam esse pedaço do endereço', () => {
    rota.query = { aba: 'seguros', demo: 'cheio' };
    const { apolice, abrir, fechar } = useApoliceNaUrl();

    abrir(7);

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { aba: 'seguros', demo: 'cheio', apolice: '7' },
    });
    expect(apolice.value).toBe(7);

    fechar();

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { aba: 'seguros', demo: 'cheio' },
    });
    expect(apolice.value).toBeNull();
  });
});

describe('a conta tem a carteira?', () => {
  it('fora da demonstração responde o payload da conta', () => {
    conta.atual = { id: 1, carteira_seguros: true };
    expect(useContaDeSeguros(null).value).toBe(true);

    conta.atual = { id: 1, carteira_seguros: false };
    expect(useContaDeSeguros(null).value).toBe(false);

    conta.atual = undefined;
    expect(useContaDeSeguros(null).value).toBe(false);
  });

  it('na demonstração responde o estado dela', () => {
    conta.atual = { id: 1, carteira_seguros: false };

    expect(useContaDeSeguros('cheio').value).toBe(true);
    expect(useContaDeSeguros('fora-do-segmento').value).toBe(false);
  });
});

describe('os seguros de uma pessoa ou empresa', () => {
  const SEGUROS = [{ id: 1 }, { id: 2 }];

  it('carrega e fica pronto', async () => {
    const lista = useSegurosDe(() => Promise.resolve(SEGUROS));

    expect(lista.estado.value).toBe(ESTADOS_DOS_SEGUROS.CARREGANDO);
    await lista.carregar();

    expect(lista.estado.value).toBe(ESTADOS_DOS_SEGUROS.PRONTO);
    expect(lista.seguros.value).toEqual(SEGUROS);
  });

  it('falha comum vira erro', async () => {
    const lista = useSegurosDe(() => Promise.reject(new Error('rede')));

    await lista.carregar();

    expect(lista.estado.value).toBe(ESTADOS_DOS_SEGUROS.ERRO);
  });

  it.each([NAO_ACHEI, SEM_ACESSO])('a falha %s esconde o bloco', async name => {
    const falha = Object.assign(new Error('x'), { name });
    const lista = useSegurosDe(() => Promise.reject(falha));

    await lista.carregar();

    expect(lista.estado.value).toBe(ESTADOS_DOS_SEGUROS.ESCONDIDO);
  });

  it('atualizar troca a lista sem voltar ao esqueleto', async () => {
    const buscar = vi
      .fn()
      .mockResolvedValueOnce(SEGUROS)
      .mockResolvedValue([{ id: 3 }]);
    const lista = useSegurosDe(buscar);
    await lista.carregar();

    const atualizando = lista.atualizar();

    expect(lista.estado.value).toBe(ESTADOS_DOS_SEGUROS.PRONTO);
    await atualizando;
    expect(lista.seguros.value).toEqual([{ id: 3 }]);
  });

  it('resposta de pedido antigo não pisa na do mais novo', async () => {
    let soltarAntigo;
    const antigo = new Promise(resolve => {
      soltarAntigo = resolve;
    });
    const buscar = vi
      .fn()
      .mockReturnValueOnce(antigo)
      .mockResolvedValue([{ id: 9 }]);
    const lista = useSegurosDe(buscar);

    lista.carregar();
    await lista.carregar();
    soltarAntigo(SEGUROS);
    await flushPromises();

    expect(lista.seguros.value).toEqual([{ id: 9 }]);
  });
});

import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import { usarDemo } from '../../fonte/modoDemo';
import MarcarTodas from '../../components/lista/MarcarTodas.vue';
import ListaPage from '../../pages/ListaPage.vue';

// A lista de Relacionamentos inteira (#2894), com a base fictícia e o texto de
// verdade em pt_BR: cheio, vazio, carregando, erro, ações e navegação.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./teleportFalso')).TeleportFalso,
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(),
}));
// A conta dos testes não tem a chave `companies`: a demonstração inventa as
// empresas e mostra a aba mesmo assim.
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
// A pessoa dos testes não pode criar card, etiquetar nem apagar: a demonstração
// mostra as três ações mesmo assim (as permissões de verdade estão em
// ListaPageReal).
vi.mock('../../lista/usePermissoesDaLista', () => ({
  usePermissoesDaLista: () => ({
    podeCriarCards: { value: false },
    podeEtiquetar: { value: false },
    podeApagar: { value: false },
  }),
}));
// Fora da demonstração a lista lê do servidor; aqui ele recusa todo pedido (a
// lista com respostas de verdade está em ListaPageReal.spec.js).
vi.mock('dashboard/api/relacionamentos', () => {
  const recusar = () =>
    Promise.reject(new Error('Request failed with status code 500'));
  const leituras = [
    'pessoas',
    'contagensDePessoas',
    'todasAsPessoas',
    'empresas',
    'contagensDeEmpresas',
    'resumo',
    'opcoesDeFiltro',
  ];
  return {
    default: Object.fromEntries(leituras.map(nome => [nome, recusar])),
  };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
// A demonstração sem o atraso de 300 ms (os testes esperam as respostas).
// `trocas.listar` deixa um teste responder a lista de um jeito só dele.
const trocas = vi.hoisted(() => ({ listar: null, listarTodos: null }));
vi.mock('../../fonte/listaFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    listaFonte: opcoes => {
      const base = real.listaFonte({ ...opcoes, atraso: 0 });
      return {
        ...base,
        listar: pedido =>
          trocas.listar ? trocas.listar(base, pedido) : base.listar(pedido),
        listarTodos: pedido =>
          trocas.listarTodos
            ? trocas.listarTodos(base, pedido)
            : base.listarTodos(pedido),
      };
    },
  };
});
vi.mock('../../fonte/acoesDaListaFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    acoesDaListaFonte: opcoes =>
      real.acoesDaListaFonte({ ...opcoes, atraso: 0 }),
  };
});

withFullI18n('pt_BR');

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

// Sem animação de saída: a barra e a gaveta somem na hora, como o teste espera.
const COMO_NO_NAVEGADOR = {
  attachTo: document.body,
  global: { stubs: { transition: true } },
};

const rota = useRoute();
const roteador = useRouter();
const marca = nome => `[data-relacionamentos="${nome}"]`;

// A fonte de demonstração e a busca esperam em setTimeout: com o relógio falso
// o tempo é nosso, e a máquina carregada não muda o resultado.
const avancar = ms => vi.advanceTimersByTimeAsync(ms);
const assentar = async () => {
  await avancar(40);
  await flushPromises();
};

const abrir = async ({ demo = 'cheio', query = {} } = {}) => {
  usarDemo.mockReturnValue(demo);
  rota.name = 'relationships_home';
  rota.query = query;
  const w = mount(ListaPage, COMO_NO_NAVEGADOR);
  await assentar();
  await vi.waitFor(
    () => expect(w.find(marca('carregando')).exists()).toBe(false),
    { timeout: 5000 }
  );
  return w;
};

const textoDe = (w, seletor) => w.get(seletor).text();
const linhas = w => w.findAll(marca('linha'));
const pilula = (w, id) => w.get(`[data-grupo="${id}"]`);

let aberta;
const montar = async opcoes => {
  aberta = await abrir(opcoes);
  return aberta;
};

// As fontes de demonstração carregam os dados por import() dinâmico, que leva
// tempo de verdade. Carregar antes deixa as respostas só por conta do relógio
// falso, não da velocidade da máquina.
beforeAll(async () => {
  await Promise.all([
    import('../../demo/base.js'),
    import('../../demo/acoesDaLista.js'),
  ]);
}, 60000);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});

afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  trocas.listar = null;
  trocas.listarTodos = null;
  vi.clearAllMocks();
});

const NINGUEM = { itens: [], total: 0, temMais: false };

describe('ListaPage: largura e respiro', () => {
  it('a raiz da página ocupa a largura disponível sempre, qualquer que seja o conteúdo', async () => {
    // A raiz é filha de um contêiner flex: sem `w-full flex-1` ela encolheria
    // até a largura do conteúdo (Empresas, conta vazia).
    const pessoas = await montar();
    expect(pessoas.classes()).toEqual(
      expect.arrayContaining(['w-full', 'flex-1', 'min-w-0'])
    );
    pessoas.unmount();
    const vazia = await montar({ demo: 'vazio' });
    expect(vazia.classes()).toEqual(
      expect.arrayContaining(['w-full', 'flex-1', 'min-w-0'])
    );
    vazia.unmount();
    const empresas = await montar({ query: { aba: 'empresas' } });
    expect(empresas.classes()).toEqual(
      expect.arrayContaining(['w-full', 'flex-1', 'min-w-0'])
    );
  });

  it('o contêiner ocupa a largura toda e nunca empurra a página para o lado', async () => {
    const w = await montar();
    const conteudo = w.get('main > div');
    expect(conteudo.classes()).toEqual(
      expect.arrayContaining(['w-full', 'min-w-0', 'max-w-6xl', 'mx-auto'])
    );
    expect(w.get('main').classes()).toContain('min-w-0');
    expect(w.get(`[role="tabpanel"]`).classes()).toContain('min-w-0');
  });

  it('deixa respiro embaixo para a última linha não ficar atrás da barra nem do botão do app', async () => {
    const w = await montar();
    expect(w.get('main > div').classes()).toEqual(
      expect.arrayContaining(['pb-24', 'md:pb-10'])
    );
  });

  it('com gente marcada a lista ganha folga extra do tamanho da barra', async () => {
    const w = await montar();
    await w.get(`${marca('marcar')} input`).setValue(true);
    const classes = w.get('main > div').classes();
    expect(classes).toEqual(expect.arrayContaining(['pb-48', 'md:pb-28']));
    expect(classes).not.toContain('pb-24');
  });

  it('a barra de ação deixa livre o canto do botão do menu do app no celular', async () => {
    const w = await montar();
    await w.get(`${marca('marcar')} input`).setValue(true);
    expect(w.get(marca('barra')).classes()).toEqual(
      expect.arrayContaining(['ms-20', 'md:ms-0'])
    );
  });
});

describe('ListaPage: carregando', () => {
  it('mostra o esqueleto enquanto a base não chegou e depois some', async () => {
    usarDemo.mockReturnValue('cheio');
    rota.query = {};
    aberta = mount(ListaPage, COMO_NO_NAVEGADOR);
    expect(aberta.find(marca('carregando')).exists()).toBe(true);
    expect(aberta.get(marca('carregando')).attributes('aria-busy')).toBe(
      'true'
    );
    await assentar();
    expect(aberta.find(marca('carregando')).exists()).toBe(false);
    expect(aberta.find(marca('heroi-acao')).exists()).toBe(true);
  });

  it('mostra o esqueleto só na lista quando troca de grupo', async () => {
    const w = await montar();
    await pilula(w, 'clientes').trigger('click');
    expect(w.find(marca('carregando')).exists()).toBe(true);
    expect(w.find(marca('busca')).exists()).toBe(true);
    await assentar();
    expect(w.find(marca('carregando')).exists()).toBe(false);
  });
});

describe('ListaPage: cheia', () => {
  it('tem o título da página só para o leitor de tela', async () => {
    const w = await montar();
    expect(w.attributes('data-relacionamentos')).toBe('lista');
    expect(w.get('h1').classes()).toContain('sr-only');
    expect(w.get('h1').text()).toBe('Relacionamentos');
  });

  it('abre com a frase de quem sumiu, as abas, os sete grupos e a primeira página', async () => {
    const w = await montar();
    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      '42 pessoas pararam de falar com você nos últimos 3 meses.'
    );
    expect(textoDe(w, marca('heroi-acao'))).toBe('Ver quem sumiu');
    expect(w.findAll('[role="tab"]').map(a => a.text())).toEqual([
      'Pessoas',
      'Empresas',
    ]);
    expect(w.findAll('[data-grupo]').map(b => b.text())).toEqual([
      'Todos 280',
      'Clientes 120',
      'Falou há pouco 96',
      'Sumiu há 1 a 3 meses 42',
      'Sumiu há mais de 3 meses 71',
      'Nunca conversou 71',
      'Não quer mensagens 9',
    ]);
    expect(pilula(w, 'todos').attributes('aria-pressed')).toBe('true');
    expect(w.get(marca('explicacao-do-grupo')).text()).toBe('');
    expect(linhas(w)).toHaveLength(25);
    expect(textoDe(w, marca('mostrar-mais')).length).toBeGreaterThan(0);
    expect(w.text()).toContain('Mostrando 25 de 280');
  });

  it('cada linha tem caixa de marcar e o nome abre a ficha', async () => {
    const w = await montar();
    expect(w.findAll(marca('marcar'))).toHaveLength(25);
    await linhas(w)[0].get('button').trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: expect.any(Number) },
    });
  });

  it('"Mostrar mais" soma mais 25', async () => {
    const w = await montar();
    await w.get(marca('mostrar-mais')).trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(50);
    expect(w.text()).toContain('Mostrando 50 de 280');
  });

  it('trocar de grupo mostra a explicação dele, o total e volta à página 1', async () => {
    const w = await montar();
    await w.get(marca('mostrar-mais')).trigger('click');
    await assentar();
    await pilula(w, 'clientes').trigger('click');
    await assentar();
    expect(pilula(w, 'clientes').attributes('aria-pressed')).toBe('true');
    expect(w.get(marca('explicacao-do-grupo')).text()).toBe(
      'Quem já comprou de você.'
    );
    expect(linhas(w)).toHaveLength(25);
    expect(w.text()).toContain('Mostrando 25 de 120');
    expect(w.findAll('[data-selo="cliente"]')).toHaveLength(25);
  });

  it('a ação principal do herói seleciona o grupo de quem sumiu', async () => {
    const w = await montar();
    await w.get(marca('heroi-acao')).trigger('click');
    await assentar();
    expect(pilula(w, 'sumiu_1_a_3_meses').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(w.text()).toContain('Mostrando 25 de 42');
  });

  it('"Todos" e "Todas" não explicam nada; a linha só ocupa espaço quando tem texto', async () => {
    const w = await montar();
    const linha = w.get(marca('explicacao-do-grupo'));
    expect(linha.text()).toBe('');
    // Vazia, a linha não reserva altura nem margem (nada de faixa em branco).
    expect(linha.classes()).not.toContain('min-h-5');
    expect(linha.classes()).not.toContain('mt-3');
    await pilula(w, 'clientes').trigger('click');
    await assentar();
    expect(linha.text()).toBe('Quem já comprou de você.');
    expect(linha.classes()).toContain('mt-3');
    await w.get(marca('aba-empresas')).trigger('click');
    await assentar();
    expect(w.get(marca('explicacao-do-grupo')).text()).toBe('');
    await pilula(w, 'sem_pessoas').trigger('click');
    await assentar();
    expect(w.get(marca('explicacao-do-grupo')).text()).not.toBe('');
  });

  it('a barra de marcadas diz quem fica de fora, com os números separados', async () => {
    const w = await montar();
    await pilula(w, 'nao_quer_mensagens').trigger('click');
    await assentar();
    await w.get(`${marca('marcar')} input`).setValue(true);
    expect(textoDe(w, `${marca('barra')} p`)).toBe(
      '1 marcada · 1 pediu para não receber'
    );
  });

  it('na aba Empresas o herói fala de empresas e o botão marca o grupo delas', async () => {
    const w = await montar({ query: { aba: 'empresas' } });
    expect(textoDe(w, '[data-heroi-frase]')).toMatch(/empresas? (estão|está)/);
    expect(textoDe(w, marca('heroi-acao'))).toBe('Ver essas empresas');
    await w.get(marca('heroi-acao')).trigger('click');
    await assentar();
    expect(roteador.push).not.toHaveBeenCalled();
    expect(pilula(w, 'sem_conversa_3_meses').attributes('aria-pressed')).toBe(
      'true'
    );
  });

  it('fora da demonstração, com o servidor recusando, mostra o erro com "Tentar de novo" e o marcador do robô', async () => {
    const w = await montar({ demo: null });
    expect(textoDe(w, marca('erro'))).toContain(
      'Não consegui mostrar as pessoas.'
    );
    expect(w.get(`${marca('erro')} button`).exists()).toBe(true);
  });

  it('?demo=carregando deixa o esqueleto na tela, sem resposta', async () => {
    usarDemo.mockReturnValue('carregando');
    rota.name = 'relationships_home';
    rota.query = {};
    aberta = mount(ListaPage, COMO_NO_NAVEGADOR);
    await assentar();
    await avancar(5000);
    expect(aberta.find(marca('carregando')).exists()).toBe(true);
    expect(aberta.find(marca('erro')).exists()).toBe(false);
    expect(aberta.find(marca('heroi-acao')).exists()).toBe(false);
  });

  it('rola a pílula escolhida para dentro da fila, sem mexer na rolagem vertical', async () => {
    const rolou = vi.fn();
    const original = HTMLElement.prototype.scrollIntoView;
    HTMLElement.prototype.scrollIntoView = function rolar(opcoes) {
      rolou({ grupo: this.dataset.grupo, opcoes });
    };
    const w = await montar();
    expect(rolou).not.toHaveBeenCalled();
    await w.get(marca('heroi-acao')).trigger('click');
    await assentar();
    HTMLElement.prototype.scrollIntoView = original;
    expect(rolou).toHaveBeenCalledWith({
      grupo: 'sumiu_1_a_3_meses',
      opcoes: { inline: 'nearest', block: 'nearest' },
    });
  });

  it('de md em diante a fileira quebra em linhas: não há o que rolar', async () => {
    const rolou = vi.fn();
    const original = HTMLElement.prototype.scrollIntoView;
    HTMLElement.prototype.scrollIntoView = rolou;
    window.matchMedia = vi.fn().mockImplementation(consulta => ({
      matches: true,
      media: consulta,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }));
    const w = await montar();
    await w.get(marca('heroi-acao')).trigger('click');
    await assentar();
    HTMLElement.prototype.scrollIntoView = original;
    delete window.matchMedia;
    expect(rolou).not.toHaveBeenCalled();
  });

  it('"Trazer minha lista" discreto leva à tela de trazer', async () => {
    const w = await montar();
    await w.get(marca('heroi-trazer')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
    });
  });

  it('o grupo "Não quer mensagens" mostra o selo âmbar', async () => {
    const w = await montar();
    await pilula(w, 'nao_quer_mensagens').trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(9);
    expect(w.findAll('[data-selo="alerta"]')).toHaveLength(9);
    expect(w.find(marca('mostrar-mais')).exists()).toBe(false);
  });

  it('"Conversar" avisa o que vai acontecer (simulado)', async () => {
    const w = await montar();
    const nome = linhas(w)[0].get('button').text();
    await linhas(w)[0]
      .findAll('button')
      .find(b => b.text() === 'Conversar')
      .trigger('click');
    expect(useAlert).toHaveBeenCalledWith(`Abrindo a conversa com ${nome}`);
  });
});

describe('ListaPage: busca, ordem e filtros', () => {
  it('busca depois de 300 ms e mostra "Não achei ninguém com “…”." com Limpar busca', async () => {
    const w = await montar();
    await w.get(marca('busca')).setValue('zzzzqx');
    expect(linhas(w)).toHaveLength(25);
    await avancar(350);
    await assentar();
    expect(textoDe(w, marca('vazio'))).toContain(
      'Não achei ninguém com “zzzzqx”.'
    );
    const limpar = w
      .findAll(`${marca('vazio')} button`)
      .find(b => b.text() === 'Limpar busca');
    await limpar.trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(25);
    expect(w.get(marca('busca')).element.value).toBe('');
  });

  it('com busca, o número de cada pílula acompanha a lista', async () => {
    const w = await montar();
    const nome = linhas(w)[0].get('button').text();
    await w.get(marca('busca')).setValue(nome);
    await w.get(marca('busca')).trigger('keydown', { key: 'Enter' });
    await assentar();
    const mostradas = linhas(w).length;
    expect(pilula(w, 'todos').text()).toBe(`Todos ${mostradas}`);
    expect(w.text()).toContain(`Mostrando ${mostradas} de ${mostradas}`);
  });

  it('a região viva da página já existe vazia e anuncia o "não achei" depois', async () => {
    const w = await montar();
    const aviso = w.get(marca('aviso-da-lista'));
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('');
    await w.get(marca('busca')).setValue('zzzzqx');
    await w.get(marca('busca')).trigger('keydown', { key: 'Enter' });
    await assentar();
    expect(w.get(marca('aviso-da-lista')).element).toBe(aviso.element);
    expect(aviso.text()).toBe('Não achei ninguém com “zzzzqx”.');
    await w.get(marca('busca')).setValue('');
    await w.get(marca('busca')).trigger('keydown', { key: 'Enter' });
    await assentar();
    expect(aviso.text()).toBe('');
  });

  it('achou: filtra a lista pelo nome', async () => {
    const w = await montar();
    const nome = linhas(w)[0].get('button').text();
    await w.get(marca('busca')).setValue(nome);
    await w.get(marca('busca')).trigger('keydown', { key: 'Enter' });
    await assentar();
    expect(linhas(w).length).toBeGreaterThan(0);
    expect(linhas(w)[0].text()).toContain(nome);
  });

  it('ordenar por nome deixa a lista em ordem alfabética', async () => {
    const w = await montar();
    w.getComponent({ name: 'ChoiceSelect' }).vm.$emit(
      'update:modelValue',
      'nome'
    );
    await assentar();
    const nomes = linhas(w).map(l => l.get('button').text());
    expect(nomes).toEqual(
      [...nomes].sort((a, b) => a.localeCompare(b, 'pt-BR'))
    );
  });

  it('"Mais filtros" abre a gaveta com as opções da base e "Ver resultado" filtra', async () => {
    const w = await montar();
    await w.get(marca('mais-filtros')).trigger('click');
    await assentar();
    expect(w.find(marca('gaveta-filtros')).exists()).toBe(true);
    const campos = w
      .get(marca('gaveta-filtros'))
      .findAllComponents({ name: 'ChoiceSelect' });
    const cidades = campos[2].props('options');
    expect(cidades.length).toBeGreaterThan(1);
    campos[2].vm.$emit('update:modelValue', cidades[1].value);
    await w.vm.$nextTick();
    await w
      .get(marca('gaveta-filtros'))
      .findAll('button')
      .find(b => b.text() === 'Ver resultado')
      .trigger('click');
    await assentar();
    expect(w.find(marca('gaveta-filtros')).exists()).toBe(false);
    expect(textoDe(w, marca('mais-filtros'))).toBe('Mais filtros · 1');
    expect(w.text()).not.toContain('de 280');
  });

  it('filtro sem resultado diz "Não achei ninguém com esses filtros." e limpa', async () => {
    trocas.listar = (base, pedido) =>
      Object.values(pedido.filtros).some(Boolean)
        ? NINGUEM
        : base.listar(pedido);
    const w = await montar();
    await w.get(marca('mais-filtros')).trigger('click');
    await assentar();
    const campos = w
      .get(marca('gaveta-filtros'))
      .findAllComponents({ name: 'ChoiceSelect' });
    campos[3].vm.$emit('update:modelValue', 'ultimos_7');
    await w.vm.$nextTick();
    await w
      .get(marca('gaveta-filtros'))
      .findAll('button')
      .find(b => b.text() === 'Ver resultado')
      .trigger('click');
    await assentar();
    expect(textoDe(w, marca('vazio'))).toContain(
      'Não achei ninguém com esses filtros.'
    );
    await w
      .findAll(`${marca('vazio')} button`)
      .find(b => b.text() === 'Limpar filtros')
      .trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(25);
    expect(textoDe(w, marca('mais-filtros'))).toBe('Mais filtros');
  });
});

describe('ListaPage: marcar e agir em grupo', () => {
  const marcar = async (w, quantas) => {
    const caixas = w.findAll(`${marca('marcar')} input`);
    for (let i = 0; i < quantas; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      await caixas[i].setValue(true);
    }
  };

  it('a barra só aparece ao marcar e some ao fechar', async () => {
    const w = await montar();
    expect(w.find(marca('barra')).exists()).toBe(false);
    await marcar(w, 2);
    expect(textoDe(w, `${marca('barra')} p`)).toBe('2 marcadas');
    await w.get('button[aria-label="Desmarcar todas"]').trigger('click');
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('"Marcar todas as 280 deste grupo" marca o grupo inteiro, não só a página', async () => {
    const w = await montar();
    expect(w.text()).not.toContain('Marcar todas');
    await marcar(w, 1);
    expect(w.text()).toContain('Marcar todas as 280 deste grupo');
    const link = w
      .findAll('button')
      .find(b => b.text().startsWith('Marcar todas'));
    await link.trigger('click');
    await assentar();
    expect(textoDe(w, `${marca('barra')} p`)).toMatch(/^280 marcadas · /);
    expect(w.text()).not.toContain('Marcar todas');
  });

  it('trocar de grupo, buscar ou ordenar desmarca todo mundo', async () => {
    const w = await montar();
    await marcar(w, 3);
    await pilula(w, 'clientes').trigger('click');
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
    await marcar(w, 1);
    w.getComponent({ name: 'ChoiceSelect' }).vm.$emit(
      'update:modelValue',
      'nome'
    );
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('Mandar mensagem mostra quem recebe e quem fica de fora, e Continuar avisa a campanha (simulado)', async () => {
    const w = await montar();
    await pilula(w, 'nao_quer_mensagens').trigger('click');
    await assentar();
    await marcar(w, 3);
    await w.get(marca('mandar-mensagem')).trigger('click');
    expect(textoDe(w, marca('dialogo-mensagem'))).toBe(
      'Ninguém aqui pode receber: 3 pediram para não receber.'
    );
    expect(w.get('[data-confirmar]').text()).toBe('Entendi');
    expect(w.find('[data-cancelar]').exists()).toBe(false);
    await w.get('[data-confirmar]').trigger('click');
    expect(useAlert).not.toHaveBeenCalled();
    await pilula(w, 'clientes').trigger('click');
    await assentar();
    await marcar(w, 2);
    await w.get(marca('mandar-mensagem')).trigger('click');
    await w.get('[data-confirmar]').trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringMatching('Abrindo a campanha com')
    );
  });

  it('Criar cards: pergunta funil e etapa, cria e desmarca ao terminar', async () => {
    const w = await montar();
    await marcar(w, 2);
    await w.get(marca('criar-cards')).trigger('click');
    await assentar();
    expect(w.get(marca('dialogo-cards')).text()).toContain('Em qual funil?');
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(w.get(marca('dialogo-cards')).text()).toContain('cards criados.');
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('"Marcar todas" mostra que está carregando e não atende clique duplo', async () => {
    const pedidos = [];
    trocas.listarTodos = (base, pedido) =>
      new Promise(resolve => {
        pedidos.push(() => resolve(base.listarTodos(pedido)));
      });
    const w = await montar();
    await marcar(w, 1);
    const link = () =>
      w.findAll('button').find(b => b.text().startsWith('Marcar todas'));
    await link().trigger('click');
    await link().trigger('click');
    expect(pedidos).toHaveLength(1);
    expect(w.getComponent(MarcarTodas).props('carregando')).toBe(true);
    pedidos[0]();
    await assentar();
    expect(textoDe(w, `${marca('barra')} p`)).toMatch(/^280 marcadas · /);
  });

  it('"Marcar todas" não aplica a resposta se o grupo mudou durante a espera', async () => {
    const pedidos = [];
    trocas.listarTodos = (base, pedido) =>
      new Promise(resolve => {
        pedidos.push(() => resolve(base.listarTodos(pedido)));
      });
    const w = await montar();
    await marcar(w, 1);
    await w
      .findAll('button')
      .find(b => b.text().startsWith('Marcar todas'))
      .trigger('click');
    await pilula(w, 'clientes').trigger('click');
    await assentar();
    pedidos[0]();
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('depois de criar cards, recarrega a lista (e desmarca)', async () => {
    const chamadas = [];
    trocas.listar = (base, pedido) => {
      chamadas.push(pedido);
      return base.listar(pedido);
    };
    const w = await montar();
    await marcar(w, 2);
    const antes = chamadas.length;
    await w.get(marca('criar-cards')).trigger('click');
    await assentar();
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(w.find(marca('barra')).exists()).toBe(false);
    expect(chamadas.length).toBeGreaterThan(antes);
  });

  it('Etiqueta e Apagar abrem o diálogo certo', async () => {
    const w = await montar();
    await marcar(w, 2);
    await w.get(marca('etiqueta')).trigger('click');
    await assentar();
    expect(w.get(marca('dialogo-etiqueta')).text()).toContain('Qual etiqueta?');
    await w.get('[data-cancelar]').trigger('click');
    await w.get(marca('mais-acoes')).trigger('click');
    await w.get('[data-acao="apagar"]').trigger('click');
    expect(w.get('[data-dialogo-falso] h3').text()).toBe('Apagar 2 pessoas?');
    expect(w.get('[data-dialogo-falso] p').text()).toBe('Isto não volta.');
  });
});

describe('ListaPage: aba Empresas', () => {
  it('troca a URL para ?aba=empresas e mostra o mesmo desenho com os grupos de empresas', async () => {
    const w = await montar();
    await w.get(marca('aba-empresas')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({ query: { aba: 'empresas' } });
    await assentar();
    expect(w.get(marca('aba-empresas')).attributes('aria-selected')).toBe(
      'true'
    );
    expect(w.findAll('[data-grupo]').map(b => b.text())).toEqual([
      'Todas 38',
      'Com clientes 14',
      'Sem pessoas 5',
      'Sem conversa há 3 meses ' +
        w.get('[data-grupo="sem_conversa_3_meses"]').text().split(' ').pop(),
    ]);
    expect(linhas(w)).toHaveLength(25);
    expect(w.text()).toContain('Mostrando 25 de 38');
  });

  it('não tem caixa de marcar, barra nem "Mais filtros"', async () => {
    const w = await montar({ query: { aba: 'empresas' } });
    expect(w.findAll(marca('marcar'))).toHaveLength(0);
    expect(w.find(marca('mais-filtros')).exists()).toBe(false);
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('sair da página (a rota deixa de ser a lista) não dispara carga', async () => {
    const chamadas = [];
    trocas.listar = (base, pedido) => {
      chamadas.push(pedido);
      return base.listar(pedido);
    };
    await montar({ query: { aba: 'empresas' } });
    chamadas.length = 0;
    rota.name = 'relacionamentos_pessoa';
    rota.query = {};
    await assentar();
    expect(chamadas).toHaveLength(0);
  });

  it('clicar na empresa abre a ficha dela', async () => {
    const w = await montar({ query: { aba: 'empresas' } });
    await linhas(w)[0].get('button').trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_empresa',
      params: { companyId: expect.any(Number) },
    });
  });

  it('voltar para Pessoas tira o ?aba da URL e reabre o grupo padrão', async () => {
    const w = await montar({ query: { aba: 'empresas', demo: 'cheio' } });
    await w.get(marca('aba-pessoas')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({ query: { demo: 'cheio' } });
    await assentar();
    expect(pilula(w, 'todos').attributes('aria-pressed')).toBe('true');
    expect(w.findAll(marca('marcar'))).toHaveLength(25);
  });

  it('o grupo sem ninguém diz "Nenhuma empresa neste grupo agora."', async () => {
    const w = await montar({ query: { aba: 'empresas' } });
    await w.get(marca('busca')).setValue('zzzzqx');
    await w.get(marca('busca')).trigger('keydown', { key: 'Enter' });
    await assentar();
    expect(textoDe(w, marca('vazio'))).toContain(
      'Não achei nenhuma empresa com “zzzzqx”.'
    );
  });
});

describe('ListaPage: conta vazia, erro', () => {
  it('?demo=vazio mostra só o herói de trazer a lista, sem cartão nem abas', async () => {
    const w = await montar({ demo: 'vazio' });
    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      'Traga as pessoas com quem você já fala.'
    );
    expect(w.get(marca('vazio')).find('[data-heroi-frase]').exists()).toBe(
      true
    );
    expect(w.find('[data-vazio]').exists()).toBe(false);
    expect(w.text()).not.toContain('Ainda não tem ninguém aqui.');
    expect(w.find('[role="tablist"]').exists()).toBe(false);
    expect(w.find(marca('busca')).exists()).toBe(false);
    expect(linhas(w)).toHaveLength(0);
  });

  it('abaixo do convite, a conta vazia mostra a lista de exemplo apagada, sem nada para clicar', async () => {
    const w = await montar({ demo: 'vazio' });
    const exemplo = w.get(marca('linhas-de-exemplo'));
    expect(exemplo.attributes('aria-hidden')).toBe('true');
    expect(exemplo.findAll('[data-linha-de-exemplo]')).toHaveLength(5);
    expect(exemplo.text()).toContain('Sua lista vai ficar assim:');
    expect(exemplo.find('button, a, input').exists()).toBe(false);
    expect(w.findAll('button')).toHaveLength(1);
    const html = w.html();
    expect(html.indexOf('data-heroi-frase')).toBeLessThan(
      html.indexOf('linhas-de-exemplo')
    );
  });

  it('com gente na conta não há lista de exemplo', async () => {
    const w = await montar();
    expect(w.find(marca('linhas-de-exemplo')).exists()).toBe(false);
  });

  it('a conta vazia tem um botão só, "Trazer minha lista", e ele leva a trazer', async () => {
    const w = await montar({ demo: 'vazio' });
    const botoes = w
      .findAll('button')
      .filter(b => b.text() === 'Trazer minha lista');
    expect(botoes).toHaveLength(1);
    await w.get(marca('heroi-acao')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
    });
  });

  it('grupo sem ninguém diz "Ninguém neste grupo agora." e não oferece botão', async () => {
    trocas.listar = (base, pedido) =>
      pedido.grupo === 'nunca_conversou' ? NINGUEM : base.listar(pedido);
    const w = await montar();
    await pilula(w, 'nunca_conversou').trigger('click');
    await assentar();
    expect(textoDe(w, marca('vazio'))).toBe('Ninguém neste grupo agora.');
    expect(w.find(`${marca('vazio')} button`).exists()).toBe(false);
    expect(w.find(marca('mostrar-mais')).exists()).toBe(false);
  });

  it('mostra o erro com "Tentar de novo" quando a fonte falha', async () => {
    const w = await montar({ demo: null });
    expect(w.find(marca('carregando')).exists()).toBe(false);
    expect(textoDe(w, marca('erro'))).toContain(
      'Não consegui mostrar as pessoas.'
    );
    expect(w.get(marca('erro')).attributes('role')).toBe('alert');
    await w.get(`${marca('erro')} button`).trigger('click');
    await assentar();
    expect(w.find(marca('erro')).exists()).toBe(true);
  });
});

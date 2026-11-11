import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import { usarDemo } from '../../fonte/modoDemo';
import ListaPage from '../../pages/ListaPage.vue';

// A lista de Relacionamentos inteira (#2894), com a base fictícia e o texto de
// verdade em pt_BR: cheio, vazio, carregando, erro, ações e navegação.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./dialogoFalso')).TeleportFalso,
}));
vi.mock('../../fonte/modoDemo', () => ({ usarDemo: vi.fn() }));
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
// A demonstração sem o atraso de 300 ms (os testes esperam as respostas).
// `trocas.listar` deixa um teste responder a lista de um jeito só dele.
const trocas = vi.hoisted(() => ({ listar: null }));
vi.mock('../../fonte/listaFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    listaFonte: opcoes => {
      const base = real.listaFonte({ ...opcoes, atraso: 0 });
      return trocas.listar
        ? { ...base, listar: pedido => trocas.listar(base, pedido) }
        : base;
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

// Sem animação de saída: a barra e a gaveta somem na hora, como o teste espera.
const COMO_NO_NAVEGADOR = {
  attachTo: document.body,
  global: { stubs: { transition: true } },
};

const rota = useRoute();
const roteador = useRouter();
const marca = nome => `[data-relacionamentos="${nome}"]`;

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });
const assentar = async () => {
  await esperar(40);
  await flushPromises();
};

const abrir = async ({ demo = 'cheio', query = {} } = {}) => {
  usarDemo.mockReturnValue(demo);
  rota.query = query;
  const w = mount(ListaPage, COMO_NO_NAVEGADOR);
  await assentar();
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

afterEach(() => {
  aberta?.unmount();
  aberta = null;
  trocas.listar = null;
  vi.clearAllMocks();
});

const NINGUEM = { itens: [], total: 0, temMais: false };

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
      '42 pessoas não falam com você há mais de um mês.'
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
    expect(w.get('[aria-live="polite"]').text()).toBe(
      'Todo mundo que está aqui.'
    );
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
    expect(w.get('[aria-live="polite"]').text()).toBe(
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
    await esperar(350);
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
    expect(textoDe(w, `${marca('barra')} p`)).toBe('280 marcadas');
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
      'Ninguém vai receber. 3 ficam de fora: 3 pediram para não receber.'
    );
    await w.get('[data-cancelar]').trigger('click');
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
  it('?demo=vazio mostra o herói de trazer a lista e "Ainda não tem ninguém aqui."', async () => {
    const w = await montar({ demo: 'vazio' });
    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      'Traga as pessoas com quem você já fala.'
    );
    expect(textoDe(w, marca('vazio'))).toContain('Ainda não tem ninguém aqui.');
    expect(w.find('[role="tablist"]').exists()).toBe(false);
    expect(w.find(marca('busca')).exists()).toBe(false);
    expect(linhas(w)).toHaveLength(0);
  });

  it('os dois botões da conta vazia levam a trazer a lista', async () => {
    const w = await montar({ demo: 'vazio' });
    await w.get(marca('heroi-acao')).trigger('click');
    await w.get(`${marca('vazio')} button`).trigger('click');
    expect(roteador.push).toHaveBeenNthCalledWith(1, {
      name: 'relacionamentos_trazer',
    });
    expect(roteador.push).toHaveBeenNthCalledWith(2, {
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
      'Não consegui carregar. Tente de novo.'
    );
    expect(w.get(marca('erro')).attributes('role')).toBe('alert');
    await w.get(`${marca('erro')} button`).trigger('click');
    await assentar();
    expect(w.find(marca('erro')).exists()).toBe(true);
  });
});

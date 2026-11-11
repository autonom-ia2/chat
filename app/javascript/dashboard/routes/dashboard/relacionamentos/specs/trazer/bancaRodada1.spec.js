import { effectScope } from 'vue';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  aplicarConserto,
  aplicarDeixarDeFora,
  leituraDeExemplo,
} from '../../demo/trazer';
import { resumoAoVivo, totalDaLeitura } from '../../trazer/contagem';
import { ERROS, useTrazerLista } from '../../trazer/useTrazerLista';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';
import EtapasDoTopo from '../../components/trazer/EtapasDoTopo.vue';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';
import TelaPronto from '../../components/trazer/TelaPronto.vue';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';

// Rodada da banca (#2894): título curto com contadores, textos, estados da
// planilha por `?planilha=`, andamento, nomes nos problemas, Desfazer.
withFullI18n('pt_BR');

const estado = vi.hoisted(() => ({ demo: 'cheio', planilha: undefined }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: { planilha: estado.planilha } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerFonte: opcoes =>
      original.trazerFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      }),
  };
});

vi.setConfig({ testTimeout: 30000 });
const esperarPor = (verificacao, opcoes) =>
  vi.waitFor(verificacao, { timeout: 5000, ...opcoes });

const DialogoFalso = { template: '<div />' };
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const leitura = leituraDeExemplo('l1');
const conferir = (l = leitura, extra = {}) =>
  mount(TelaConferir, {
    attachTo: document.body,
    props: {
      leitura: l,
      resumo: resumoAoVivo(l),
      total: totalDaLeitura(l),
      ...extra,
    },
  });
const leituraDoContador = (w, chave) =>
  w.get(`[data-contador="${chave}"] .sr-only`).text();

beforeEach(() => {
  esquecerMemoriaDaDemo();
  estado.planilha = undefined;
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('B1. título curto e contadores', () => {
  it('o título é só "Achei 200 pessoas." e cada contador é um nó lido junto', () => {
    const w = conferir();
    expect(w.get('h1').text()).toBe('Achei 200 pessoas.');
    expect(w.get('h1').attributes('aria-live')).toBeUndefined();
    expect(leituraDoContador(w, 'NOVAS')).toBe('180 novas');
    expect(leituraDoContador(w, 'COMPLETADAS')).toBe('15 já estavam aqui');
    expect(leituraDoContador(w, 'PRECISAM')).toBe('5 precisam de você');
    const numero = w.get('[data-contador="NOVAS"] .tabular-nums');
    expect(numero.text()).toBe('180');
    expect(numero.attributes('aria-hidden')).toBe('true');
  });

  it('contador com zero não aparece', () => {
    const tudo = [14, 37, 62, 143, 171].reduce(
      (atual, linha) => aplicarConserto(atual, linha, 'x'),
      leitura
    );
    const w = conferir(tudo);
    expect(w.find('[data-contador="PRECISAM"]').exists()).toBe(false);
    expect(w.find('[data-contador="DEIXADAS"]').exists()).toBe(false);
    expect(leituraDoContador(w, 'NOVAS')).toBe('185 novas');
  });

  it('"precisam de você" é um botão que rola até o bloco e leva o foco ao título dele', async () => {
    const w = conferir();
    const contador = w.get('[data-contador="PRECISAM"] button');
    await contador.trigger('click');
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
    expect(document.activeElement).toBe(marca(w, 'precisam-titulo').element);
    expect(w.find('[data-contador="NOVAS"] button').exists()).toBe(false);
  });
});

describe('B2. nome inteiro na ficha', () => {
  it('o nome não trunca e reserva duas linhas em md+', async () => {
    const { default: Ficha } = await import(
      '../../components/trazer/FichaDeExemplo.vue'
    );
    const w = mount(Ficha, {
      props: { pessoa: { ...leitura.exemplos[1], cliente: true } },
    });
    const nome = w.get('h3');
    expect(nome.classes()).toEqual(
      expect.arrayContaining(['line-clamp-2', 'md:min-h-12'])
    );
    expect(nome.classes()).not.toContain('md:truncate');
  });
});

describe('B3. textos', () => {
  it('histórico: título novo', () => {
    const w = mount(HistoricoDeListas, {
      props: { listas: [] },
    });
    expect(w.get('h2').text()).toBe('Listas que você já trouxe');
  });

  it('Pronto cita o título novo', () => {
    const w = mount(TelaPronto, { props: { total: 195 } });
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer quando quiser, em “Listas que você já trouxe”.'
    );
  });

  it('coluna extra no mesmo formato: coluna, seta, "Informação nova"', () => {
    const w = mount(LinhaDeColuna, {
      props: { coluna: { nome: 'Situação', destino: 'informacao' } },
    });
    expect(w.text()).toContain('Situação');
    expect(w.text()).toContain('Informação nova');
    expect(w.find('.i-lucide-arrow-right').exists()).toBe(true);
    expect(w.text()).not.toContain('Vira uma informação');
  });
});

describe('B8. O que vou guardar', () => {
  const montar = () =>
    mount(OQueVouGuardar, { props: { colunas: leitura.colunas } });

  it('nasce fechado', () => {
    const w = montar();
    expect(w.get('h2 button').attributes('aria-expanded')).toBe('false');
    expect(w.get('ul').attributes('style')).toContain('display: none');
  });

  it('Mudar e Não guardar são botões da casa de 44 px, com rótulo claro', () => {
    const w = montar();
    const linha = w.get('[data-coluna="Aniversário"]');
    const botoes = linha.findAll('button');
    expect(botoes.map(b => b.text())).toEqual(['Mudar', 'Não guardar']);
    botoes.forEach(b => expect(b.classes()).toContain('min-h-11'));
    botoes.forEach(b =>
      expect(b.classes().join(' ')).toContain('bg-n-slate-9/10')
    );
    expect(botoes[0].attributes('aria-label')).toBe(
      'Mudar para onde vai a coluna Aniversário'
    );
    expect(linha.classes()).toContain('flex-wrap');
  });
});

describe('B4. estados da planilha em demonstração (?planilha=)', () => {
  const fonteDe = planilha =>
    trazerFonte({
      demo: 'cheio',
      planilha,
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
    });
  const montarTela = planilha => {
    const escopo = effectScope();
    const tela = escopo.run(() =>
      useTrazerLista({ fonte: fonteDe(planilha), avisar: vi.fn() })
    );
    return { tela, parar: () => escopo.stop() };
  };

  it('vazia e sem_contato viram erros do arquivo; nao_e_planilha vira erro de tipo', async () => {
    const vazia = montarTela('vazia');
    await vazia.tela.usarExemplo();
    expect(vazia.tela.erro.value).toBe(ERROS.VAZIA);
    const sem = montarTela('sem_contato');
    await sem.tela.usarExemplo();
    expect(sem.tela.erro.value).toBe(ERROS.SEM_CONTATO);
    const tipo = montarTela('nao_e_planilha');
    await tipo.tela.usarExemplo();
    expect(tipo.tela.erro.value).toBe(ERROS.TIPO);
  });

  it('valor desconhecido é ignorado: a planilha de exemplo lê normal', async () => {
    const { tela } = montarTela('qualquer-coisa');
    await tela.usarExemplo();
    expect(tela.erro.value).toBe(ERROS.NENHUM);
    expect(tela.leitura.value.resumo.total).toBe(200);
  });

  it('fonte real não conhece o parâmetro', () => {
    expect(trazerFonte({ demo: null, planilha: 'vazia' }).planilhaDeDemo).toBe(
      undefined
    );
  });

  it.each([
    ['tipo', ERROS.TIPO, 'Este arquivo não é uma planilha. Use Excel ou CSV.'],
    ['vazia', ERROS.VAZIA, 'Esta planilha está vazia.'],
    [
      'sem_contato',
      ERROS.SEM_CONTATO,
      'Não achei nome e telefone ou e-mail nesta planilha.',
    ],
  ])('Enviar mostra o erro %s com seletor estável', (tipo, erro, frase) => {
    const w = mount(TelaEnviar, { props: { erro } });
    const aviso = marca(w, 'erro-da-planilha');
    expect(aviso.text()).toBe(frase);
    expect(aviso.attributes('data-erro')).toBe(erro);
    expect(aviso.attributes('role')).toBe('alert');
  });

  it('Enviar mostra "Lendo sua planilha…" com seletor estável', () => {
    const w = mount(TelaEnviar, { props: { lendo: true } });
    expect(marca(w, 'lendo-planilha').text()).toBe('Lendo sua planilha…');
    expect(marca(w, 'carregando').findAll('.animate-pulse').length).toBe(3);
  });

  const abrirPagina = planilha => {
    estado.planilha = planilha;
    return mount(TrazerListaPage, {
      attachTo: document.body,
      global: { stubs: { RouterLink: RouterLinkStub, Dialog: DialogoFalso } },
    });
  };

  it.each([
    ['nao_e_planilha', 'Este arquivo não é uma planilha. Use Excel ou CSV.'],
    ['vazia', 'Esta planilha está vazia.'],
    ['sem_contato', 'Não achei nome e telefone ou e-mail nesta planilha.'],
  ])(
    'a página com ?planilha=%s já abre no estado, sem clique',
    async (planilha, frase) => {
      const w = abrirPagina(planilha);
      await esperarPor(() =>
        expect(marca(w, 'erro-da-planilha').text()).toBe(frase)
      );
      w.unmount();
    }
  );

  it('a página com ?planilha=lendo fica em "Lendo sua planilha…"', async () => {
    const w = abrirPagina('lendo');
    await esperarPor(() =>
      expect(marca(w, 'lendo-planilha').exists()).toBe(true)
    );
    w.unmount();
  });
});

describe('B4. ?demo=carregando no histórico', () => {
  it('o histórico nunca responde (esqueleto), e volta ao normal ao desligar', async () => {
    const { usarDemo } = await vi.importActual('../../fonte/modoDemo');
    usarDemo({ demo: 'carregando' }, true);
    try {
      const fonte = trazerFonte({
        demo: 'cheio',
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
      });
      const pendente = Symbol('pendente');
      const resultado = await Promise.race([
        fonte.historico(),
        new Promise(resolve => {
          setTimeout(() => resolve(pendente), 50);
        }),
      ]);
      expect(resultado).toBe(pendente);
    } finally {
      usarDemo({ demo: 'desligado' }, true);
    }
    const lista = await trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
    }).historico();
    expect(lista.length).toBeGreaterThan(0);
  });
});

describe('B5. pergunta de clientes nasce sem resposta', () => {
  it('nenhuma opção marcada e Continuar desligado', () => {
    const w = mount(PerguntaDaVez, {
      props: {
        pergunta: { id: 'clientes' },
        respostas: {},
        colunas: leitura.colunas,
        podeContinuar: false,
      },
    });
    expect(w.findAll('[aria-checked="true"]')).toHaveLength(0);
    expect(w.findAll('[role="radio"]').length).toBe(3);
    expect(marca(w, 'continuar').attributes('disabled')).toBeDefined();
  });

  it('na tela, depois de ler a planilha, nada vem marcado e o composable não deixa continuar', async () => {
    const escopo = effectScope();
    const tela = escopo.run(() =>
      useTrazerLista({
        fonte: trazerFonte({
          demo: 'cheio',
          carregarDemo: () => import('../../demo/trazer.js'),
          atraso: 0,
          atrasoDaLeitura: 0,
        }),
        avisar: vi.fn(),
      })
    );
    await tela.usarExemplo();
    expect(tela.respostas.value).toEqual({});
    expect(tela.podeContinuar.value).toBe(false);
    escopo.stop();
  });
});

describe('E2. contadores com a mesma caixa', () => {
  it('o botão não traz padding, margem nem borda próprios; três em grid-cols-3, quatro em 2×2', () => {
    const w = conferir();
    const botao = w.get('[data-contador="PRECISAM"] button');
    expect(botao.classes()).toEqual(
      expect.arrayContaining(['p-0', 'm-0', 'border-0', 'min-h-11'])
    );
    const caixaDosOutros = w.get('[data-contador="NOVAS"] > div');
    ['p-0', 'm-0', 'min-h-11', 'justify-start'].forEach(classe => {
      expect(caixaDosOutros.classes()).toContain(classe);
      expect(botao.classes()).toContain(classe);
    });
    const lista = marca(w, 'contadores');
    expect(lista.classes()).toContain('grid-cols-3');
    const quatro = conferir(aplicarDeixarDeFora(leitura, 62));
    expect(marca(quatro, 'contadores').classes()).toContain('grid-cols-2');
  });
});

describe('B6. andamento e etapas do topo', () => {
  it('a largura da barra troca de uma vez, sem classe de transição', () => {
    const w = mount(TelaPronto, {
      props: { trazendo: true, porcentagem: 50 },
    });
    const barra = w.get('[role="progressbar"] > div');
    expect(barra.classes()).toContain('w-[50%]');
    expect(barra.classes().join(' ')).not.toContain('transition');
    expect(barra.classes().join(' ')).not.toContain('duration-');
    expect(barra.classes()).not.toContain('duration-500');
  });

  it('o passo 3 é "Trazendo" enquanto traz e "Pronto" quando termina', () => {
    const trazendo = mount(EtapasDoTopo, {
      props: { atual: 'pronto', trazendo: true },
    });
    const atual = trazendo.get('[aria-current="step"]');
    expect(atual.text()).toContain('Trazendo');
    expect(atual.text()).not.toContain('Pronto');
    const pronto = mount(EtapasDoTopo, { props: { atual: 'pronto' } });
    expect(pronto.get('[aria-current="step"]').text()).toContain('Pronto');
    const antes = mount(EtapasDoTopo, {
      props: { atual: 'conferir', trazendo: true },
    });
    expect(antes.get('[data-etapa="pronto"]').text()).toContain('Pronto');
  });
});

describe('B7. problemas com o nome da pessoa', () => {
  const problema = linha => leitura.problemas.find(p => p.linha === linha);
  const montar = linha =>
    mount(ProblemaDaLinha, { props: { problema: problema(linha) } });

  it('o nome vem na frente e a linha vai como apoio em cinza', () => {
    const w = montar(14);
    expect(w.text()).toContain('Tadeu Imbirussu: falta um número no telefone');
    expect(w.text()).toContain('Linha 14 da planilha');
    expect(w.get('p').classes()).toContain('font-semibold');
  });

  it('sem nome usa o contato que houver', () => {
    expect(montar(62).text()).toContain('+55 11 95412-0062: falta o nome');
  });

  it('sem nome nem contato cai na linha', () => {
    const w = mount(ProblemaDaLinha, {
      props: {
        problema: { linha: 9, tipo: 'nome', nome: '', estado: 'aberto' },
      },
    });
    expect(w.text()).toContain('Linha 9: falta o nome');
  });

  it('duplicada: título com o nome e cartões mostrando a diferença', async () => {
    const w = montar(143);
    expect(w.text()).toContain(
      'Paulo Hortêncio aparece duas vezes. Qual fica?'
    );
    expect(w.text()).toContain('Linhas 88 e 143 da planilha');
    const a = w.get('[data-opcao="88"]');
    const b = w.get('[data-opcao="143"]');
    expect(a.text()).toContain('Ficar com a linha 88');
    // Telefone e e-mail em linhas separadas; o e-mail só quebra no "@".
    const linhasDeA = a.findAll('span').map(s => s.text());
    expect(linhasDeA).toContain('+55 11 94410-0088');
    expect(a.html()).toContain('paulo.hortencio<wbr>@exemplo.com.br');
    expect(b.findAll('span').map(s => s.text())).toEqual([
      'Ficar com a linha 143',
      '+55 11 94410-0143',
      'sem e-mail',
      'Ficar com esta',
      '',
    ]);
    expect(a.classes()).toEqual(
      expect.arrayContaining([
        'min-h-11',
        'border',
        'border-n-weak',
        'rounded-xl',
        'focus-visible:outline-2',
      ])
    );
    expect(a.classes().join(' ')).toContain('hover:enabled:bg-');
    expect(w.text()).not.toContain('Na planilha:');
    expect(a.element.parentElement.className).toContain('sm:grid-cols-2');
    await b.trigger('click');
    expect(w.emitted('guardar')).toEqual([[143, 143]]);
  });

  it('as duas ações são botões da casa de 44 px, alinhados', () => {
    const w = montar(37);
    const salvar = w.findAll('button').find(b => b.text() === 'Salvar');
    const deixar = marca(w, 'deixar-de-fora');
    [salvar, deixar].forEach(b => expect(b.classes()).toContain('min-h-11'));
    expect(deixar.classes().join(' ')).toContain('bg-n-slate-9/10');
    expect(salvar.element.parentElement).toBe(deixar.element.parentElement);
  });

  it('B10. Salvar não ganha opacidade extra: só o desligado padrão do Button', () => {
    const w = montar(37);
    const salvar = w.findAll('button').find(b => b.text() === 'Salvar');
    expect(salvar.attributes('disabled')).toBeDefined();
    const extras = salvar.classes().filter(c => c.startsWith('opacity-'));
    expect(extras).toEqual([]);
    expect(salvar.classes().join(' ')).not.toContain('faded');
  });

  it('o bloco diz que quem ficar sem resolver fica de fora, e o botão já faz isso', () => {
    const w = mount(PrecisamDeVoce, {
      props: { problemas: leitura.problemas },
    });
    expect(w.text()).toContain('Quem ficar sem resolver fica de fora.');
    // 195 = 180 novas + 15 completadas: as 5 abertas não entram na conta.
    expect(totalDaLeitura(leitura)).toBe(195);
    expect(totalDaLeitura(aplicarDeixarDeFora(leitura, 62))).toBe(195);
  });
});

describe('B9. diálogo Desfazer', () => {
  const DialogFalso = {
    props: ['title'],
    template:
      '<div data-dialog><h3>{{ title }}</h3><slot /><slot name="footer" /></div>',
  };
  const montar = props =>
    mount(DialogoDesfazer, {
      props,
      global: { stubs: { Dialog: DialogFalso } },
    });

  it('o título diz o nome da lista', () => {
    const w = montar({
      arquivo: 'Clientes 2025.xlsx',
      previa: { tira: 1, devolve: 0, receberamCampanha: 0 },
    });
    expect(w.get('[data-relacionamentos="titulo-do-dialogo"]').text()).toBe(
      'Desfazer “Clientes 2025.xlsx”?'
    );
  });

  it('sem nome volta ao título geral', () => {
    const w = montar({ previa: null });
    expect(w.get('[data-relacionamentos="titulo-do-dialogo"]').text()).toBe(
      'Desfazer esta lista?'
    );
  });

  it('o aviso da campanha usa o tom de aviso legível, claro e escuro', () => {
    const w = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 1, devolve: 0, receberamCampanha: 3 },
    });
    const aviso = w
      .findAll('p')
      .find(p => p.text().includes('já receberam uma campanha'));
    expect(aviso.classes()).toEqual(
      expect.arrayContaining(['text-n-amber-12', 'bg-n-amber-3'])
    );
    expect(aviso.classes()).not.toContain('text-n-amber-11');
  });
});

describe('T1. Desfazer sem prazo', () => {
  const lista = (id, situacao) => ({
    id,
    arquivo: `${id}.xlsx`,
    quando: Date.UTC(2020, 0, 1),
    quem: 'Marina Dornelaz',
    total: 5,
    situacao,
    porcentagem: 100,
  });

  it('só a lista pronta tem Desfazer, por mais antiga que seja; trazendo e desfeita não', () => {
    const w = mount(HistoricoDeListas, {
      props: {
        listas: [
          lista('a', 'pronto'),
          lista('b', 'trazendo'),
          lista('c', 'desfeito'),
        ],
      },
    });
    const tem = id =>
      w.find(`[data-lista="${id}"] [data-relacionamentos="desfazer"]`).exists();
    expect([tem('a'), tem('b'), tem('c')]).toEqual([true, false, false]);
    expect(w.text()).not.toContain('Prazo');
    expect(w.text()).not.toContain('até');
  });

  it('os textos de prazo saíram do catálogo', async () => {
    const pt = (
      await import('dashboard/i18n/locale/pt_BR/relacionamentosTrazer.json')
    ).default.RELACIONAMENTOS_TRAZER;
    expect(pt.HISTORICO.ATE).toBeUndefined();
    expect(pt.HISTORICO.PRAZO_ACABOU).toBeUndefined();
    expect(pt.CONFERIR.CONTADOR.IR_PARA_PRECISAM).toBeUndefined();
    expect(pt.CONFERIR.SOSSEGO).toBe('Você pode desfazer quando quiser.');
  });
});

describe('T2. achados da revisão', () => {
  it('?planilha= só vale com a demonstração ligada', async () => {
    estado.demo = null;
    estado.planilha = 'vazia';
    const w = mount(TrazerListaPage, {
      attachTo: document.body,
      global: {
        stubs: { RouterLink: RouterLinkStub, Dialog: { template: '<div />' } },
      },
    });
    await vi.waitFor(() =>
      expect(marca(w, 'soltar-arquivo').exists()).toBe(true)
    );
    expect(marca(w, 'erro-da-planilha').exists()).toBe(false);
    expect(marca(w, 'lendo-planilha').exists()).toBe(false);
    estado.demo = 'cheio';
    w.unmount();
  });

  it('os contadores avisam a mudança por uma região viva só', () => {
    const w = conferir();
    expect(marca(w, 'contadores').attributes('aria-live')).toBe('polite');
    expect(w.findAll('[aria-live]')).toHaveLength(1);
  });

  it('exemplos com o mesmo nome não repetem a chave do v-for', () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const repetida = {
      ...leitura,
      exemplos: [leitura.exemplos[0], leitura.exemplos[0], leitura.exemplos[1]],
    };
    const w = conferir(repetida);
    expect(w.findAll('[data-ficha-de-exemplo]')).toHaveLength(3);
    const duplicadas = aviso.mock.calls.filter(chamada =>
      String(chamada[0]).includes('Duplicate keys')
    );
    expect(duplicadas).toEqual([]);
    aviso.mockRestore();
  });

  it('?planilha=lendo nunca termina, nem com horas de relógio', async () => {
    vi.useFakeTimers();
    try {
      const fonte = trazerFonte({
        demo: 'cheio',
        planilha: 'lendo',
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
      });
      let terminou = false;
      fonte.ler(null).then(
        () => {
          terminou = true;
        },
        () => {
          terminou = true;
        }
      );
      await vi.advanceTimersByTimeAsync(3 * 60 * 60 * 1000);
      expect(terminou).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });
});

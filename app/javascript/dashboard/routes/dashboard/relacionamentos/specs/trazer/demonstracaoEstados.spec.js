import { effectScope } from 'vue';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { ERROS, useTrazerLista } from '../../trazer/useTrazerLista';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';
// #2894 — os estados que a demonstração mostra sem arquivo de verdade:
// `?planilha=` (os erros do envio e o "lendo") e `?demo=carregando` (o
// histórico no esqueleto). Só valem com a demonstração ligada.
withFullI18n('pt_BR');

const estado = vi.hoisted(() => ({ demo: 'cheio', planilha: undefined }));

// #2897 — a conta destes testes não tem a carteira de seguros: a tela é a das
// listas, sem a pergunta dos seguros.
vi.mock('../../carteira/useContaDeSeguros', async () => {
  const { ref } = await import('vue');
  return { useContaDeSeguros: () => ref(false) };
});

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

beforeEach(() => {
  esquecerMemoriaDaDemo();
  estado.planilha = undefined;
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('estados da planilha em demonstração (?planilha=)', () => {
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
    expect(tela.leitura.value.resumo.total).toBe(203);
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
      'Não achei nesta planilha telefone nem e-mail que eu consiga usar. O telefone precisa ser celular, com o DDD junto do número, na mesma coluna. Arrume a planilha e envie de novo.',
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
    [
      'sem_contato',
      'Não achei nesta planilha telefone nem e-mail que eu consiga usar. O telefone precisa ser celular, com o DDD junto do número, na mesma coluna. Arrume a planilha e envie de novo.',
    ],
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

describe('?demo=carregando no histórico', () => {
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

describe('?planilha= fora da demonstração e o "lendo" que não termina', () => {
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

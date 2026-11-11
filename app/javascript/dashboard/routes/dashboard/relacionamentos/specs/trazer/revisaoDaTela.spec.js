import { effectScope } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  leituraDeExemplo,
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarReabrir,
  quemTrouxeNaDemo,
} from '../../demo/trazer';
import * as contagem from '../../trazer/contagem';
import { ETAPAS } from '../../trazer/etapas';
import {
  INTERVALO_DO_ANDAMENTO_MS,
  useTrazerLista,
} from '../../trazer/useTrazerLista';
import {
  INTERVALO_DO_HISTORICO_MS,
  useHistoricoDeListas,
} from '../../trazer/useHistoricoDeListas';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import TelaPronto from '../../components/trazer/TelaPronto.vue';
import FichaDeExemplo from '../../components/trazer/FichaDeExemplo.vue';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
import SoltarArquivo from '../../components/trazer/SoltarArquivo.vue';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';

// Achados da revisão da tela "Trazer minha lista" (#2894): foco e anúncio ao
// resolver uma linha, troca de coluna, corridas nos relógios, e-mail único,
// nomes inventados e "Voltar atrás".
withFullI18n('pt_BR');

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
const leitura = leituraDeExemplo('l1');
const problemaDe = (l, linha) => l.problemas.find(p => p.linha === linha);

afterEach(() => {
  document.body.innerHTML = '';
});

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

describe('1. foco e anúncio ao resolver uma linha', () => {
  const montar = (l = leitura) =>
    mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: { problemas: l.problemas },
    });
  const resolver = async (w, nova) => {
    await w.setProps({ problemas: nova.problemas });
    await flushPromises();
  };

  it('a região viva existe desde o início, vazia, e a seção não é aria-live', () => {
    const w = montar();
    const aviso = marca(w, 'anuncio-precisam');
    expect(aviso.exists()).toBe(true);
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('');
    expect(
      marca(w, 'precisam-de-voce').attributes('aria-live')
    ).toBeUndefined();
  });

  it('resolver a linha 14 leva o foco ao campo da linha 37 e anuncia', async () => {
    const w = montar();
    await resolver(w, aplicarConserto(leitura, 14, 'x'));
    expect(document.activeElement).toBe(
      w.get('[data-linha="37"] input').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe('Linha 14: pronto');
  });

  it('deixar de fora anuncia e leva ao próximo, que pode ser de escolha', async () => {
    const w = montar();
    await resolver(w, aplicarDeixarDeFora(leitura, 62));
    expect(document.activeElement).toBe(
      w.get('[data-linha="143"] button').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe(
      'Linha 62: deixada de fora'
    );
  });

  it('resolver a última volta ao primeiro problema ainda aberto', async () => {
    const w = montar();
    await resolver(w, aplicarDeixarDeFora(leitura, 171));
    expect(document.activeElement).toBe(
      w.get('[data-linha="14"] input').element
    );
  });

  it('sem problema aberto, o foco vai ao título da seção', async () => {
    const w = montar();
    const tudo = [14, 37, 62, 143, 171].reduce(
      (atual, linha) => aplicarConserto(atual, linha, 'x'),
      leitura
    );
    await resolver(w, tudo);
    expect(document.activeElement).toBe(marca(w, 'precisam-titulo').element);
    expect(marca(w, 'precisam-titulo').text()).toBe('Tudo resolvido');
  });

  it('a linha resolvida não nasce com role="status" própria', async () => {
    const w = montar();
    await resolver(w, aplicarConserto(leitura, 62, 'Ana'));
    expect(w.get('[data-linha="62"]').find('[role="status"]').exists()).toBe(
      false
    );
  });

  it('voltar atrás leva o foco ao primeiro campo da linha reaberta e anuncia', async () => {
    const resolvida = aplicarConserto(leitura, 62, 'Ana');
    const w = montar(resolvida);
    await resolver(w, aplicarReabrir(resolvida, 62));
    expect(document.activeElement).toBe(
      w.get('[data-linha="62"] input').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe(
      'Linha 62: voltou para você conferir'
    );
  });

  it('mudança sem linha resolvida não mexe no foco nem no aviso', async () => {
    const w = montar();
    await resolver(w, { problemas: [...leitura.problemas] });
    expect(marca(w, 'anuncio-precisam').text()).toBe('');
    expect(document.activeElement).toBe(document.body);
  });
});

describe('5. um só emailValido', () => {
  it('contagem não tem mais o seu e o campo usa o da ficha', async () => {
    expect(contagem.emailValido).toBeUndefined();
    const w = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(leitura, 37) },
    });
    await w.get('input').setValue('a@b..com');
    expect(botao(w, 'Salvar').attributes('disabled')).toBeDefined();
    await w.get('input').setValue('  ana@exemplo.com.br ');
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')).toEqual([[37, 'ana@exemplo.com.br']]);
  });
});

describe('2. Trocar a coluna', () => {
  // O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
  beforeEach(() => {
    Element.prototype.scrollIntoView = vi.fn();
  });
  const montar = () =>
    mount(LinhaDeColuna, {
      attachTo: document.body,
      props: { coluna: { nome: 'Cel', destino: 'telefone' } },
    });
  const trocar = async w => {
    await botao(w, 'Mudar').trigger('click');
    await flushPromises();
  };
  const escolha = w => w.get('[role="combobox"]');

  it('abre a escolha com o foco nela', async () => {
    const w = montar();
    await trocar(w);
    expect(document.activeElement).toBe(escolha(w).element);
    expect(escolha(w).attributes('aria-expanded')).toBe('true');
    expect(botao(w, 'Mudar')).toBeUndefined();
  });

  it('fechar com Esc sem escolher volta ao Trocar, com o foco nele', async () => {
    const w = montar();
    await trocar(w);
    await escolha(w).trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(w.find('[role="combobox"]').exists()).toBe(false);
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
    expect(w.emitted('trocar')).toBeUndefined();
  });

  it('escolher a mesma opção também volta ao Trocar', async () => {
    const w = montar();
    await trocar(w);
    await w.get('[role="option"][data-value="telefone"]').trigger('click');
    await flushPromises();
    expect(botao(w, 'Mudar')).toBeDefined();
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
    expect(w.emitted('trocar')).toBeUndefined();
  });

  it('escolher outra opção emite a troca e volta ao Trocar', async () => {
    const w = montar();
    await trocar(w);
    await w.get('[role="option"][data-value="email"]').trigger('click');
    await flushPromises();
    expect(w.emitted('trocar')).toEqual([['Cel', 'email']]);
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
  });

  it('clicar fora fecha e volta ao Trocar sem roubar o foco de outro lugar', async () => {
    const outro = document.createElement('input');
    document.body.append(outro);
    const w = montar();
    await trocar(w);
    outro.focus();
    await flushPromises();
    expect(document.activeElement).toBe(outro);
    expect(botao(w, 'Mudar')).toBeDefined();
  });
});

describe('3. relógio do andamento: geração e desmontagem', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const fonteComConsultaEmVoo = () => {
    const respostas = [];
    return {
      respostas,
      ler: async () => ({
        id: 'l1',
        arquivo: 'a.csv',
        perguntas: [],
        problemas: [],
        resumo: { novas: 3, completadas: 0 },
      }),
      trazer: vi.fn(async () => ({ trazidaId: 't1' })),
      andamento: vi.fn(
        () =>
          new Promise(resolve => {
            respostas.push(resolve);
          })
      ),
    };
  };
  const montar = fonte => {
    const escopo = effectScope();
    const tela = escopo.run(() => useTrazerLista({ fonte, avisar: vi.fn() }));
    return { tela, parar: () => escopo.stop() };
  };

  it('recomecar com consulta em voo: a resposta velha não reagenda o relógio', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    tela.recomecar();
    fonte.respostas[0]({ porcentagem: 40, situacao: 'trazendo', total: 3 });
    await trazendo;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 3);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    expect(tela.porcentagem.value).toBe(0);
  });

  it('recomecar com consulta em voo: a resposta "pronto" não dispara o término', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    tela.recomecar();
    fonte.respostas[0]({ porcentagem: 100, situacao: 'pronto', total: 3 });
    await trazendo;
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.totalTrazido.value).toBe(0);
  });

  it('um novo trazer depois de recomecar ignora a consulta velha', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela } = montar(fonte);
    await tela.usarExemplo();
    const primeira = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    tela.recomecar();
    await tela.usarExemplo();
    const segunda = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    fonte.respostas[0]({ porcentagem: 100, situacao: 'pronto', total: 99 });
    await primeira;
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    expect(tela.totalTrazido.value).toBe(0);
    fonte.respostas[1]({ porcentagem: 50, situacao: 'trazendo', total: 3 });
    await segunda;
    expect(tela.porcentagem.value).toBe(50);
  });

  it('desmontar com consulta em voo: nada mais é agendado nem mudado', async () => {
    const fonte = fonteComConsultaEmVoo();
    const { tela, parar } = montar(fonte);
    await tela.usarExemplo();
    const trazendo = tela.trazer();
    await vi.advanceTimersByTimeAsync(0);
    parar();
    fonte.respostas[0]({ porcentagem: 40, situacao: 'trazendo', total: 3 });
    await trazendo;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS * 3);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('4. histórico: um só relógio, resposta velha descartada', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const lista = (id, situacao) => ({ id, situacao, porcentagem: 10 });
  const montar = fonte => {
    const escopo = effectScope();
    const historico = escopo.run(() =>
      useHistoricoDeListas({ fonte, avisar: vi.fn() })
    );
    return { historico, parar: () => escopo.stop() };
  };
  const fonteDeFila = () => {
    const respostas = [];
    return {
      respostas,
      historico: vi.fn(
        () =>
          new Promise(resolve => {
            respostas.push(resolve);
          })
      ),
    };
  };

  it('duas cargas ao mesmo tempo deixam um único temporizador', async () => {
    const fonte = fonteDeFila();
    const { historico } = montar(fonte);
    const a = historico.carregar();
    const b = historico.carregar({ silencioso: true });
    fonte.respostas[0]([lista('x', 'trazendo')]);
    fonte.respostas[1]([lista('x', 'trazendo')]);
    await Promise.all([a, b]);
    expect(vi.getTimerCount()).toBe(1);
  });

  it('a resposta velha não sobrescreve a nova', async () => {
    const fonte = fonteDeFila();
    const { historico } = montar(fonte);
    const velha = historico.carregar();
    const nova = historico.carregar({ silencioso: true });
    fonte.respostas[1]([lista('novo', 'pronto')]);
    await nova;
    fonte.respostas[0]([lista('velho', 'trazendo')]);
    await velha;
    expect(historico.listas.value.map(l => l.id)).toEqual(['novo']);
    expect(historico.carregando.value).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('depois de sair da tela, carregar não pede nada', async () => {
    const fonte = fonteDeFila();
    const { historico, parar } = montar(fonte);
    parar();
    await historico.carregar();
    expect(fonte.historico).not.toHaveBeenCalled();
  });

  it('resposta que chega depois de sair não agenda nada', async () => {
    const fonte = fonteDeFila();
    const { historico, parar } = montar(fonte);
    const carga = historico.carregar();
    parar();
    fonte.respostas[0]([lista('x', 'trazendo')]);
    await carga;
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_HISTORICO_MS * 3);
    expect(fonte.historico).toHaveBeenCalledTimes(1);
  });
});

describe('6. nomes da planilha de exemplo são inventados', () => {
  const NOMES_QUE_PARECEM_REAIS = [
    'Marina Teixeira',
    'Otávio Lacerda',
    'Sofia Brandão',
    'Tadeu Marques',
    'Rita Nogueira',
    'Paulo Siqueira',
    'Helena Barreto',
    'Marina Alves',
  ];

  it('nenhum nome nem e-mail do demo é de gente comum', () => {
    const texto = JSON.stringify([leitura, quemTrouxeNaDemo()]);
    NOMES_QUE_PARECEM_REAIS.forEach(nome => {
      expect(texto).not.toContain(nome);
    });
    leitura.exemplos.forEach(e => {
      expect(e.email.endsWith('@exemplo.com.br')).toBe(true);
      expect(e.telefone.startsWith('+55 11 9')).toBe(true);
      expect(e.telefone.at(-5)).toBe('-');
      expect(e.telefone.slice(-4, -2)).toBe('00');
    });
  });
});

describe('8. Voltar atrás', () => {
  it('linha pronta ou deixada de fora ganha o botão, que emite a linha', async () => {
    const guardada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarConserto(leitura, 62, 'Ana'), 62) },
    });
    await marca(guardada, 'voltar-atras').trigger('click');
    expect(guardada.emitted('reabrir')).toEqual([[62]]);
    expect(marca(guardada, 'voltar-atras').text()).toBe('Voltar atrás');
    const deixada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarDeixarDeFora(leitura, 62), 62) },
    });
    expect(marca(deixada, 'voltar-atras').exists()).toBe(true);
  });

  it('linha ainda aberta não tem Voltar atrás', () => {
    const w = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(leitura, 62) },
    });
    expect(marca(w, 'voltar-atras').exists()).toBe(false);
  });

  it('a tela Conferir repassa o reabrir', async () => {
    const resolvida = aplicarDeixarDeFora(leitura, 62);
    const w = mount(TelaConferir, {
      props: {
        leitura: resolvida,
        resumo: contagem.resumoAoVivo(resolvida),
        total: contagem.totalDaLeitura(resolvida),
      },
    });
    await w.getComponent(ProblemaDaLinha).vm.$emit('reabrir', 62);
    expect(w.emitted('reabrir')).toEqual([[62]]);
  });

  it('aplicarReabrir devolve a linha aberta, sem o valor corrigido', () => {
    const resolvida = aplicarConserto(leitura, 62, 'Ana');
    const nova = aplicarReabrir(resolvida, 62);
    expect(problemaDe(nova, 62)).toMatchObject({ estado: 'aberto' });
    expect(problemaDe(nova, 62).corrigido).toBeUndefined();
    expect(contagem.contarProblemas(nova.problemas).abertos).toBe(5);
    expect(contagem.totalDaLeitura(nova)).toBe(195);
  });

  describe('na fonte e na tela', () => {
    beforeEach(() => esquecerMemoriaDaDemo());
    const fonte = () =>
      trazerFonte({
        demo: 'cheio',
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      });

    it('fonte.reabrir refaz os números', async () => {
      const f = fonte();
      const { id } = await f.ler(null);
      await f.deixarDeFora(id, 62);
      const nova = await f.reabrir(id, 62);
      expect(problemaDe(nova, 62).estado).toBe('aberto');
      expect(contagem.resumoAoVivo(nova).precisamDeVoce).toBe(5);
    });

    it('fonte real diz FONTE_REAL_PENDENTE', async () => {
      await expect(
        trazerFonte({ demo: null }).reabrir('x', 1)
      ).rejects.toMatchObject({ name: 'FONTE_REAL_PENDENTE' });
    });

    it('useTrazerLista.reabrir troca a leitura e volta a contar', async () => {
      const escopo = effectScope();
      const tela = escopo.run(() =>
        useTrazerLista({ fonte: fonte(), avisar: vi.fn() })
      );
      await tela.usarExemplo();
      await tela.deixarDeFora(62);
      expect(tela.resumo.value.deixadas).toBe(1);
      await tela.reabrir(62);
      expect(tela.resumo.value.deixadas).toBe(0);
      expect(tela.resumo.value.precisamDeVoce).toBe(5);
      escopo.stop();
    });
  });
});

describe('V1/V3. contêiner centrado e respiro embaixo', () => {
  it('a página e o conteúdo têm a mesma largura em toda etapa e folga para o menu', async () => {
    // jsdom não mede largura: confere as classes do contêiner no arquivo.
    const texto = (await import('../../pages/TrazerListaPage.vue?raw')).default;
    const inicio = texto.indexOf('data-relacionamentos="trazer-conteudo"');
    const conteudo = texto.slice(inicio, texto.indexOf('>', inicio));
    ['w-full', 'max-w-3xl', 'mx-auto', 'pb-24', 'md:pb-10'].forEach(classe => {
      expect(conteudo).toContain(classe);
    });
    expect(texto).not.toContain('max-w-4xl');
  });
});

describe('V2. ficha: nome inteiro, selo embaixo', () => {
  const pessoa = {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: '',
    cliente: true,
  };

  it('o nome não é cortado e o selo fica na coluna do nome', () => {
    const w = mount(FichaDeExemplo, { props: { pessoa } });
    const nome = w.get('h3');
    expect(nome.classes()).not.toContain('truncate');
    expect(
      nome.element.parentElement.contains(w.get('[data-selo]').element)
    ).toBe(true);
  });

  it('o e-mail tem title com o endereço inteiro', () => {
    const w = mount(FichaDeExemplo, { props: { pessoa } });
    expect(w.find(`[title="${pessoa.email}"]`).exists()).toBe(true);
  });
});

describe('V4. soltar arquivo', () => {
  it('foco por teclado tem anel e arrastar por cima enche a borda e o fundo', async () => {
    const w = mount(SoltarArquivo);
    const area = marca(w, 'soltar-arquivo');
    expect(area.classes()).toContain('focus-visible:outline-2');
    expect(area.classes()).toContain('focus-visible:outline-offset-2');
    await area.trigger('dragenter');
    expect(area.classes()).toEqual(
      expect.arrayContaining(['border-solid', 'border-n-blue-9', 'bg-n-blue-2'])
    );
    expect(area.classes()).not.toContain('border-dashed');
    await area.trigger('dragleave');
    expect(area.classes()).toContain('border-dashed');
  });
});

describe('V5. histórico: prazo junto do botão Desfazer', () => {
  it('"até dd/mm" fica no mesmo bloco do botão, em cinza pequeno', () => {
    const w = mount(HistoricoDeListas, {
      props: {
        listas: [
          {
            id: 'a',
            arquivo: 'a.xlsx',
            quando: Date.UTC(2026, 10, 8, 15),
            quem: 'Marina Dornelaz',
            total: 5,
            situacao: 'pronto',
            porcentagem: 100,
          },
        ],
        prazoDe: () => 'aberto',
      },
    });
    const bloco = marca(w, 'desfazer').element.parentElement;
    expect(bloco.textContent).toContain('até 15/11');
    const prazo = [...bloco.querySelectorAll('span')].find(el =>
      el.textContent.includes('até')
    );
    expect(prazo.className).toContain('text-xs');
  });
});

describe('rodada 3', () => {
  it('1. "O que vou guardar": título do tamanho dos outros, botão no h2 e apoio quando fechado', async () => {
    const w = mount(OQueVouGuardar, {
      props: { colunas: leitura.colunas },
    });
    const botaoTitulo = w.get('h2 button');
    expect(w.get('h2').classes()).toEqual(
      expect.arrayContaining(['text-2xl', 'font-semibold'])
    );
    expect(botaoTitulo.classes()).toEqual(
      expect.arrayContaining(['text-2xl', 'font-semibold'])
    );
    expect(botaoTitulo.attributes('aria-expanded')).toBe('false');
    const apoio = marca(w, 'guardar-apoio');
    expect(apoio.text()).toBe(
      'Cada coluna da sua planilha e para onde ela vai.'
    );
    await botaoTitulo.trigger('click');
    expect(botaoTitulo.attributes('aria-expanded')).toBe('true');
    expect(marca(w, 'guardar-apoio').attributes('style') || '').toContain(
      'display: none'
    );
  });

  it('2. e-mail da ficha quebra em até duas linhas, sem truncar', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Marina Esteveira',
          telefone: '+55 11 94271-0003',
          email: 'marina.esteveira@exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="marina.esteveira@exemplo.com.br"]');
    expect(email.classes()).toEqual(
      expect.arrayContaining(['break-words', 'line-clamp-2'])
    );
    expect(email.classes()).not.toContain('break-all');
    expect(email.classes()).not.toContain('truncate');
  });

  it('T1. o e-mail só quebra no "@", com <wbr> entre as duas partes', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Marina Esteveira',
          telefone: '',
          email: 'marina.esteveira@exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="marina.esteveira@exemplo.com.br"]');
    expect(email.element.innerHTML).toContain(
      'marina.esteveira<wbr>@exemplo.com.br'
    );
    expect(email.text()).toBe('marina.esteveira@exemplo.com.br');
  });

  it('T1. e-mail sem "@" (linha com problema) vem inteiro, sem <wbr>', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Rita Carvalhedo',
          telefone: '',
          email: 'rita.carvalhedo.exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="rita.carvalhedo.exemplo.com.br"]');
    expect(email.element.innerHTML).not.toContain('<wbr>');
    expect(email.text()).toBe('rita.carvalhedo.exemplo.com.br');
  });

  it('T2/B2. nome em até 2 linhas, com altura reservada em md+ (selo alinhado)', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Otávio Lourenzatto',
          telefone: '',
          email: '',
          empresa: '',
          cliente: true,
        },
      },
    });
    const nome = w.get('h3');
    expect(nome.classes()).toEqual(
      expect.arrayContaining(['line-clamp-2', 'md:min-h-12'])
    );
    expect(nome.classes()).not.toContain('md:truncate');
    expect(nome.attributes('title')).toBe('Otávio Lourenzatto');
  });

  it('3. Pronto: linha de sossego abaixo do herói e "Trazer outra lista" discreta', () => {
    const w = mount(TelaPronto, { props: { total: 195 } });
    expect(marca(w, 'pronto').exists()).toBe(true);
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer por 7 dias, em “Listas que você já trouxe”.'
    );
    expect(marca(w, 'trazer-outra').text()).toBe('Trazer outra lista');
    expect(marca(w, 'trazer-outra').classes()).toContain('bg-white/10');
  });

  it('4. Salvar é discreto: só "Trazer N pessoas" é preenchido na tela', () => {
    const w = mount(TelaConferir, {
      props: {
        leitura,
        resumo: contagem.resumoAoVivo(leitura),
        total: contagem.totalDaLeitura(leitura),
      },
    });
    const salvar = w.findAll('button').filter(b => b.text() === 'Salvar');
    expect(salvar.length).toBeGreaterThan(0);
    salvar.forEach(b => {
      expect(b.classes().join(' ')).not.toContain('bg-n-blue-11');
    });
    expect(marca(w, 'trazer-confirmar').classes().join(' ')).toContain(
      'bg-n-blue-11'
    );
  });
});

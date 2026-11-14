import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import { resumoDaTela } from '../../trazer/contagem';
import { ETAPAS } from '../../trazer/etapas';
import {
  PERGUNTAS,
  emVoo,
  fonteDeMentira,
  lida,
  montarTela,
  noConferir,
} from './apoioDaTela';

// #2896, Fatia 2 — enquanto uma escrita está indo ao servidor (ou a planilha
// está sendo lida de novo) a tela não aceita outra por cima: o Voltar não anda
// e o segundo "Trazer" não abre outra lista nem outra cadeia de consultas.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

// A leitura que volta de responder traz a resposta que o servidor gravou (a
// pergunta que voltasse sem resposta seria feita de novo).
const GRAVADA = lida({
  perguntas: [PERGUNTAS[0]],
  respostas: { clientes: 'sim_todas' },
});

describe('Voltar com uma escrita em voo', () => {
  it('no Conferir: não sai da tela enquanto a escrita não volta', async () => {
    const escrita = emVoo();
    const { tela } = await noConferir(lida({ perguntas: [] }), {
      deixarDeFora: vi.fn(() => escrita.promessa),
    });
    const deixando = tela.deixarDeFora(14);
    expect(tela.ocupado.value).toBe(true);
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    escrita.resolver(lida());
    await deixando;
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
  });

  it('na pergunta: não volta enquanto a resposta está sendo gravada', async () => {
    const escrita = emVoo();
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(lida({ perguntas: [PERGUNTAS[0]] })),
      responder: vi.fn(() => escrita.promessa),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('clientes', 'sim_todas');
    const continuando = tela.continuar();
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    escrita.resolver(GRAVADA);
    await continuando;
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('o segundo Continuar em voo não grava duas vezes', async () => {
    const escrita = emVoo();
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(lida({ perguntas: [PERGUNTAS[0]] })),
      responder: vi.fn(() => escrita.promessa),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('clientes', 'sim_todas');
    const primeiro = tela.continuar();
    const segundo = tela.continuar();
    escrita.resolver(GRAVADA);
    await Promise.all([primeiro, segundo]);
    expect(fonte.responder).toHaveBeenCalledTimes(1);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });
});

describe('o segundo Trazer', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const TRAZENDO = { porcentagem: 10, situacao: 'trazendo' };

  it('com o primeiro em voo: não pede de novo ao servidor', async () => {
    const pedido = emVoo();
    const { tela, fonte, parar } = await noConferir(lida(), {
      trazer: vi.fn(() => pedido.promessa),
      andamento: vi.fn().mockResolvedValue(TRAZENDO),
    });
    const primeiro = tela.trazer();
    const segundo = tela.trazer();
    pedido.resolver({ trazidaId: 't1' });
    await Promise.all([primeiro, segundo]);
    expect(fonte.trazer).toHaveBeenCalledTimes(1);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    parar();
  });

  it('depois de a lista começar a ser trazida: não pede de novo nem abre outra cadeia de consultas', async () => {
    const { tela, fonte, parar } = await noConferir(lida(), {
      andamento: vi.fn().mockResolvedValue(TRAZENDO),
    });
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    await tela.trazer();
    expect(fonte.trazer).toHaveBeenCalledTimes(1);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    // Uma cadeia só: uma consulta por espera.
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    parar();
  });

  it('"tentar de novo" depois do erro do trazer começa uma cadeia só', async () => {
    const { tela, fonte, parar } = await noConferir(lida(), {
      trazer: vi
        .fn()
        .mockRejectedValueOnce(new Error('caiu'))
        .mockResolvedValueOnce({ trazidaId: 't1' }),
      andamento: vi.fn().mockResolvedValue(TRAZENDO),
    });
    await tela.trazer();
    await tela.tentarDeNovo();
    expect(fonte.trazer).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    parar();
  });
});

describe('os botões do Conferir com a escrita em voo', () => {
  const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
  const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
  const trazer = w =>
    w.findComponent('[data-relacionamentos="trazer-confirmar"]');
  const montar = (props = {}) =>
    mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura: lida(),
        resumo: resumoDaTela(lida()),
        total: 195,
        ...props,
      },
    });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('o Voltar e o Trazer ficam desligados', () => {
    const w = montar({ ocupado: true });
    expect(botao(w, 'Voltar').attributes('disabled')).toBeDefined();
    expect(marca(w, 'trazer-confirmar').attributes('disabled')).toBeDefined();
    const livre = montar();
    expect(botao(livre, 'Voltar').attributes('disabled')).toBeUndefined();
  });

  it('o Trazer que a pessoa clicou fica carregando até a escrita voltar', async () => {
    const w = montar();
    await marca(w, 'trazer-confirmar').trigger('click');
    expect(w.emitted('trazer')).toHaveLength(1);
    await w.setProps({ ocupado: true });
    expect(trazer(w).props('isLoading')).toBe(true);
    await w.setProps({ ocupado: false });
    expect(trazer(w).props('isLoading')).toBe(false);
  });

  it('outra escrita em voo desliga o Trazer sem o pôr carregando', () => {
    expect(trazer(montar({ ocupado: true })).props('isLoading')).toBe(false);
  });

  it('lendo a planilha de novo: a tela diz isso num `status`', async () => {
    const w = montar();
    const estado = marca(w, 'relendo');
    expect(estado.attributes('role')).toBe('status');
    expect(estado.text()).toBe('');
    await w.setProps({ ocupado: true, relendo: true });
    expect(estado.text()).toBe('Lendo sua planilha de novo…');
  });
});

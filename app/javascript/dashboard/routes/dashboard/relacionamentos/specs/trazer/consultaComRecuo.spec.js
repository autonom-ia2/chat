import { effectScope } from 'vue';
import {
  INTERVALO_INICIAL_MS,
  INTERVALO_MAXIMO_MS,
  agendaComRecuo,
} from '../../trazer/consultaComRecuo';
import { useHistoricoDeListas } from '../../trazer/useHistoricoDeListas';
import { useTrazerLista } from '../../trazer/useTrazerLista';
import { ETAPAS } from '../../trazer/etapas';

// #2896, Fatia 2 — a tela pergunta de novo ao servidor enquanto uma lista está
// sendo trazida. A espera entre uma pergunta e outra cresce (de 1,5 s até 5 s) e,
// com a aba escondida, a tela não pergunta: retoma quando a aba volta.
const esconderAAba = escondida => {
  Object.defineProperty(document, 'hidden', {
    configurable: true,
    get: () => escondida,
  });
  document.dispatchEvent(new Event('visibilitychange'));
};

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  esconderAAba(false);
  vi.useRealTimers();
});

describe('agendaComRecuo', () => {
  it('começa em 1,5 s e não passa de 5 s', () => {
    expect(INTERVALO_INICIAL_MS).toBe(1500);
    expect(INTERVALO_MAXIMO_MS).toBe(5000);
  });

  it('cada espera é maior que a anterior, até o máximo', () => {
    const agenda = agendaComRecuo();
    const tarefa = vi.fn();
    const esperas = [1500, 2250, 3375, 5000, 5000];
    esperas.forEach((espera, vez) => {
      agenda.agendar(tarefa);
      vi.advanceTimersByTime(espera - 1);
      expect(tarefa).toHaveBeenCalledTimes(vez);
      vi.advanceTimersByTime(1);
      expect(tarefa).toHaveBeenCalledTimes(vez + 1);
    });
  });

  it('recomeçar volta à primeira espera', () => {
    const agenda = agendaComRecuo();
    const tarefa = vi.fn();
    agenda.agendar(tarefa);
    vi.advanceTimersByTime(1500);
    agenda.recomecar();
    agenda.agendar(tarefa);
    vi.advanceTimersByTime(1500);
    expect(tarefa).toHaveBeenCalledTimes(2);
  });

  it('agendar de novo troca a tarefa que estava esperando: nunca há duas', () => {
    const agenda = agendaComRecuo();
    const velha = vi.fn();
    const nova = vi.fn();
    agenda.agendar(velha);
    agenda.agendar(nova);
    vi.advanceTimersByTime(INTERVALO_MAXIMO_MS);
    expect(velha).not.toHaveBeenCalled();
    expect(nova).toHaveBeenCalledTimes(1);
  });

  it('cancelar tira a tarefa da espera', () => {
    const agenda = agendaComRecuo();
    const tarefa = vi.fn();
    agenda.agendar(tarefa);
    agenda.cancelar();
    vi.advanceTimersByTime(INTERVALO_MAXIMO_MS);
    expect(tarefa).not.toHaveBeenCalled();
  });

  it('com a aba escondida não roda a tarefa; roda quando a aba volta', () => {
    const agenda = agendaComRecuo();
    const tarefa = vi.fn();
    agenda.agendar(tarefa);
    esconderAAba(true);
    vi.advanceTimersByTime(60000);
    expect(tarefa).not.toHaveBeenCalled();
    esconderAAba(false);
    expect(tarefa).toHaveBeenCalledTimes(1);
    // Voltar de novo não repete a tarefa.
    esconderAAba(false);
    expect(tarefa).toHaveBeenCalledTimes(1);
  });

  it('cancelar com a aba escondida: a tarefa não roda quando a aba volta', () => {
    const agenda = agendaComRecuo();
    const tarefa = vi.fn();
    agenda.agendar(tarefa);
    esconderAAba(true);
    vi.advanceTimersByTime(INTERVALO_INICIAL_MS);
    agenda.cancelar();
    esconderAAba(false);
    expect(tarefa).not.toHaveBeenCalled();
  });
});

describe('o histórico pergunta com recuo e para com a aba escondida', () => {
  const TRAZENDO = [{ id: 't1', situacao: 'trazendo', porcentagem: 10 }];
  const montar = () => {
    const escopo = effectScope();
    const fonte = { historico: vi.fn().mockResolvedValue(TRAZENDO) };
    const historico = escopo.run(() => useHistoricoDeListas({ fonte }));
    return { fonte, historico, parar: () => escopo.stop() };
  };

  it('a segunda pergunta espera mais que a primeira', async () => {
    const { fonte, historico, parar } = montar();
    await historico.carregar();
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.historico).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.historico).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(750);
    expect(fonte.historico).toHaveBeenCalledTimes(3);
    parar();
  });

  it('a carga que a pessoa pede recomeça da primeira espera', async () => {
    const { fonte, historico, parar } = montar();
    await historico.carregar();
    await vi.advanceTimersByTimeAsync(1500);
    await historico.carregar();
    const antes = fonte.historico.mock.calls.length;
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.historico).toHaveBeenCalledTimes(antes + 1);
    parar();
  });

  it('com a aba escondida não pergunta; pergunta quando a aba volta', async () => {
    const { fonte, historico, parar } = montar();
    await historico.carregar();
    esconderAAba(true);
    await vi.advanceTimersByTimeAsync(60000);
    expect(fonte.historico).toHaveBeenCalledTimes(1);
    esconderAAba(false);
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.historico).toHaveBeenCalledTimes(2);
    parar();
  });

  it('sair da tela com a aba escondida: não pergunta quando a aba volta', async () => {
    const { fonte, historico, parar } = montar();
    await historico.carregar();
    esconderAAba(true);
    await vi.advanceTimersByTimeAsync(1500);
    parar();
    esconderAAba(false);
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.historico).toHaveBeenCalledTimes(1);
  });
});

describe('o andamento pergunta com recuo e para com a aba escondida', () => {
  const LIDA = {
    id: 'l1',
    arquivo: 'a.csv',
    perguntas: [],
    problemas: [],
    resumo: { entram: 3 },
  };
  const montar = () => {
    const escopo = effectScope();
    const fonte = {
      ler: vi.fn().mockResolvedValue(LIDA),
      trazer: vi.fn().mockResolvedValue({ trazidaId: 't1' }),
      andamento: vi
        .fn()
        .mockResolvedValue({ porcentagem: 10, situacao: 'trazendo' }),
    };
    const tela = escopo.run(() => useTrazerLista({ fonte }));
    return { fonte, tela, parar: () => escopo.stop() };
  };
  const trazer = async tela => {
    await tela.escolherArquivo({ name: 'a.csv' });
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
  };

  it('a segunda pergunta espera mais que a primeira', async () => {
    const { fonte, tela, parar } = montar();
    await trazer(tela);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1500);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(750);
    expect(fonte.andamento).toHaveBeenCalledTimes(3);
    parar();
  });

  it('com a aba escondida não pergunta; pergunta quando a aba volta', async () => {
    const { fonte, tela, parar } = montar();
    await trazer(tela);
    esconderAAba(true);
    await vi.advanceTimersByTimeAsync(60000);
    expect(fonte.andamento).toHaveBeenCalledTimes(1);
    esconderAAba(false);
    await vi.advanceTimersByTimeAsync(0);
    expect(fonte.andamento).toHaveBeenCalledTimes(2);
    parar();
  });
});

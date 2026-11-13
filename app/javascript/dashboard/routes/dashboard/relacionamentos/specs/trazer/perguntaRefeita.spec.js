import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
import { ETAPAS } from '../../trazer/etapas';
import {
  MARCADOR,
  PERGUNTAS,
  RESPONDIDAS,
  erroDeNome,
  lida,
  noConferir,
} from './apoioDaTela';

// #2896, Fatia 2 — a troca de uma coluna pode derrubar uma resposta (a coluna
// que dizia quem é cliente, a coluna do telefone). A tela leva a pessoa de volta
// à pergunta e a pergunta diz por que está sendo feita de novo.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const COM_RESPOSTAS = lida({ perguntas: PERGUNTAS, respostas: RESPONDIDAS });
const SEM_A_DO_TELEFONE = lida({
  perguntas: PERGUNTAS,
  respostas: { clientes: 'sim_todas' },
});

// A tela no Conferir de uma leitura com as duas perguntas já respondidas.
const noConferirRespondido = async (extra = {}) => {
  const montada = await noConferir(COM_RESPOSTAS, {
    responder: vi.fn().mockResolvedValue(COM_RESPOSTAS),
    ...extra,
  });
  await montada.tela.continuar();
  await montada.tela.continuar();
  expect(montada.tela.etapa.value).toBe(ETAPAS.CONFERIR);
  return montada;
};

afterEach(() => {
  document.body.innerHTML = '';
});

describe('o estado marca a pergunta que voltou por causa da troca', () => {
  it('a troca que derruba uma resposta leva à pergunta e liga `perguntaDeNovo`', async () => {
    const { tela } = await noConferirRespondido({
      trocarDestino: vi.fn().mockResolvedValue(SEM_A_DO_TELEFONE),
    });
    await tela.trocarDestino(1, 'cidade');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('telefone');
    expect(tela.perguntaDeNovo.value).toBe(true);
  });

  it('vale também quando a planilha é lida de novo antes', async () => {
    const { tela } = await noConferirRespondido({
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi.fn().mockResolvedValue(SEM_A_DO_TELEFONE),
    });
    await tela.trocarDestino(1, 'email');
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaDeNovo.value).toBe(true);
  });

  it('e quando a espera falha e a pessoa tenta de novo', async () => {
    const { tela } = await noConferirRespondido({
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi
        .fn()
        .mockRejectedValueOnce(
          erroDeNome('LEITURA_PENDENTE', { leituraId: 'l1' })
        )
        .mockResolvedValueOnce(SEM_A_DO_TELEFONE),
    });
    await tela.trocarDestino(1, 'email');
    expect(tela.perguntaDeNovo.value).toBe(false);
    await tela.tentarDeNovo();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaDeNovo.value).toBe(true);
  });

  it('a troca que não derruba resposta fica no Conferir, sem marcar nada', async () => {
    const { tela } = await noConferirRespondido({
      trocarDestino: vi.fn().mockResolvedValue(COM_RESPOSTAS),
    });
    await tela.trocarDestino(6, 'cidade');
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.perguntaDeNovo.value).toBe(false);
  });

  it('quem volta à pergunta pelo "Voltar" não vê a frase', async () => {
    const { tela } = await noConferirRespondido();
    tela.voltar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaDeNovo.value).toBe(false);
  });

  it('respondeu e continuou: a frase não segue para a tela seguinte', async () => {
    const { tela } = await noConferirRespondido({
      trocarDestino: vi.fn().mockResolvedValue(SEM_A_DO_TELEFONE),
      responder: vi.fn().mockResolvedValue(COM_RESPOSTAS),
    });
    await tela.trocarDestino(1, 'cidade');
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.perguntaDeNovo.value).toBe(false);
  });
});

describe('a pergunta diz por que voltou', () => {
  const montar = (pergunta, props = {}) =>
    mount(PerguntaDaVez, {
      attachTo: document.body,
      props: { pergunta, respostas: {}, ...props },
    });

  it('a de clientes', () => {
    const w = montar(PERGUNTAS[0], { deNovo: true });
    expect(marca(w, 'pergunta-de-novo').text()).toBe(
      'Você mudou a coluna que dizia quem é cliente. Responda de novo.'
    );
  });

  it('a do telefone', () => {
    const w = montar(PERGUNTAS[1], { deNovo: true });
    expect(marca(w, 'pergunta-de-novo').text()).toBe(
      'Você mudou a coluna do telefone. Responda de novo.'
    );
  });

  it('o título aponta para a frase (o leitor de tela a lê junto)', () => {
    const w = montar(PERGUNTAS[1], { deNovo: true });
    expect(w.get('h1').attributes('aria-describedby')).toBe(
      marca(w, 'pergunta-de-novo').attributes('id')
    );
  });

  it('sem `deNovo` a frase não aparece', () => {
    const w = montar(PERGUNTAS[1]);
    expect(marca(w, 'pergunta-de-novo').exists()).toBe(false);
    expect(w.get('h1').attributes('aria-describedby')).toBeUndefined();
  });
});

describe('a pergunta enquanto a resposta é gravada', () => {
  const montar = props =>
    mount(PerguntaDaVez, {
      attachTo: document.body,
      props: {
        pergunta: PERGUNTAS[1],
        respostas: { telefone: 'da_pessoa' },
        podeContinuar: true,
        ...props,
      },
    });
  const voltar = w => w.findAll('button').find(b => b.text() === 'Voltar');

  it('o Voltar fica desligado com a escrita em voo', () => {
    expect(
      voltar(montar({ ocupado: true })).attributes('disabled')
    ).toBeDefined();
    expect(voltar(montar({})).attributes('disabled')).toBeUndefined();
  });

  it('lendo a planilha de novo: diz isso num `status`, com o Continuar carregando', () => {
    const w = montar({ ocupado: true, relendo: true });
    const estado = marca(w, 'relendo');
    expect(estado.attributes('role')).toBe('status');
    expect(estado.text()).toBe('Lendo sua planilha de novo…');
    expect(
      w.findComponent('[data-relacionamentos="continuar"]').props('isLoading')
    ).toBe(true);
  });

  it('a região de estado existe vazia antes (para o leitor de tela anunciar depois)', () => {
    const estado = marca(montar({}), 'relendo');
    expect(estado.exists()).toBe(true);
    expect(estado.text()).toBe('');
  });
});

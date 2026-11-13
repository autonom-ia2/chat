import { flushPromises, mount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import TrazerSeguros from '../../components/carteira/trazer/TrazerSeguros.vue';
import { PASSOS, useTrazerSeguros } from '../../carteira/useTrazerSeguros';
import { leituraDeExemplo } from '../../demo/trazer';
import {
  comAResposta,
  comODestino,
  comSeguros,
  estadoInicial,
} from '../../demo/trazerSeguros';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS } from '../../trazer/falhasDaTela';
import { daCarteira } from './apoio';

// #2897 — as telas que "Trazer minha lista" ganha na conta de seguros
// (components/carteira/trazer/TrazerSeguros.vue) e quem decide quando elas
// aparecem (carteira/useTrazerSeguros.js), com o estado da tela das listas de
// mentira e as leituras da demonstração (tudo fictício).
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

// O estado de "Trazer minha lista" como a página o tem (trazer/useTrazerLista.js):
// só o que as telas da carteira leem e pedem.
const telaDeMentira = (extra = {}) => ({
  etapa: ref(ETAPAS.CONFERIR),
  leitura: ref(null),
  lendo: ref(false),
  erro: ref(ERROS.NENHUM),
  releituraParada: ref(false),
  perguntaAtual: ref(null),
  respostas: ref({}),
  ocupado: ref(false),
  relendo: ref(false),
  recusaDaPergunta: ref(null),
  recusaDoConserto: ref(null),
  recusaDaColuna: ref(null),
  faltamCarregar: ref(0),
  carregandoMais: ref(false),
  erroDoMais: ref(false),
  responder: vi.fn(),
  continuar: vi.fn(),
  trazer: vi.fn(),
  voltar: vi.fn(),
  guardar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarDestino: vi.fn(),
  mostrarMais: vi.fn(),
  tentarDeNovo: vi.fn(),
  ...extra,
});

// A planilha de exemplo com "sim" na pergunta dos seguros.
const DAS_PESSOAS = leituraDeExemplo(1);
const COLUNAS_DAS_PESSOAS = DAS_PESSOAS.colunas.length;
const COM_TUDO = comAResposta(estadoInicial(), 'sim', COLUNAS_DAS_PESSOAS);
const leituraConferida = () => comSeguros(DAS_PESSOAS, COM_TUDO);
// A mesma, com a coluna de quando o seguro termina guardada como informação.
const leituraSemOFim = () => {
  const conferida = leituraConferida();
  const { indice } = conferida.colunas.find(
    coluna => coluna.destino === 'seguro_termina'
  );
  return comSeguros(DAS_PESSOAS, comODestino(COM_TUDO, indice, 'informacao'));
};

let aberta;
const abrir = (tela, fonte = {}) => {
  const carteira = useTrazerSeguros({ tela, fonte, ligado: true });
  aberta = mount(TrazerSeguros, {
    attachTo: document.body,
    props: { tela, carteira },
  });
  return { w: aberta, carteira };
};

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  document.body.innerHTML = '';
});

describe('Trazer com coluna do seguro faltando', () => {
  it('a tela já diz o que falta e mostra as colunas abertas, com o Trazer ligado', () => {
    const tela = telaDeMentira({ leitura: ref(leituraSemOFim()) });
    const { w } = abrir(tela);

    const conferir = w.get(daCarteira('conferir-seguros'));
    expect(conferir.attributes('data-conferidos')).toBe('nao');
    expect(w.get('h1').text()).toBe('Me diga onde estão os seguros');
    expect(
      w
        .get(daCarteira('colunas-que-faltam'))
        .findAll('li')
        .map(item => item.text())
    ).toEqual(['Quando o seguro termina']);
    expect(
      w
        .get('[data-relacionamentos="o-que-vou-guardar"] h2 button')
        .attributes('aria-expanded')
    ).toBe('true');
    expect(w.find(daCarteira('falta-coluna')).exists()).toBe(false);
    const trazer = w.get(daCarteira('trazer-seguros'));
    expect(trazer.text()).toBe('Trazer os seguros');
    expect(trazer.attributes('disabled')).toBeUndefined();
  });

  it('o clique em Trazer não vai ao servidor: diz o que falta como alerta e leva o foco até lá', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSemOFim()) });
    const { w } = abrir(tela);

    await w.get(daCarteira('trazer-seguros')).trigger('click');
    await flushPromises();

    expect(tela.trazer).not.toHaveBeenCalled();
    const alerta = w.get(daCarteira('falta-coluna'));
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'Ainda falta escolher a coluna de: Quando o seguro termina.'
    );
    expect(document.activeElement).toBe(alerta.element);
    // O botão aponta o alerta para o leitor de tela.
    expect(
      w.get(daCarteira('trazer-seguros')).attributes('aria-describedby')
    ).toBe(alerta.attributes('id'));
  });

  it('pedir de novo leva o foco ao alerta outra vez', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSemOFim()) });
    const { w } = abrir(tela);
    await w.get(daCarteira('trazer-seguros')).trigger('click');
    await flushPromises();
    const alerta = w.get(daCarteira('falta-coluna'));
    alerta.element.blur();

    await w.get(daCarteira('trazer-seguros')).trigger('click');
    await flushPromises();

    expect(tela.trazer).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(alerta.element);
  });

  it('apontada a coluna, o alerta some e o Trazer vai ao servidor', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSemOFim()) });
    const { w } = abrir(tela);
    await w.get(daCarteira('trazer-seguros')).trigger('click');
    await flushPromises();

    tela.leitura.value = leituraConferida();
    await flushPromises();

    expect(w.find(daCarteira('falta-coluna')).exists()).toBe(false);
    expect(
      w.get(daCarteira('conferir-seguros')).attributes('data-conferidos')
    ).toBe('sim');

    await w.get(daCarteira('trazer-seguros')).trigger('click');

    expect(tela.trazer).toHaveBeenCalledTimes(1);
  });

  it('as colunas oferecem os destinos de seguro, e a escolha vai para a tela das listas', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSemOFim()) });
    const { w } = abrir(tela);

    const fim = w.get('[data-coluna="Fim"]');
    await fim.get('[data-relacionamentos="trocar-coluna"]').trigger('click');
    await flushPromises();

    const oferecidos = fim
      .findAll('[role="option"]')
      .map(opcao => opcao.attributes('data-value'));
    expect(oferecidos).toEqual(
      expect.arrayContaining(tela.leitura.value.seguros.destinos)
    );
    const termina = fim.get('[role="option"][data-value="seguro_termina"]');
    expect(termina.text()).toContain('Quando o seguro termina');

    await termina.trigger('click');
    await flushPromises();

    const { indice } = tela.leitura.value.colunas.find(
      coluna => coluna.nome === 'Fim'
    );
    expect(tela.trocarDestino).toHaveBeenCalledWith(indice, 'seguro_termina');
  });
});

describe('quando a tela é a da carteira', () => {
  const passoDe = (tela, opcoes = {}) =>
    useTrazerSeguros({ tela, fonte: {}, ligado: true, ...opcoes });

  it('na conta sem a carteira, nunca', () => {
    const tela = telaDeMentira({
      etapa: ref(ETAPAS.ENVIAR),
      leitura: ref(leituraConferida()),
    });
    const carteira = passoDe(tela, { ligado: false });

    expect(carteira.passo.value).toBe(null);
    tela.etapa.value = ETAPAS.CONFERIR;
    expect(carteira.passo.value).toBe(null);
  });

  it('antes de enviar, a escolha de como trazer; escolhida a planilha, a tela das listas', () => {
    const tela = telaDeMentira({ etapa: ref(ETAPAS.ENVIAR) });
    const carteira = passoDe(tela);

    expect(carteira.passo.value).toBe(PASSOS.COMO);
    carteira.escolherPlanilha();
    expect(carteira.passo.value).toBe(null);
    carteira.recomecar();
    expect(carteira.passo.value).toBe(PASSOS.COMO);
  });

  it('a planilha sendo lida e o erro do envio são da tela das listas', () => {
    const tela = telaDeMentira({ etapa: ref(ETAPAS.ENVIAR) });
    const carteira = passoDe(tela);

    tela.lendo.value = true;
    expect(carteira.passo.value).toBe(null);
    tela.lendo.value = false;
    tela.erro.value = ERROS.LEITURA;
    expect(carteira.passo.value).toBe(null);
  });

  it('nas perguntas, só a dos seguros', () => {
    const tela = telaDeMentira({
      etapa: ref(ETAPAS.PERGUNTAS),
      perguntaAtual: ref({ id: 'clientes' }),
    });
    const carteira = passoDe(tela);

    expect(carteira.passo.value).toBe(null);
    tela.perguntaAtual.value = { id: 'seguros' };
    expect(carteira.passo.value).toBe(PASSOS.PERGUNTA);
  });

  it('a resposta dos seguros já segue para a próxima tela', () => {
    const tela = telaDeMentira({ etapa: ref(ETAPAS.PERGUNTAS) });
    const carteira = passoDe(tela);

    carteira.responder('sim');

    expect(tela.responder).toHaveBeenCalledWith('seguros', 'sim');
    expect(tela.continuar).toHaveBeenCalledTimes(1);
  });

  it('no conferir, só a planilha que tem seguros', () => {
    const tela = telaDeMentira({ leitura: ref(DAS_PESSOAS) });
    const carteira = passoDe(tela);

    expect(carteira.passo.value).toBe(null);
    tela.leitura.value = leituraSemOFim();
    expect(carteira.passo.value).toBe(PASSOS.CONFERIR);
    tela.releituraParada.value = true;
    expect(carteira.passo.value).toBe(null);
  });

  it('no fim, diz o que o servidor contou; sem a conta dele, o que o Conferir dizia', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraConferida()) });
    const doServidor = {
      seguros: 4,
      pessoas: 3,
      pessoasNovas: 1,
      pessoasQueJaEstavam: 2,
    };
    const fonte = { chegaram: vi.fn(() => null) };
    const carteira = passoDe(tela, { fonte });

    carteira.trazer();
    tela.etapa.value = ETAPAS.TRAZENDO;
    expect(carteira.passo.value).toBe(null);
    tela.etapa.value = ETAPAS.PRONTO;

    expect(carteira.passo.value).toBe(PASSOS.PRONTO);
    const { seguros, pessoas } = leituraConferida().resumo;
    expect(carteira.chegaram.value).toMatchObject({ seguros, pessoas });

    // A lista seguinte, com a conta do servidor.
    tela.etapa.value = ETAPAS.ENVIAR;
    await nextTick();
    tela.etapa.value = ETAPAS.CONFERIR;
    fonte.chegaram.mockReturnValue(doServidor);
    carteira.trazer();
    tela.etapa.value = ETAPAS.PRONTO;

    expect(carteira.chegaram.value).toEqual(doServidor);
  });

  it('a lista que só trouxe pessoas termina na tela das listas', () => {
    const tela = telaDeMentira({ leitura: ref(DAS_PESSOAS) });
    const carteira = passoDe(tela);

    carteira.trazer();
    tela.etapa.value = ETAPAS.PRONTO;

    expect(tela.trazer).toHaveBeenCalledTimes(1);
    expect(carteira.passo.value).toBe(null);
  });
});

import { flushPromises, mount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import TrazerSeguros from '../../components/carteira/trazer/TrazerSeguros.vue';
import { PASSOS, useTrazerSeguros } from '../../carteira/useTrazerSeguros';
import { leituraDeExemplo } from '../../demo/trazer';
import {
  comAResposta,
  comAsSugestoesConfirmadas,
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
  porcentagem: ref(0),
  responder: vi.fn(),
  continuar: vi.fn(),
  trazer: vi.fn(),
  voltar: vi.fn(),
  guardar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarDestino: vi.fn(() => Promise.resolve(true)),
  mostrarMais: vi.fn(),
  tentarDeNovo: vi.fn(),
  ...extra,
});

// A planilha de exemplo com "sim" na pergunta dos seguros: o servidor sugere a
// coluna de cada coisa do seguro, e nenhuma está confirmada.
const DAS_PESSOAS = leituraDeExemplo(1);
const COLUNAS_DAS_PESSOAS = DAS_PESSOAS.colunas.length;
const SUGERIDO = comAResposta(estadoInicial(), 'sim', COLUNAS_DAS_PESSOAS);
const leituraSugerida = () => comSeguros(DAS_PESSOAS, SUGERIDO);
// A mesma, depois do "Está certo": as linhas conferidas como seguro.
const leituraConferida = () =>
  comSeguros(DAS_PESSOAS, comAsSugestoesConfirmadas(SUGERIDO));
// O servidor não sugeriu a coluna de quando o seguro termina.
const semSugestaoDoFim = () => {
  const { seguro_termina: _, ...sugestao } = SUGERIDO.sugestao;
  return comSeguros(DAS_PESSOAS, { ...SUGERIDO, sugestao });
};
// O servidor não sugeriu nada (o modelo está desligado ou não respondeu).
const semSugestao = () =>
  comSeguros(DAS_PESSOAS, { ...SUGERIDO, sugestao: {} });
const indiceDa = (leitura, nome) =>
  leitura.colunas.find(coluna => coluna.nome === nome).indice;

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

const linhaDo = (w, destino) =>
  w.get(`${daCarteira('colunas-dos-seguros')} [data-destino="${destino}"]`);
// Abre a lista de colunas de um destino e escolhe a coluna de índice `coluna`.
const apontar = async (w, destino, coluna) => {
  const linha = linhaDo(w, destino);
  await linha.get('[role="combobox"]').trigger('click');
  await flushPromises();
  await linha.get(`[role="option"][data-value="${coluna}"]`).trigger('click');
  await flushPromises();
};

describe('onde estão os seguros: a tela chega com o que o servidor sugeriu', () => {
  it('pergunta se está certo e mostra a coluna achada para cada coisa do seguro', () => {
    const tela = telaDeMentira({ leitura: ref(leituraSugerida()) });
    const { w } = abrir(tela);

    expect(
      w.get(daCarteira('conferir-seguros')).attributes('data-conferidos')
    ).toBe('nao');
    expect(w.get('h1').text()).toBe(
      'Achei os seguros na sua planilha. Está certo?'
    );
    const linhas = w.findAll(`${daCarteira('colunas-dos-seguros')} > li`);
    expect(linhas.map(linha => linha.attributes('data-destino'))).toEqual(
      tela.leitura.value.seguros.destinos
    );
    linhas.forEach(linha =>
      expect(linha.attributes('data-situacao')).toBe('sugerida')
    );
    const termina = linhaDo(w, 'seguro_termina');
    expect(termina.get('label').text()).toBe('Quando o seguro termina');
    expect(termina.get('[role="combobox"]').text()).toContain('Fim');
    expect(termina.get(daCarteira('situacao-da-coluna')).text()).toBe(
      'Foi a coluna que achei. Confira.'
    );
    // Um botão principal só, ligado; a lista de colunas das listas não aparece.
    const certo = w.get(daCarteira('confirmar-colunas'));
    expect(certo.text()).toBe('Está certo');
    expect(certo.attributes('disabled')).toBeUndefined();
    expect(w.find(daCarteira('trazer-seguros')).exists()).toBe(false);
    expect(w.find('[data-relacionamentos="o-que-vou-guardar"]').exists()).toBe(
      false
    );
  });

  it('"Está certo" confirma todas de uma vez, os obrigatórios por último', async () => {
    const leitura = leituraSugerida();
    const tela = telaDeMentira({ leitura: ref(leitura) });
    const { w } = abrir(tela);

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    const pedidos = tela.trocarDestino.mock.calls;
    expect(pedidos.map(([, destino]) => destino)).toEqual([
      'seguro_comeca',
      'seguro_valor',
      'seguro_bem',
      'seguro_numero',
      'seguro_seguradora',
      'seguro_tipo',
      'seguro_termina',
    ]);
    pedidos.forEach(([coluna, destino]) =>
      expect(coluna).toBe(leitura.seguros.sugestao[destino])
    );
    expect(w.find(daCarteira('falta-coluna')).exists()).toBe(false);
    expect(w.find(daCarteira('erro-nas-colunas')).exists()).toBe(false);
  });

  it('a pessoa troca a coluna errada antes de confirmar, e nada vai ao servidor até o "Está certo"', async () => {
    const leitura = leituraSugerida();
    const tela = telaDeMentira({ leitura: ref(leitura) });
    const { w } = abrir(tela);

    // O valor está, na verdade, na coluna "Bem".
    await apontar(w, 'seguro_valor', indiceDa(leitura, 'Bem'));

    expect(tela.trocarDestino).not.toHaveBeenCalled();
    expect(linhaDo(w, 'seguro_valor').attributes('data-situacao')).toBe(
      'escolhida'
    );
    // A coluna só guarda uma coisa: quem a tinha fica sem coluna.
    expect(linhaDo(w, 'seguro_bem').attributes('data-situacao')).toBe(
      'opcional'
    );

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    const pedidos = tela.trocarDestino.mock.calls;
    expect(pedidos).toContainEqual([indiceDa(leitura, 'Bem'), 'seguro_valor']);
    expect(pedidos.map(([, destino]) => destino)).not.toContain('seguro_bem');
  });

  it('a confirmação que para no meio diz o que houve e oferece tentar de novo', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSugerida()) });
    tela.trocarDestino.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
    const { w } = abrir(tela);

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    // Parou na segunda: as seguintes não foram pedidas.
    expect(tela.trocarDestino).toHaveBeenCalledTimes(2);
    const erro = w.get(daCarteira('erro-nas-colunas'));
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toBe(
      'Não consegui guardar todas as colunas. O que deu certo já está salvo.'
    );
    expect(w.get(daCarteira('confirmar-colunas')).text()).toBe(
      'Tentar de novo'
    );
  });

  it('confirmadas as colunas, a tela passa a ser a dos seguros contados', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraSugerida()) });
    const { w } = abrir(tela);

    tela.leitura.value = leituraConferida();
    await flushPromises();

    expect(
      w.get(daCarteira('conferir-seguros')).attributes('data-conferidos')
    ).toBe('sim');
    expect(w.find(daCarteira('colunas-dos-seguros')).exists()).toBe(false);
    expect(w.find('[data-relacionamentos="o-que-vou-guardar"]').exists()).toBe(
      true
    );

    await w.get(daCarteira('trazer-seguros')).trigger('click');

    expect(tela.trazer).toHaveBeenCalledTimes(1);
  });
});

describe('onde estão os seguros: o servidor não achou uma coluna', () => {
  it('a linha diz que não achou e pede a coluna; o botão continua ligado', () => {
    const tela = telaDeMentira({ leitura: ref(semSugestaoDoFim()) });
    const { w } = abrir(tela);

    const termina = linhaDo(w, 'seguro_termina');
    expect(termina.attributes('data-situacao')).toBe('falta');
    expect(termina.get(daCarteira('situacao-da-coluna')).text()).toBe(
      'Não achei. Escolha a coluna.'
    );
    expect(termina.get('[role="combobox"]').text()).toContain(
      'Escolha a coluna'
    );
    expect(
      w.get(daCarteira('confirmar-colunas')).attributes('disabled')
    ).toBeUndefined();
    expect(w.find(daCarteira('falta-coluna')).exists()).toBe(false);
  });

  it('o clique não vai ao servidor: diz o que falta como alerta e leva o foco até lá', async () => {
    const tela = telaDeMentira({ leitura: ref(semSugestaoDoFim()) });
    const { w } = abrir(tela);

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    expect(tela.trocarDestino).not.toHaveBeenCalled();
    const alerta = w.get(daCarteira('falta-coluna'));
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'Ainda falta escolher a coluna de: Quando o seguro termina.'
    );
    expect(document.activeElement).toBe(alerta.element);
    // O botão e o campo que falta apontam o alerta para o leitor de tela.
    expect(
      w.get(daCarteira('confirmar-colunas')).attributes('aria-describedby')
    ).toBe(alerta.attributes('id'));
    const campo = linhaDo(w, 'seguro_termina').get('[role="combobox"]');
    expect(campo.attributes('aria-invalid')).toBe('true');
    expect(campo.attributes('aria-describedby')).toBe(alerta.attributes('id'));
  });

  it('pedir de novo leva o foco ao alerta outra vez', async () => {
    const tela = telaDeMentira({ leitura: ref(semSugestaoDoFim()) });
    const { w } = abrir(tela);
    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();
    const alerta = w.get(daCarteira('falta-coluna'));
    alerta.element.blur();

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    expect(tela.trocarDestino).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(alerta.element);
  });

  it('apontada a coluna, o alerta some e o "Está certo" manda todas', async () => {
    const leitura = semSugestaoDoFim();
    const tela = telaDeMentira({ leitura: ref(leitura) });
    const { w } = abrir(tela);
    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    await apontar(w, 'seguro_termina', indiceDa(leitura, 'Fim'));

    expect(w.find(daCarteira('falta-coluna')).exists()).toBe(false);
    expect(linhaDo(w, 'seguro_termina').attributes('data-situacao')).toBe(
      'escolhida'
    );

    await w.get(daCarteira('confirmar-colunas')).trigger('click');
    await flushPromises();

    const pedidos = tela.trocarDestino.mock.calls;
    expect(pedidos).toHaveLength(7);
    expect(pedidos.at(-1)).toEqual([
      indiceDa(leitura, 'Fim'),
      'seguro_termina',
    ]);
  });

  it('sem sugestão nenhuma, a tela pede as colunas e só oferece as que servem a um seguro', async () => {
    const leitura = semSugestao();
    const tela = telaDeMentira({ leitura: ref(leitura) });
    const { w } = abrir(tela);

    expect(w.get('h1').text()).toBe('Me diga onde estão os seguros');
    expect(linhaDo(w, 'seguro_numero').attributes('data-situacao')).toBe(
      'falta'
    );
    expect(linhaDo(w, 'seguro_bem').attributes('data-situacao')).toBe(
      'opcional'
    );
    expect(
      linhaDo(w, 'seguro_bem').get(daCarteira('situacao-da-coluna')).text()
    ).toBe('Não achei. Se a planilha não tiver, pode deixar assim.');

    const numero = linhaDo(w, 'seguro_numero');
    await numero.get('[role="combobox"]').trigger('click');
    await flushPromises();
    const oferecidas = numero
      .findAll('[role="option"]')
      .map(opcao => Number(opcao.attributes('data-value')));
    // As colunas que já acham a pessoa (o nome, o telefone, o e-mail, a
    // empresa) não são oferecidas; as outras, todas.
    const livres = leitura.colunas
      .filter(({ destino }) => destino === 'informacao')
      .map(({ indice }) => indice);
    expect(livres.length).toBeLessThan(leitura.colunas.length);
    expect(oferecidas).toEqual(livres);
    expect(oferecidas).toContain(indiceDa(leitura, 'Apólice'));
  });
});

describe('enquanto a lista é trazida', () => {
  it('a tela continua sendo o Conferir, com os números, e diz quanto falta no lugar dos botões', async () => {
    const tela = telaDeMentira({
      leitura: ref(leituraConferida()),
      porcentagem: ref(40),
    });
    const { w, carteira } = abrir(tela);
    const titulo = w.get('h1').text();

    carteira.trazer();
    tela.etapa.value = ETAPAS.TRAZENDO;
    await flushPromises();

    expect(carteira.passo.value).toBe(PASSOS.CONFERIR);
    expect(w.get('h1').text()).toBe(titulo);
    const andamento = w.get(daCarteira('trazendo-seguros'));
    expect(andamento.get('[role="status"]').text()).toBe(
      'Trazendo os seguros… 40%.'
    );
    expect(
      andamento.get('[role="progressbar"]').attributes('aria-valuenow')
    ).toBe('40');
    expect(w.find(daCarteira('trazer-seguros')).exists()).toBe(false);
    expect(w.find(daCarteira('voltar')).exists()).toBe(false);
    expect(w.find('[data-relacionamentos="o-que-vou-guardar"]').exists()).toBe(
      false
    );
  });

  it('se o andamento não vem, oferece tentar de novo ali mesmo', async () => {
    const tela = telaDeMentira({ leitura: ref(leituraConferida()) });
    const { w, carteira } = abrir(tela);
    carteira.trazer();
    tela.etapa.value = ETAPAS.TRAZENDO;
    tela.erro.value = ERROS.ANDAMENTO;
    await flushPromises();

    await w
      .get(`${daCarteira('trazendo-seguros')} ${daCarteira('erro')} button`)
      .trigger('click');

    expect(tela.tentarDeNovo).toHaveBeenCalledTimes(1);
  });
});

describe('o que o Conferir com seguros avisa', () => {
  it('a conta que está desfazendo uma lista é dita como alerta', () => {
    const tela = telaDeMentira({
      leitura: ref(leituraConferida()),
      erro: ref(ERROS.DESFAZER_EM_CURSO),
    });
    const { w } = abrir(tela);

    const alerta = w.get(daCarteira('recusa-do-trazer'));
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'Tem uma lista sendo desfeita agora. Espere o Desfazer terminar e tente de novo.'
    );
  });

  it('os seguros que estão cancelados na carteira ficam como estão, e a tela diz quantos', () => {
    const leitura = leituraConferida();
    leitura.resumo = { ...leitura.resumo, cancelados: 2 };
    const { w } = abrir(telaDeMentira({ leitura: ref(leitura) }));

    expect(w.get(daCarteira('seguros-cancelados')).text()).toBe(
      '2 seguros desta planilha estão cancelados aqui e ficam como estão.'
    );
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

  it('antes de enviar, e enquanto a planilha é lida, a tela é a das listas', () => {
    const tela = telaDeMentira({ etapa: ref(ETAPAS.ENVIAR) });
    const carteira = passoDe(tela);

    expect(carteira.passo.value).toBe(null);
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
    tela.leitura.value = leituraSugerida();
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
    expect(carteira.passo.value).toBe(PASSOS.CONFERIR);
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

  it('a lista que só trouxe pessoas é trazida e termina na tela das listas', () => {
    const tela = telaDeMentira({ leitura: ref(DAS_PESSOAS) });
    const carteira = passoDe(tela);

    carteira.trazer();
    tela.etapa.value = ETAPAS.TRAZENDO;
    expect(carteira.passo.value).toBe(null);
    tela.etapa.value = ETAPAS.PRONTO;

    expect(tela.trazer).toHaveBeenCalledTimes(1);
    expect(carteira.passo.value).toBe(null);
  });

  it('com coluna obrigatória faltando no servidor, o trazer não é pedido', () => {
    const tela = telaDeMentira({ leitura: ref(leituraSugerida()) });
    const carteira = passoDe(tela);

    carteira.trazer();

    expect(tela.trazer).not.toHaveBeenCalled();
  });

  it('a conta do servidor que chega depois de a tela estar no fim aparece (a fonte é reativa)', async () => {
    const chegou = ref(null);
    const tela = telaDeMentira({ leitura: ref(leituraConferida()) });
    const carteira = passoDe(tela, { fonte: { chegaram: () => chegou.value } });
    carteira.trazer();
    tela.etapa.value = ETAPAS.PRONTO;
    const { seguros } = leituraConferida().resumo;
    expect(carteira.chegaram.value.seguros).toBe(seguros);

    chegou.value = { seguros: 4, pessoas: 3, pessoasNovas: 1 };
    await nextTick();

    expect(carteira.chegaram.value).toEqual(chegou.value);
  });
});

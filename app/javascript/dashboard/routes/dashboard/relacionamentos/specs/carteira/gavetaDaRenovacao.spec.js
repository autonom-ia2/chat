import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import GavetaDaRenovacao from '../../components/carteira/renovacao/GavetaDaRenovacao.vue';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { COMO_ENVIA } from '../../carteira/ajustesDaRenovacao';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { salvarAjustesNaDemo } from '../../demo/carteiraAjustes';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  textoDe,
} from './apoio';

// A renovação de um seguro na gaveta (#2897, telas 11 e 12), com a carteira
// fictícia e o texto de verdade em pt_BR: a cotação num estado de cada vez, a
// conferência antes de enviar, "Renovou" e "Não renovou" com desfazer, e
// carregando, erro e "não está mais aqui".
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('vue-router', () => {
  const roteador = { push: vi.fn() };
  return { useRouter: () => roteador, useRoute: () => ({ query: {} }) };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const ENVIADA_POR_ALGUEM = 1;
const SEM_RENOVACAO = 2;
const RENOVADO = 102;
const SEM_TELEFONE = 104;
const NAO_QUER_MENSAGENS = 105;
const COTANDO = 107;
const FALTOU_DADO = 110;
const AINDA_NAO_COMECOU = 111;
const PRONTA = 112;
const ENVIADA_SOZINHA = 113;

const fonteDaDemo = (opcoes = {}) =>
  carteiraFonte({ demo: 'cheio', atraso: 0, ...opcoes });

let aberta;
const abrir = async (seguroId, fonte = fonteDaDemo()) => {
  aberta = mount(GavetaDaRenovacao, {
    attachTo: document.body,
    props: { seguroId, fonte },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const clicar = async (w, nome) => {
  await w.get(daCarteira(nome)).trigger('click');
  await assentar();
};
const cotacao = w => w.get(daCarteira('cotacao'));
// A fonte responde depois de um instante: com o relógio do teste, é preciso
// deixar o tempo andar.
const historiaDe = async id => {
  const pedido = fonteDaDemo().historia(id);
  await assentar();
  return pedido;
};
const aviso = w => textoDe(w, daCarteira('aviso-vivo'));

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  vi.clearAllMocks();
});

describe('a renovação na gaveta', () => {
  it('diz de quem é, em que pé está, quem cuida e qual é o seguro, sem nome de mecanismo', async () => {
    const w = await abrir(ENVIADA_POR_ALGUEM);

    expect(textoDe(w, '[data-view-title]')).toBe('Renovação do seguro Auto');
    expect(w.get(daCarteira('pessoa-da-renovacao')).text()).toBe(
      'Fábio Kalinoski'
    );
    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'As opções já foram enviadas. Falta a resposta.'
    );
    expect(textoDe(w, daCarteira('quem-cuida'))).toBe(
      'Quem cuida: Bia Lunardelli'
    );
    const seguro = textoDe(w, daCarteira('seguro-da-renovacao'));
    expect(seguro).toContain('Auto · Seguradora Atlântica · nº AT-000451');
    expect(seguro).toContain('Vence em 18 dias');
    const tudo = w.get(daCarteira('card-renovacao')).text();
    ['Funil', 'funil', 'etapa', 'Opções enviadas'].forEach(palavra =>
      expect(tudo).not.toContain(palavra)
    );
  });

  it('o link da pessoa leva à ficha dela; "Abrir no CRM" e "Ver apólice" avisam o que vão abrir', async () => {
    const w = await abrir(ENVIADA_POR_ALGUEM);

    await clicar(w, 'pessoa-da-renovacao');
    expect(w.emitted('abrirSegurado')).toEqual([[{ tipo: 'pessoa', id: 23 }]]);
    await clicar(w, 'abrir-no-crm');
    await clicar(w, 'ver-apolice');
    expect(useAlert.mock.calls.map(([texto]) => texto)).toEqual([
      'Abrindo a renovação no CRM',
      'Abrindo o PDF do seguro Auto',
    ]);
  });

  it('nenhuma tela da renovação fala de custo, preço de consulta ou limite de uso', async () => {
    const w = await abrir(AINDA_NAO_COMECOU);
    const tudo = w.text().toLowerCase();

    ['consulta', 'custa', 'custo', 'limite', 'teto', 'crédito'].forEach(
      palavra => expect(tudo).not.toContain(palavra)
    );
  });

  it('carregando: o esqueleto; erro: a frase e "Tentar de novo"; sem renovação: diz e deixa voltar', async () => {
    const carregando = await abrir(
      ENVIADA_POR_ALGUEM,
      fonteDaDemo({ peca: 'carregando' })
    );
    expect(textoDe(carregando, '[data-view-title]')).toBe(
      'Abrindo a renovação'
    );
    expect(carregando.find(daCarteira('carregando')).exists()).toBe(true);
    expect(carregando.find(daCarteira('renovou')).exists()).toBe(false);
    carregando.unmount();

    const comErro = await abrir(
      ENVIADA_POR_ALGUEM,
      fonteDaDemo({ peca: 'erro' })
    );
    const erro = comErro.get(
      `${daCarteira('card-renovacao')} ${doBlocoA('erro')}`
    );
    expect(erro.text()).toContain(
      'Não consegui abrir esta renovação. Tente de novo.'
    );
    expect(erro.get('button').text()).toBe('Tentar de novo');
    comErro.unmount();

    const semRenovacao = await abrir(SEM_RENOVACAO);
    expect(semRenovacao.get(daCarteira('renovacao-nao-esta')).text()).toContain(
      'Esta renovação não está mais aqui.'
    );
    await semRenovacao
      .get(`${daCarteira('renovacao-nao-esta')} button`)
      .trigger('click');
    expect(semRenovacao.emitted('fechar')).toHaveLength(1);
  });
});

describe('a cotação, um estado de cada vez', () => {
  it('cotando: só diz que está cotando; a ação principal é "Renovou"', async () => {
    const w = await abrir(COTANDO);

    expect(cotacao(w).attributes('data-cotacao')).toBe('COTANDO');
    expect(cotacao(w).get('[role="status"]').text()).toBe(
      'Cotando… pode levar alguns minutos.'
    );
    expect(cotacao(w).find('button').exists()).toBe(false);
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
    expect(w.get(daCarteira('renovou')).text()).toBe('Renovou');
  });

  it('proposta pronta: a ação principal é enviar, com a conferência antes; depois, o aviso e a história', async () => {
    const w = await abrir(PRONTA);

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Resumo da cotação pronto: Seguradora Atlântica, R$ 3.580,50 por ano.'
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Subiu 5% em relação ao ano passado.'
    );
    expect(w.get(daCarteira('ver-proposta')).text()).toBe('Ver resumo');
    // Sem supor o gênero: o botão fala com o nome da pessoa.
    expect(w.get(daCarteira('enviar-ao-cliente')).text()).toBe(
      'Enviar a Paula'
    );

    await clicar(w, 'enviar-ao-cliente');
    const previa = w.get(daCarteira('previa-envio'));
    expect(previa.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Enviar a proposta a Paula Aguiardo'
    );
    expect(textoDe(w, daCarteira('previa-envio'))).toContain(
      'Oi, Paula! Aqui está a renovação do seu seguro Auto: Seguradora Atlântica, R$ 3.580,50 por ano. O resumo vai junto, em PDF. Posso seguir?'
    );
    expect(previa.text()).toContain('Resumo da cotação.pdf');
    expect(w.get(daCarteira('enviar')).text()).toBe('Enviar');

    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();

    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    expect(aviso(w)).toBe('Proposta enviada a Paula Aguiardo.');
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(cotacao(w).attributes('data-cotacao')).toBe('ENVIADA_POR_VOCE');
    expect(cotacao(w).text()).toContain('Proposta enviada por você em ');
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'As opções já foram enviadas. Falta a resposta.'
    );
    const historia = await historiaDe(PRONTA);
    expect(historia[0]).toMatchObject({
      tipo: 'proposta_enviada',
      quem: { papel: 'voce' },
    });
  });

  it('enviada por alguém e enviada sozinha: diz quem e quando, sem nada para apertar', async () => {
    const porAlguem = await abrir(ENVIADA_POR_ALGUEM);
    expect(cotacao(porAlguem).text()).toContain(
      'Proposta enviada por Bia Lunardelli em '
    );
    expect(cotacao(porAlguem).text()).toContain(
      'Subiu 8% em relação ao ano passado.'
    );
    expect(porAlguem.get(daCarteira('ver-proposta')).text()).toBe('Ver resumo');
    porAlguem.unmount();

    const sozinha = await abrir(ENVIADA_SOZINHA);
    expect(cotacao(sozinha).attributes('data-cotacao')).toBe('ENVIADA_SOZINHA');
    expect(cotacao(sozinha).text()).toContain('Proposta enviada sozinha em ');
    expect(cotacao(sozinha).text()).toContain(
      'Baixou 3% em relação ao ano passado.'
    );
    expect(sozinha.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
  });

  it('quem escolheu "sai sozinha" não confere nada: a proposta pronta já saiu e a história conta', async () => {
    salvarAjustesNaDemo({ comoEnvia: COMO_ENVIA.SOZINHA });

    const w = await abrir(PRONTA);

    expect(cotacao(w).attributes('data-cotacao')).toBe('ENVIADA_SOZINHA');
    expect(cotacao(w).text()).toContain('Proposta enviada sozinha em ');
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    const tipos = (await historiaDe(PRONTA)).map(p => p.tipo);
    expect(tipos).toContain('proposta_enviada_sozinha');
    // Quem está sem telefone ou pediu para não receber fica de fora.
    aberta.unmount();
    const semTelefone = await abrir(SEM_TELEFONE);
    expect(cotacao(semTelefone).attributes('data-cotacao')).toBe(
      'SEM_TELEFONE'
    );
  });

  it('faltou um dado: com quem atende sozinho, só informa; sem, pede o dado e cota com ele', async () => {
    const perguntado = await abrir(FALTOU_DADO);
    expect(textoDe(perguntado, daCarteira('cotacao'))).toContain(
      'Faltou um dado para cotar: a data de nascimento de Marina.'
    );
    expect(textoDe(perguntado, daCarteira('cotacao'))).toContain(
      'Nina já perguntou.'
    );
    expect(perguntado.find(daCarteira('cotar-com-dado')).exists()).toBe(false);
    perguntado.unmount();

    const w = await abrir(
      FALTOU_DADO,
      fonteDaDemo({ caso: 'cotacao_sem_agente' })
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Pergunte e escreva aqui.'
    );
    const dado = w.get(daCarteira('dado-que-faltou'));
    const botao = w.get(daCarteira('cotar-com-dado'));
    expect(botao.attributes('disabled')).toBeUndefined();

    // Sem o dado, o clique diz o que falta e leva o foco até lá.
    await botao.trigger('click');
    const falta = cotacao(w).get('[role="alert"]');
    expect(falta.text()).toBe('Escreva o dado que faltou.');
    expect(dado.attributes('aria-invalid')).toBe('true');
    expect(dado.attributes('aria-describedby')).toBe(falta.attributes('id'));
    expect(document.activeElement).toBe(dado.element);

    await dado.setValue('12/03/1988');
    await clicar(w, 'cotar-com-dado');
    expect(cotacao(w).attributes('data-cotacao')).toBe('COTANDO');
  });

  it('algumas seguradoras já responderam: mostra cada uma e pede a proposta da escolhida', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_parcial' })
    );

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      '3 seguradoras já deram preço.'
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      '2 ainda não responderam.'
    );
    const linhas = w.findAll(`${daCarteira('respostas-da-cotacao')} li`);
    expect(linhas).toHaveLength(5);
    expect(textoDe(w, daCarteira('respostas-da-cotacao'))).toContain(
      'Seguradora AtlânticaR$ 546,00'
    );
    expect(linhas[2].text()).toContain(
      'Esta seguradora não dá proposta em PDF. O que vai à pessoa é o resumo.'
    );
    expect(linhas[2].find(daCarteira('pedir-proposta')).exists()).toBe(false);
    expect(linhas[4].text()).toContain('ainda não respondeu');
    const pedir = linhas[1].get(daCarteira('pedir-proposta'));
    expect(pedir.text()).toBe('Pedir a proposta desta');
    expect(pedir.attributes('aria-label')).toBe(
      'Pedir a proposta: Serra Azul Seguros'
    );

    await pedir.trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Proposta pronta: Serra Azul Seguros, R$ 566,80 por ano.'
    );
    expect(w.get(daCarteira('ver-proposta')).text()).toBe('Ver proposta');
    await clicar(w, 'enviar-ao-cliente');
    expect(w.get(daCarteira('previa-envio')).text()).toContain(
      'A proposta vai junto, em PDF.'
    );
  });

  it.each([
    [
      'cotacao_sem_pdf',
      'O preço chegou: Seguradora Atlântica, R$ 546,00 por ano. O PDF do resumo não veio.',
      'pedir-pdf',
      'Pedir o PDF de novo',
      'PRONTA',
    ],
    [
      'cotacao_demorou',
      'A cotação demorou e parou. Tente de novo.',
      'cotar-de-novo',
      'Cotar de novo',
      'COTANDO',
    ],
    [
      'cotacao_falhou',
      'Não consegui cotar. Tente de novo.',
      'cotar-de-novo',
      'Cotar de novo',
      'COTANDO',
    ],
  ])(
    '%s: diz o que houve e o botão resolve',
    async (caso, frase, marca, rotulo, depois) => {
      const w = await abrir(AINDA_NAO_COMECOU, fonteDaDemo({ caso }));

      expect(textoDe(w, daCarteira('cotacao'))).toContain(frase);
      expect(w.get(daCarteira(marca)).text()).toBe(rotulo);
      await clicar(w, marca);
      expect(cotacao(w).attributes('data-cotacao')).toBe(depois);
    }
  );

  it('só o preço, sem o PDF: dá para enviar o preço, e a prévia sai sem arquivo', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_sem_pdf' })
    );

    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'O preço chegou. O PDF não veio.'
    );
    // "Pedir o PDF de novo" continua no bloco da cotação.
    expect(w.get(daCarteira('pedir-pdf')).text()).toBe('Pedir o PDF de novo');
    const enviar = w.get(daCarteira('enviar-ao-cliente'));
    expect(enviar.text()).toMatch('Enviar a ');
    const primeiroNome = enviar.text().split(' ').at(-1);

    await clicar(w, 'enviar-ao-cliente');
    const previa = w.get(daCarteira('previa-envio'));
    expect(textoDe(w, daCarteira('previa-de-mensagem'))).toBe(
      `Oi, ${primeiroNome}! Aqui está a renovação do seu seguro Residencial: Seguradora Atlântica, R$ 546,00 por ano. Posso seguir?`
    );
    expect(previa.text()).not.toContain('.pdf');
    expect(previa.text()).not.toContain('vai junto');

    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();

    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    expect(aviso(w)).toMatch('Proposta enviada a ');
    expect(cotacao(w).attributes('data-cotacao')).toBe('ENVIADA_POR_VOCE');
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
  });

  it('Agger fora do ar: leva a entrar no Agger de novo', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_agger_fora' })
    );

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Não consegui entrar no Agger. Sem ele não dá para cotar.'
    );
    await clicar(w, 'entrar-no-agger');
    expect(useRouter().push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
      query: { como: 'agger' },
    });
  });

  it('conta que não cota sozinha: a equipe põe a proposta; conta que cota oferece "Cotar agora"', async () => {
    const naoCota = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ cotacaoDesligada: true })
    );
    expect(textoDe(naoCota, daCarteira('cotacao'))).toContain(
      'Faça a cotação e ponha a proposta aqui.'
    );
    expect(textoDe(naoCota, daCarteira('cotacao'))).not.toContain(
      'não cota sozinha'
    );
    await clicar(naoCota, 'anexar-proposta');
    expect(textoDe(naoCota, daCarteira('cotacao'))).toContain(
      'Proposta pronta: Seguradora Atlântica, '
    );
    expect(naoCota.find(daCarteira('enviar-ao-cliente')).exists()).toBe(true);
    naoCota.unmount();
    esquecerEscritasDaCarteira();

    const cota = await abrir(AINDA_NAO_COMECOU);
    expect(textoDe(cota, daCarteira('cotacao'))).toContain(
      'A cotação ainda não começou.'
    );
    await clicar(cota, 'cotar-agora');
    expect(cotacao(cota).attributes('data-cotacao')).toBe('COTANDO');
  });

  it('sem telefone e "não quer mensagens": diz por que a proposta não chega e o que fazer', async () => {
    const semTelefone = await abrir(SEM_TELEFONE);
    expect(textoDe(semTelefone, daCarteira('cotacao'))).toContain(
      ' está sem telefone. A proposta não chega.'
    );
    await clicar(semTelefone, 'por-o-telefone');
    expect(semTelefone.emitted('abrirSegurado')).toEqual([
      [{ tipo: 'pessoa', id: 59 }],
    ]);
    semTelefone.unmount();

    const naoQuer = await abrir(NAO_QUER_MENSAGENS);
    expect(textoDe(naoQuer, daCarteira('cotacao'))).toContain(
      ' pediu para não receber mensagens. A proposta não sai sozinha. Envie na conversa.'
    );
    await clicar(naoQuer, 'conversar-sobre-a-proposta');
    expect(useAlert.mock.calls[0][0]).toMatch('Abrindo a conversa com ');
  });
});

describe('o título da gaveta não contradiz a cotação logo abaixo', () => {
  it.each([
    [AINDA_NAO_COMECOU, {}, 'A renovação ainda não começou.'],
    [COTANDO, {}, 'A cotação está sendo feita.'],
    [PRONTA, {}, 'A cotação está pronta. Falta enviar.'],
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_parcial' },
      'Os preços estão chegando.',
    ],
    [FALTOU_DADO, {}, 'Falta um dado para cotar.'],
    [FALTOU_DADO, { caso: 'cotacao_sem_agente' }, 'Falta um dado para cotar.'],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_agger_fora' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_demorou' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_falhou' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { cotacaoDesligada: true }, 'Falta a cotação.'],
    [SEM_TELEFONE, {}, 'A proposta está pronta. Falta o telefone.'],
    [NAO_QUER_MENSAGENS, {}, 'A proposta está pronta. Envie na conversa.'],
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_sem_pdf' },
      'O preço chegou. O PDF não veio.',
    ],
  ])('seguro %i com %j: "%s"', async (id, opcoes, titulo) => {
    const w = await abrir(id, fonteDaDemo(opcoes));

    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(titulo);
  });
});

describe('como a renovação termina', () => {
  it('"Renovou" não pede confirmação; o aviso traz "Desfazer", que devolve como estava', async () => {
    const w = await abrir(PRONTA);
    // Com proposta esperando, a ação principal é enviar; "Renovou" vem depois.
    const botoes = w
      .findAll('footer button[data-carteira]')
      .map(botao => botao.attributes('data-carteira'));
    expect(botoes).toEqual(['enviar-ao-cliente', 'renovou', 'nao-renovou']);

    await clicar(w, 'renovou');

    expect(aviso(w)).toContain('Renovação marcada.');
    expect(textoDe(w, daCarteira('como-terminou'))).toBe(
      'Renovou. A apólice nova chega sozinha na próxima busca do Agger.'
    );
    expect(w.find(daCarteira('cotacao')).exists()).toBe(false);
    expect(w.find(daCarteira('renovou')).exists()).toBe(false);
    expect(w.find(daCarteira('anexar-apolice-nova')).exists()).toBe(false);

    await clicar(w, 'desfazer');

    expect(aviso(w)).toBe('Desfeito.');
    expect(w.find(daCarteira('como-terminou')).exists()).toBe(false);
    expect(w.get(daCarteira('enviar-ao-cliente')).text()).toBe(
      'Enviar a Paula'
    );
    expect((await historiaDe(PRONTA)).map(p => p.tipo)).not.toContain(
      'renovou'
    );
  });

  it('renovado que veio de planilha: falta a apólice nova, e o botão principal a anexa', async () => {
    const w = await abrir(RENOVADO);

    expect(textoDe(w, daCarteira('como-terminou'))).toBe(
      'Renovou. Falta a apólice nova.'
    );
    expect(w.get(daCarteira('anexar-apolice-nova')).text()).toBe(
      'Anexar a apólice nova'
    );
    await clicar(w, 'anexar-apolice-nova');
    expect(w.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Anexar a apólice nova'
    );
  });

  it('"Não renovou" pergunta o motivo; um toque guarda, fecha e deixa desfazer', async () => {
    const w = await abrir(ENVIADA_POR_ALGUEM);

    await clicar(w, 'nao-renovou');
    const dialogo = w.get(daCarteira('motivo'));
    expect(dialogo.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Por que não renovou?'
    );
    expect(
      [
        'motivo-caro',
        'motivo-outra',
        'motivo-vendeu',
        'motivo-nao-respondeu',
      ].map(marca => w.get(daCarteira(marca)).text())
    ).toEqual([
      'Achou caro',
      'Foi para outra corretora',
      'Vendeu o bem',
      'Não respondeu',
    ]);

    await clicar(w, 'motivo-caro');

    expect(w.find(daCarteira('motivo')).exists()).toBe(false);
    expect(aviso(w)).toContain('Não renovou: achou caro.');
    expect(textoDe(w, daCarteira('como-terminou'))).toBe(
      'Não renovou: achou caro.'
    );
    expect(w.find(daCarteira('renovou')).exists()).toBe(false);
    const historia = await historiaDe(ENVIADA_POR_ALGUEM);
    expect(historia[0]).toMatchObject({
      tipo: 'nao_renovou',
      valores: { motivo: 'achou_caro' },
    });

    await clicar(w, 'desfazer');
    expect(w.find(daCarteira('como-terminou')).exists()).toBe(false);
    expect(w.get(daCarteira('nao-renovou')).text()).toBe('Não renovou');
  });

  it('"Outro motivo": Salvar fica ligado; sem texto diz o que falta; com texto, guarda as palavras de quem escreveu', async () => {
    const w = await abrir(ENVIADA_POR_ALGUEM);
    await clicar(w, 'nao-renovou');
    expect(w.find(daCarteira('salvar-motivo')).exists()).toBe(false);

    await clicar(w, 'motivo-outro');
    const texto = w.get(daCarteira('motivo-escrito'));
    expect(document.activeElement).toBe(texto.element);
    const salvar = w.get(daCarteira('salvar-motivo'));
    expect(salvar.attributes('disabled')).toBeUndefined();

    await w.get('[data-dialogo-falso]').trigger('submit');
    expect(w.get(`${daCarteira('motivo')} [role="alert"]`).text()).toBe(
      'Escreva o motivo.'
    );
    expect(texto.attributes('aria-invalid')).toBe('true');
    expect(document.activeElement).toBe(texto.element);

    await texto.setValue('Mudou de cidade');
    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();

    expect(aviso(w)).toContain('Não renovou: Mudou de cidade.');
    expect(textoDe(w, daCarteira('como-terminou'))).toBe(
      'Não renovou: Mudou de cidade.'
    );
    const historia = await historiaDe(ENVIADA_POR_ALGUEM);
    expect(historia[0]).toMatchObject({
      tipo: 'nao_renovou_outro',
      valores: { texto: 'Mudou de cidade' },
    });
  });
});

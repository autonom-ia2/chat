import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import GavetaDaRenovacao from '../../components/carteira/renovacao/GavetaDaRenovacao.vue';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { COMO_ENVIA } from '../../carteira/ajustesDaRenovacao';
import {
  esquecerEscritasDaCarteira,
  segurosDaCarteira,
} from '../../demo/carteira';
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
const FALTAM_DADOS = 110;
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
// O botão azul (o principal da casa): só pode haver um por vez na gaveta.
const AZUL = 'bg-n-blue-11';
const azuis = w =>
  w
    .findAll('button')
    .filter(botao => botao.classes().includes(AZUL))
    .map(botao => botao.attributes('data-carteira'));
const doRodape = w =>
  w
    .findAll('footer button[data-carteira]')
    .map(botao => botao.attributes('data-carteira'));

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
    // O número da apólice não quebra no hífen.
    const numero = w.get(
      `${daCarteira('seguro-da-renovacao')} ${daCarteira('numero-da-apolice')}`
    );
    expect(numero.text()).toBe('nº AT-000451');
    expect(numero.classes()).toContain('whitespace-nowrap');
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
    // Não há o que apertar agora: nenhum botão azul. "Renovou" e "Não renovou"
    // continuam no rodapé.
    expect(azuis(w)).toEqual([]);
    expect(doRodape(w)).toEqual(['renovou', 'nao-renovou']);
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
      'Enviar o resumo a Paula Aguiardo'
    );
    expect(textoDe(w, daCarteira('previa-envio'))).toContain(
      'Oi, Paula! Cotei a renovação do seu seguro Auto: Seguradora Atlântica, R$ 3.580,50 por ano. O resumo vai junto, em PDF. Quer renovar com esse preço?'
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
    // Depois de as opções saírem, o passo da vez é "Renovou".
    expect(azuis(w)).toEqual(['renovou']);
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

  it('faltam dados e o agente já perguntou: diz quem perguntou e a lista do que falta, sem nada azul', async () => {
    const w = await abrir(FALTAM_DADOS);

    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'Faltam dados para cotar.'
    );
    const faltam = w.get(daCarteira('dados-que-faltam'));
    expect(faltam.text()).toContain('Nina já perguntou à pessoa.');
    expect(faltam.findAll('li').map(item => item.text())).toEqual([
      'Placa do carro',
      'Data de nascimento',
      'Estado civil',
      'Quem dirige o carro',
      'Onde o carro dorme',
      'Quanto roda por mês',
    ]);
    expect(w.find(daCarteira('dado-que-faltou')).exists()).toBe(false);
    expect(azuis(w)).toEqual([]);

    // Quem prefere preencher sem esperar a resposta abre os espaços, e o passo
    // da vez vira "Cotar com estes dados".
    await clicar(w, 'preencher-os-dados');
    expect(w.findAll(daCarteira('dado-que-faltou'))).toHaveLength(6);
    expect(azuis(w)).toEqual(['cotar-com-dado']);
  });

  it('faltam dados e ninguém perguntou: um espaço por dado e UM botão; vazio, diz qual falta e leva o foco', async () => {
    const w = await abrir(
      FALTAM_DADOS,
      fonteDaDemo({ caso: 'cotacao_sem_agente' })
    );

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Pergunte e escreva aqui.'
    );
    const espacos = w.findAll(daCarteira('dado-que-faltou'));
    expect(espacos.map(espaco => espaco.attributes('data-dado'))).toEqual([
      'placa',
      'nascimento',
      'estado_civil',
      'quem_dirige',
      'onde_dorme',
      'quanto_roda',
    ]);
    const botao = w.get(daCarteira('cotar-com-dado'));
    expect(botao.text()).toBe('Cotar com estes dados');
    expect(botao.attributes('disabled')).toBeUndefined();
    expect(azuis(w)).toEqual(['cotar-com-dado']);
    // O botão é um só: não há outro igual dentro do bloco da cotação.
    expect(cotacao(w).find('button').exists()).toBe(false);

    // Tudo vazio: aponta o primeiro.
    await clicar(w, 'cotar-com-dado');
    const falta = cotacao(w).get('[role="alert"]');
    expect(falta.text()).toBe('Escreva a placa do carro.');
    expect(espacos[0].attributes('aria-invalid')).toBe('true');
    expect(espacos[0].attributes('aria-describedby')).toBe(
      falta.attributes('id')
    );
    expect(document.activeElement).toBe(espacos[0].element);

    // Com a placa escrita, o que falta é o seguinte.
    await espacos[0].setValue('FIC-0B10');
    await clicar(w, 'cotar-com-dado');
    expect(cotacao(w).findAll('[role="alert"]')).toHaveLength(1);
    expect(cotacao(w).get('[role="alert"]').text()).toBe(
      'Escreva a data de nascimento.'
    );
    expect(document.activeElement).toBe(espacos[1].element);
    expect(cotacao(w).attributes('data-cotacao')).toBe('FALTOU_SEM_AGENTE');

    await espacos[1].setValue('12/03/1988');
    await espacos[2].setValue('casada');
    await espacos[3].setValue('só ela');
    await espacos[4].setValue('na garagem');
    await espacos[5].setValue('800 km');
    await clicar(w, 'cotar-com-dado');
    expect(cotacao(w).attributes('data-cotacao')).toBe('COTANDO');
  });

  it('no residencial faltam o endereço e o tipo do imóvel; com um dado só, o título fica no singular', async () => {
    const casa = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_faltam_dados' })
    );
    expect(
      casa
        .findAll(`${daCarteira('dados-para-preencher')} label`)
        .map(rotulo => rotulo.text())
    ).toEqual(['Endereço do imóvel', 'Tipo do imóvel']);
    expect(textoDe(casa, daCarteira('situacao-da-renovacao'))).toBe(
      'Faltam dados para cotar.'
    );
    casa.unmount();

    const umSo = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_falta_um_dado' })
    );
    expect(textoDe(umSo, daCarteira('situacao-da-renovacao'))).toBe(
      'Falta um dado para cotar.'
    );
    expect(umSo.findAll(daCarteira('dado-que-faltou'))).toHaveLength(1);
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
      'Seguradora AtlânticaR$ 546,00 por ano'
    );
    expect(linhas[2].text()).toContain(
      'Esta seguradora não tem proposta em PDF. Vai o resumo da cotação, com preço e coberturas.'
    );
    expect(linhas[2].find(daCarteira('pedir-proposta')).exists()).toBe(false);
    // Antes do prazo, quem falta "ainda não respondeu".
    expect(linhas[4].text()).toContain('Ainda não respondeu');
    const pedir = linhas[1].get(daCarteira('pedir-proposta'));
    expect(pedir.text()).toBe('Pedir a proposta desta');
    expect(pedir.attributes('aria-label')).toBe(
      'Pedir a proposta: Serra Azul Seguros'
    );
    // Um azul só: o da seguradora de menor preço. O rodapé fica sem azul.
    expect(azuis(w)).toEqual(['pedir-proposta']);
    expect(linhas[0].get(daCarteira('pedir-proposta')).classes()).toContain(
      AZUL
    );
    expect(doRodape(w)).toEqual(['renovou', 'nao-renovou']);

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
    // Vai a proposta oficial: o título da conferência diz "proposta".
    expect(w.get(doBlocoA('titulo-do-dialogo')).text()).toMatch(
      'Enviar a proposta a '
    );
  });

  it('depois do prazo: "Não respondeu a tempo", quem não aceitou à parte com o motivo, e a senha que falta no Agger', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_parcial_prazo' })
    );

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      '2 seguradoras já deram preço.'
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      '1 não respondeu a tempo.'
    );
    const linhas = w.findAll(`${daCarteira('respostas-da-cotacao')} li`);
    expect(linhas).toHaveLength(3);
    expect(linhas[2].text()).toBe('Horizonte SegurosNão respondeu a tempo');
    expect(w.text()).not.toContain('Ainda não respondeu');

    const recusaram = w.get(daCarteira('seguradoras-que-recusaram'));
    expect(recusaram.get('h4').text()).toBe('Não aceitaram');
    expect(recusaram.get('li').text()).toBe(
      'Seguradora Ponte NovaNão aceita este imóvel'
    );

    const semSenha = w.get(daCarteira('seguradoras-sem-senha'));
    expect(semSenha.text()).toContain(
      'Falta a senha da Seguradora Monte Claro no seu Agger'
    );
    const comoResolver = semSenha.get(daCarteira('agger-como-resolver'));
    expect(comoResolver.text()).toBe('Como resolver');
    expect(comoResolver.attributes('aria-label')).toBe(
      'Como resolver a senha da Seguradora Monte Claro'
    );

    // O mesmo caminho do Trazer: o que fazer no Agger e um botão para a volta.
    await comoResolver.trigger('click');
    const dialogo = w.get(daCarteira('agger-dialogo-senha'));
    expect(dialogo.text()).toContain('Falta a senha da Seguradora Monte Claro');
    expect(dialogo.text()).toContain(
      'Entre no seu Agger, guarde a senha da Seguradora Monte Claro e volte aqui. Depois, cote de novo.'
    );
    expect(w.get(daCarteira('cotar-de-novo-com-a-senha')).text()).toBe(
      'Cotar de novo'
    );
    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();
    expect(cotacao(w).attributes('data-cotacao')).toBe('COTANDO');
  });

  it.each([
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
    '%s: diz o que houve e o botão azul resolve',
    async (caso, frase, marca, rotulo, depois) => {
      const w = await abrir(AINDA_NAO_COMECOU, fonteDaDemo({ caso }));

      expect(textoDe(w, daCarteira('cotacao'))).toContain(frase);
      expect(w.get(daCarteira(marca)).text()).toBe(rotulo);
      expect(azuis(w)).toEqual([marca]);
      expect(doRodape(w)).toEqual([marca, 'renovou', 'nao-renovou']);
      await clicar(w, marca);
      expect(cotacao(w).attributes('data-cotacao')).toBe(depois);
    }
  );

  it('seguradora sem proposta em PDF: vai o resumo; o botão azul é "Enviar o resumo" e a prévia sai sem arquivo', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_sem_pdf' })
    );

    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'O preço chegou. Falta enviar.'
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'O preço chegou: Seguradora Atlântica, R$ 546,00 por ano.'
    );
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Esta seguradora não tem proposta em PDF. Vai o resumo da cotação, com preço e coberturas.'
    );
    // "Pedir o PDF de novo" não existe mais.
    expect(w.find(daCarteira('pedir-pdf')).exists()).toBe(false);
    expect(w.text()).not.toContain('Pedir o PDF');
    expect(w.get(daCarteira('enviar-ao-cliente')).text()).toBe(
      'Enviar o resumo'
    );
    expect(azuis(w)).toEqual(['enviar-ao-cliente']);
    const primeiroNome = w
      .get(daCarteira('pessoa-da-renovacao'))
      .text()
      .split(' ')[0];

    // O que sai é o resumo da cotação em PDF, com preço e coberturas: a
    // prévia é a do resumo, com o arquivo e o título dizendo isso.
    await clicar(w, 'enviar-ao-cliente');
    const previa = w.get(daCarteira('previa-envio'));
    expect(previa.get(doBlocoA('titulo-do-dialogo')).text()).toMatch(
      `Enviar o resumo a ${primeiroNome}`
    );
    expect(textoDe(w, daCarteira('previa-de-mensagem'))).toContain(
      `Oi, ${primeiroNome}! Cotei a renovação do seu seguro Residencial: Seguradora Atlântica, R$ 546,00 por ano. O resumo vai junto, em PDF. Quer renovar com esse preço?`
    );
    expect(previa.text()).toContain('Resumo da cotação.pdf');

    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();

    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    expect(aviso(w)).toMatch('Proposta enviada a ');
    expect(cotacao(w).attributes('data-cotacao')).toBe('ENVIADA_POR_VOCE');
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
    // O que saiu foi o resumo: o link diz "Ver resumo".
    expect(w.get(daCarteira('ver-proposta')).text()).toBe('Ver resumo');
  });

  it('seguro por assinatura: o preço é "por mês" no card e na mensagem', async () => {
    const w = await abrir(
      AINDA_NAO_COMECOU,
      fonteDaDemo({ caso: 'cotacao_por_mes' })
    );

    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Resumo da cotação pronto: Seguradora Atlântica, R$ 45,50 por mês.'
    );
    await clicar(w, 'enviar-ao-cliente');
    expect(textoDe(w, daCarteira('previa-de-mensagem'))).toContain(
      'Seguradora Atlântica, R$ 45,50 por mês. O resumo vai junto, em PDF. Quer renovar com esse preço?'
    );
    expect(w.get(daCarteira('previa-envio')).text()).not.toContain('por ano');
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

  it('pessoa bloqueada: o mesmo tratamento de quem pediu para não receber', async () => {
    const w = await abrir(PRONTA, fonteDaDemo({ caso: 'pessoa_bloqueada' }));

    expect(cotacao(w).attributes('data-cotacao')).toBe('BLOQUEADO');
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'Alguém da equipe bloqueou Paula. A proposta não sai sozinha. Envie na conversa.'
    );
    expect(w.find(daCarteira('enviar-ao-cliente')).exists()).toBe(false);
    expect(azuis(w)).toEqual(['conversar-sobre-a-proposta']);
    await clicar(w, 'conversar-sobre-a-proposta');
    expect(useAlert.mock.calls[0][0]).toBe(
      'Abrindo a conversa com Paula Aguiardo'
    );
    // Com "sai sozinha" ligado, a proposta de quem está bloqueado não sai.
    aberta.unmount();
    salvarAjustesNaDemo({ comoEnvia: COMO_ENVIA.SOZINHA });
    const sozinha = await abrir(
      PRONTA,
      fonteDaDemo({ caso: 'pessoa_bloqueada' })
    );
    expect(cotacao(sozinha).attributes('data-cotacao')).toBe('ENVIADA_SOZINHA');
  });

  it('a proposta ia sair sozinha e não saiu: diz o que houve, oferece "Conversar" e a história conta', async () => {
    const fonte = fonteDaDemo({ caso: 'proposta_nao_saiu' });
    const w = await abrir(PRONTA, fonte);

    expect(cotacao(w).attributes('data-cotacao')).toBe('NAO_SAIU');
    expect(textoDe(w, daCarteira('cotacao'))).toContain(
      'O WhatsApp não deixou sair agora. A equipe foi avisada.'
    );
    expect(w.get(daCarteira('conversar-sobre-a-proposta')).text()).toBe(
      'Conversar'
    );
    expect(azuis(w)).toEqual(['conversar-sobre-a-proposta']);
    expect(doRodape(w)).toEqual([
      'conversar-sobre-a-proposta',
      'renovou',
      'nao-renovou',
    ]);

    const pedido = fonte.historia(PRONTA);
    await assentar();
    expect((await pedido).map(passo => passo.tipo)).toEqual([
      'proposta_nao_saiu',
      'proposta_pronta',
      'card_nasceu',
      'chegou_agger',
    ]);
  });

  it('a pessoa não escreve há mais de um dia: a prévia mostra o texto aprovado que sai e diz por quê', async () => {
    const w = await abrir(PRONTA, fonteDaDemo({ caso: 'fora_da_janela' }));

    expect(w.get(daCarteira('enviar-ao-cliente')).text()).toBe(
      'Enviar a Paula'
    );
    await clicar(w, 'enviar-ao-cliente');
    expect(w.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Enviar a proposta a Paula Aguiardo'
    );
    expect(w.get(daCarteira('nota-da-previa')).text()).toBe(
      'Faz mais de um dia que Paula não escreve. O WhatsApp só deixa sair esta mensagem.'
    );
    expect(textoDe(w, daCarteira('previa-de-mensagem'))).toBe(
      'Oi, Paula! A renovação do seu seguro Auto está pronta. Posso te mandar a proposta?'
    );
    expect(w.get(daCarteira('previa-envio')).text()).not.toContain('.pdf');
    expect(w.get(daCarteira('enviar')).text()).toBe('Enviar');

    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();
    expect(cotacao(w).attributes('data-cotacao')).toBe('ENVIADA_POR_VOCE');
  });

  it('dentro de um dia, a prévia não tem a nota', async () => {
    const w = await abrir(PRONTA);

    await clicar(w, 'enviar-ao-cliente');
    expect(w.find(daCarteira('nota-da-previa')).exists()).toBe(false);
  });

  it('"baixou em relação ao ano passado" só aparece quando a cobertura é a mesma', async () => {
    const mesma = await abrir(ENVIADA_SOZINHA);
    expect(cotacao(mesma).text()).toContain(
      'Baixou 3% em relação ao ano passado.'
    );
    mesma.unmount();

    const outra = await abrir(
      ENVIADA_SOZINHA,
      fonteDaDemo({ caso: 'cobertura_diferente' })
    );
    expect(cotacao(outra).attributes('data-cotacao')).toBe('ENVIADA_SOZINHA');
    expect(cotacao(outra).text()).not.toContain('ano passado');
  });
});

describe('o botão azul segue o passo da vez, um só', () => {
  it.each([
    [AINDA_NAO_COMECOU, {}, 'cotar-agora', 'Cotar agora'],
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_agger_fora' },
      'entrar-no-agger',
      'Entrar no Agger de novo',
    ],
    [
      AINDA_NAO_COMECOU,
      { cotacaoDesligada: true },
      'anexar-proposta',
      'Anexar proposta',
    ],
    [PRONTA, {}, 'enviar-ao-cliente', 'Enviar a Paula'],
    [SEM_TELEFONE, {}, 'por-o-telefone', 'Pôr o telefone'],
    [NAO_QUER_MENSAGENS, {}, 'conversar-sobre-a-proposta', 'Conversar'],
  ])('seguro %i com %j: o azul é "%s"', async (id, opcoes, marca, rotulo) => {
    const w = await abrir(id, fonteDaDemo(opcoes));

    expect(azuis(w)).toEqual([marca]);
    expect(w.get(daCarteira(marca)).text()).toBe(rotulo);
    // "Renovou" e "Não renovou" continuam no rodapé, como secundários.
    expect(doRodape(w)).toEqual([marca, 'renovou', 'nao-renovou']);
    // O passo não se repete dentro do bloco da cotação.
    expect(cotacao(w).find(daCarteira(marca)).exists()).toBe(false);
  });

  it.each([ENVIADA_POR_ALGUEM, ENVIADA_SOZINHA])(
    'seguro %i, depois de as opções saírem: o azul é "Renovou"',
    async id => {
      const w = await abrir(id);

      expect(azuis(w)).toEqual(['renovou']);
      expect(doRodape(w)).toEqual(['renovou', 'nao-renovou']);
    }
  );
});

describe('a conta só cota os tipos que ela cota', () => {
  it('nenhum seguro de vida (nem empresarial) aparece sendo cotado; a renovação dele pede a proposta anexada', async () => {
    const fonte = fonteDaDemo();
    const naoCotados = segurosDaCarteira().filter(
      seguro => seguro.renovacao && !fonte.tiposQueCota.includes(seguro.tipo)
    );

    expect(naoCotados.map(seguro => seguro.tipo)).toContain('vida');
    naoCotados.forEach(({ renovacao }) => {
      expect(renovacao.etapa).not.toBe('Cotando');
      expect(renovacao.cotando).toBe(false);
      expect(renovacao.faltou ?? []).toEqual([]);
    });

    const deVida = naoCotados.find(
      ({ tipo, renovacao }) => tipo === 'vida' && !renovacao.proposta
    );
    const w = await abrir(deVida.id, fonte);
    expect(cotacao(w).attributes('data-cotacao')).toBe('NAO_COTA');
    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'Falta a cotação.'
    );
    expect(azuis(w)).toEqual(['anexar-proposta']);
    expect(w.find(daCarteira('cotar-agora')).exists()).toBe(false);
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
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_parcial_prazo' },
      'Os preços chegaram.',
    ],
    [FALTAM_DADOS, {}, 'Faltam dados para cotar.'],
    [FALTAM_DADOS, { caso: 'cotacao_sem_agente' }, 'Faltam dados para cotar.'],
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_falta_um_dado' },
      'Falta um dado para cotar.',
    ],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_agger_fora' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_demorou' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { caso: 'cotacao_falhou' }, 'A cotação parou.'],
    [AINDA_NAO_COMECOU, { cotacaoDesligada: true }, 'Falta a cotação.'],
    [SEM_TELEFONE, {}, 'A proposta está pronta. Falta o telefone.'],
    [NAO_QUER_MENSAGENS, {}, 'A proposta está pronta. Envie na conversa.'],
    [
      PRONTA,
      { caso: 'pessoa_bloqueada' },
      'A proposta está pronta. Envie na conversa.',
    ],
    [
      PRONTA,
      { caso: 'proposta_nao_saiu' },
      'A proposta está pronta. Não saiu sozinha.',
    ],
    [
      AINDA_NAO_COMECOU,
      { caso: 'cotacao_sem_pdf' },
      'O preço chegou. Falta enviar.',
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

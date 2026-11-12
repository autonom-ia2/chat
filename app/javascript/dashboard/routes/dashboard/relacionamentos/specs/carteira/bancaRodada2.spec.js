import { defineComponent, effectScope, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useI18n } from 'vue-i18n';
import { withFullI18n } from 'test-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/relacionamentosCarteira.json';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import DadosQueFaltam from '../../components/carteira/renovacao/DadosQueFaltam.vue';
import GavetaDaRenovacao from '../../components/carteira/renovacao/GavetaDaRenovacao.vue';
import OndeFicamAsRenovacoes from '../../components/carteira/renovacao/OndeFicamAsRenovacoes.vue';
import { quemJaEstava } from '../../carteira/contagemDeSeguros';
import { COTACAO, cotacaoDoCard } from '../../carteira/cotacaoDoCard';
import {
  dadosEscritos,
  opcoesDoDado,
  primeiroDadoQueFalta,
  tipoDoCampo,
} from '../../carteira/dadosQueFaltam';
import { oQueNaoSaiu } from '../../carteira/oQueNaoSaiu';
import { PASSOS_DO_SEGURO, passoDoSeguro } from '../../carteira/passoDoSeguro';
import { DO_RODAPE, rodapeDoSeguro } from '../../carteira/rodapeDoSeguro';
import { tituloDaRenovacao } from '../../carteira/tituloDaRenovacao';
import { useTrazerSeguros } from '../../carteira/useTrazerSeguros';
import {
  esquecerEscritasDaCarteira,
  segurosDaCarteira,
} from '../../demo/carteira';
import { FUNIS_DA_DEMO } from '../../demo/carteiraAjustes';
import { comOCaso } from '../../demo/carteiraCasos';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { DIA_EM_MS } from '../../fonte/grupos';
import { CASOS_DA_DEMO } from '../../fonte/modoCarteira';
import { SELOS, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  semRolagem,
  textoDe,
} from './apoio';

// Os acertos pedidos pela banca na rodada 2 (#2897), com a carteira fictícia e
// o texto de verdade em pt_BR. Cada bloco é um item do pedido.
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
vi.setConfig({ testTimeout: 60000 });

const ATIVO_COM_PDF = 2;
const APOLICE_NOVA = 109;
const FALTAM_DADOS = 110;
const SEM_COTACAO = 111;
const PROPOSTA_PRONTA = 112;
const AZUL = 'bg-n-blue-11';
const AINDA_NAO_COMECOU = 'ainda não começou';

const fonteDaDemo = (opcoes = {}) =>
  carteiraFonte({ demo: 'cheio', atraso: 0, ...opcoes });

let aberta;
const abrirPeca = async (peca, props) => {
  aberta?.unmount();
  aberta = mount(peca, {
    attachTo: document.body,
    props,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const abrirSeguro = (apoliceId, opcoes = {}) =>
  abrirPeca(GavetaDoSeguro, { apoliceId, fonte: fonteDaDemo(opcoes) });
const abrirRenovacao = (seguroId, opcoes = {}) =>
  abrirPeca(GavetaDaRenovacao, { seguroId, fonte: fonteDaDemo(opcoes) });
const clicar = async (w, nome) => {
  await w.get(daCarteira(nome)).trigger('click');
  await assentar();
};
const azuis = w =>
  w.findAll('button').filter(botao => botao.classes().includes(AZUL));
const acao = w => w.get(daCarteira('gaveta-acao'));
const emQuePe = w => textoDe(w, daCarteira('situacao-da-renovacao'));
// Uma frase do catálogo, como a tela a escreve.
const dizer = (chave, valores = {}, plural = undefined) =>
  mount(
    defineComponent({
      setup() {
        const { t } = useI18n();
        return () => h('p', t(chave, valores, plural));
      },
    })
  ).text();

beforeAll(async () => {
  semRolagem();
  await carregarDemonstracao();
}, 60000);
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

describe('1 e 13 · a gaveta do seguro não contradiz a renovação', () => {
  it('em renovação e nada cotado: "A renovação começou. Falta cotar.", e "Cotar agora" continua', async () => {
    const w = await abrirSeguro(SEM_COTACAO);

    expect(textoDe(w, daCarteira('selo'))).toBe('Em renovação');
    expect(emQuePe(w)).toBe('A renovação começou. Falta cotar.');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toBe(
      'Vence em 5 dias. A renovação começou. Falta cotar.'
    );
    expect(w.get(daCarteira('cotar-agora')).text()).toBe('Cotar agora');
    expect(w.text()).not.toContain(AINDA_NAO_COMECOU);
  });

  it.each([
    [{}],
    [{ caso: 'cotacao_parcial' }],
    [{ caso: 'cotacao_agger_fora' }],
    [{ caso: 'cotacao_faltam_dados' }],
    [{ caso: 'cotacao_sem_pdf' }],
    [{ cotacaoDesligada: true }],
  ])(
    'com %j, a gaveta do seguro e a da renovação dizem a mesma frase',
    async opcoes => {
      const naRenovacao = emQuePe(await abrirRenovacao(SEM_COTACAO, opcoes));
      const noSeguro = await abrirSeguro(SEM_COTACAO, opcoes);

      expect(emQuePe(noSeguro)).toBe(naRenovacao);
      expect(textoDe(noSeguro, daCarteira('frase-do-seguro'))).toContain(
        naRenovacao
      );
    }
  );

  it('"Cotar agora" só aparece quando cotar é o passo da vez', async () => {
    const faltamDados = await abrirSeguro(SEM_COTACAO, {
      caso: 'cotacao_faltam_dados',
    });
    expect(emQuePe(faltamDados)).toBe('Faltam dados para cotar.');
    expect(faltamDados.find(daCarteira('cotar-agora')).exists()).toBe(false);
  });

  it('em nenhum caso da demo o selo "Em renovação" aparece com "ainda não começou"', async () => {
    const opcoesDaDemo = [
      {},
      { cotacaoDesligada: true },
      ...CASOS_DA_DEMO.map(caso => ({ caso })),
    ];
    const comOSelo = [];
    await opcoesDaDemo.reduce(async (antes, opcoes) => {
      await antes;
      const w = await abrirSeguro(SEM_COTACAO, opcoes);
      if (textoDe(w, daCarteira('selo')) !== 'Em renovação') return;
      comOSelo.push(opcoes);
      expect(w.text(), JSON.stringify(opcoes)).not.toContain(AINDA_NAO_COMECOU);
    }, Promise.resolve());
    expect(comOSelo).toHaveLength(opcoesDaDemo.length);
  });

  it('em nenhum seguro em renovação da carteira, com nenhum caso, a frase da renovação diz "não começou"', () => {
    const agora = Date.now();
    const frases = ptBR.RELACIONAMENTOS_CARTEIRA.RENOVACAO.SITUACAO;
    const emRenovacao = segurosDaCarteira(agora).filter(
      seguro => seloDoSeguro(seguro, agora) === SELOS.EM_RENOVACAO
    );
    const contas = [
      { cotaSozinha: true, tiposQueCota: ['auto', 'residencial'] },
      { cotaSozinha: false },
    ];

    expect(emRenovacao.length).toBeGreaterThan(10);
    emRenovacao.forEach(seguro =>
      [null, ...CASOS_DA_DEMO].forEach(caso =>
        contas.forEach(daConta => {
          const visto = comOCaso(seguro, caso, agora);
          const { id } = tituloDaRenovacao(
            visto.renovacao,
            cotacaoDoCard(visto, daConta)
          );
          expect(frases[id], `${seguro.id} ${caso} ${id}`).toBeTruthy();
          expect(frases[id]).not.toContain('não começou');
        })
      )
    );
  });

  it('na gaveta da renovação, a cotação vazia tem uma frase de estado e o próximo passo, sem repetir', async () => {
    const w = await abrirRenovacao(SEM_COTACAO);

    expect(emQuePe(w)).toBe('A renovação começou. Falta cotar.');
    expect(
      w.findAll(`${daCarteira('cotacao')} p`).map(frase => frase.text())
    ).toEqual(['Aperte “Cotar agora” para pedir os preços às seguradoras.']);
    expect(w.text()).not.toContain(AINDA_NAO_COMECOU);
    expect(w.get(daCarteira('cotar-agora')).classes()).toContain(AZUL);
  });
});

describe('2 · o que não saiu aparece no topo da gaveta do seguro', () => {
  const HA_UM_DIA = Math.floor((Date.now() - DIA_EM_MS) / 1000);

  it('sem nada pendente, não há o que dizer', () => {
    expect(oQueNaoSaiu({ naoSaiu: [] })).toBeNull();
    expect(oQueNaoSaiu({})).toBeNull();
    expect(oQueNaoSaiu(null)).toBeNull();
  });

  it('diz o que não saiu e se o bloco "Renovação" também fala disso', () => {
    const um = tipo => oQueNaoSaiu({ naoSaiu: [{ tipo, em: HA_UM_DIA }] });

    expect(
      oQueNaoSaiu({
        naoSaiu: [{ tipo: 'aviso_nao_saiu', em: HA_UM_DIA, dias: 7 }],
      })
    ).toEqual({ id: 'AVISO', dias: 7, naRenovacao: true });
    expect(um('algo_mudou_nao_saiu')).toMatchObject({
      id: 'ALGO_MUDOU',
      naRenovacao: true,
    });
    // A situação da renovação já diz "A proposta está pronta. Não saiu sozinha."
    expect(um('proposta_nao_saiu')).toMatchObject({
      id: 'PROPOSTA',
      naRenovacao: false,
    });
    expect(um('palavras_nao_saiu')).toMatchObject({
      id: 'PALAVRAS',
      naRenovacao: false,
    });
  });

  it('com mais de uma coisa, vale a mais recente', () => {
    expect(
      oQueNaoSaiu({
        naoSaiu: [
          { tipo: 'aviso_nao_saiu', em: HA_UM_DIA - 60, dias: 15 },
          { tipo: 'palavras_nao_saiu', em: HA_UM_DIA },
          { tipo: 'algo_mudou_nao_saiu', em: HA_UM_DIA - 30 },
        ],
      })
    ).toMatchObject({ id: 'PALAVRAS' });
  });

  it.each([
    [
      'aviso_nao_saiu',
      SEM_COTACAO,
      'O aviso de 7 dias não saiu.',
      'Converse com Inês.',
      true,
    ],
    [
      'algo_mudou_nao_saiu',
      SEM_COTACAO,
      'A pergunta “Algo mudou?” não saiu.',
      'Converse com Inês.',
      true,
    ],
    [
      'proposta_nao_saiu',
      PROPOSTA_PRONTA,
      'A proposta não saiu.',
      'Converse com Paula.',
      false,
    ],
    [
      'palavras_nao_saiu',
      APOLICE_NOVA,
      '“Seu seguro em palavras simples” não saiu.',
      'Converse com Hugo.',
      false,
    ],
  ])(
    '%s: uma linha logo abaixo da frase do topo, com o que não saiu e o caminho',
    async (caso, id, oQue, caminho, naRenovacao) => {
      const w = await abrirSeguro(id, { caso });

      const linha = w.get(daCarteira('nao-saiu'));
      expect(linha.attributes('role')).toBe('status');
      expect(linha.text()).toBe(`${oQue} ${caminho}`);
      expect(w.findAll(daCarteira('nao-saiu'))).toHaveLength(1);
      expect(
        w.get(daCarteira('frase-do-seguro')).element.nextElementSibling
      ).toBe(linha.element);
      // As mesmas palavras da história.
      expect(textoDe(w, `[data-passo="${caso}"]`)).toContain(oQue);
      // O que é da renovação também é dito no bloco "Renovação".
      const noBloco = w.find(daCarteira('renovacao-nao-saiu'));
      expect(noBloco.exists()).toBe(naRenovacao);
      if (naRenovacao) expect(noBloco.text()).toBe(oQue);
    }
  );

  it('sem nada que não saiu, a linha não existe', async () => {
    const w = await abrirSeguro(SEM_COTACAO);

    expect(w.find(daCarteira('nao-saiu')).exists()).toBe(false);
    expect(w.find(daCarteira('renovacao-nao-saiu')).exists()).toBe(false);
  });
});

describe('3 · um azul só na gaveta do seguro', () => {
  const agora = Date.now();
  const emDias = dias => Math.floor((agora + dias * DIA_EM_MS) / 1000);
  const ativo = { termina: emDias(200), temPdf: true, renovacao: null };
  const palavras = { cobre: 'batida', texto: '', enviadoEm: null };
  const naoSaiu = [{ tipo: 'aviso_nao_saiu', em: emDias(-1), dias: 7 }];

  it.each([
    ['sem pendência', ativo, {}, 'VER_PDF', null],
    [
      'o texto em palavras simples espera o envio',
      { ...ativo, palavras },
      {},
      'ENVIAR_PALAVRAS',
      'VER_PDF',
    ],
    [
      'quem está alterando o texto ainda não envia',
      { ...ativo, palavras },
      { alterandoPalavras: true },
      'VER_PDF',
      null,
    ],
    [
      'o texto já foi enviado',
      { ...ativo, palavras: { ...palavras, enviadoEm: emDias(-1) } },
      {},
      'VER_PDF',
      null,
    ],
    [
      'a apólice ainda está sendo lida',
      { ...ativo, palavras: { ...palavras, estado: 'lendo' } },
      {},
      'VER_PDF',
      null,
    ],
    [
      'algo não saiu: conversar vem antes de tudo',
      { ...ativo, palavras, naoSaiu },
      {},
      'CONVERSAR',
      'VER_PDF',
    ],
    [
      'algo não saiu num seguro em renovação',
      {
        termina: emDias(5),
        renovacao: { etapa: 'A vencer' },
        naoSaiu,
      },
      {},
      'CONVERSAR',
      'ABRIR_RENOVACAO',
    ],
    [
      'vencido: o passo já é conversar, e não se repete',
      { termina: emDias(-12), renovacao: null, naoSaiu },
      {},
      'CONVERSAR_COM',
      null,
    ],
  ])('%s', (_nome, seguro, opcoes, azul, depois) => {
    expect(passoDoSeguro(seguro, agora, opcoes)).toEqual({ azul, depois });
    expect(Object.values(PASSOS_DO_SEGURO)).toContain(azul);
  });

  const rotulos = w =>
    w
      .findAll('button')
      .map(botao => botao.text())
      .filter(Boolean);
  const semRepetir = w =>
    expect(new Set(rotulos(w)).size).toBe(rotulos(w).length);

  it('sem pendência fica como era: "Ver PDF" em azul, sem botão secundário', async () => {
    const w = await abrirSeguro(ATIVO_COM_PDF);

    expect(azuis(w).map(botao => botao.text())).toEqual(['Ver PDF']);
    expect(w.find(daCarteira('gaveta-acao-secundaria')).exists()).toBe(false);
  });

  it('envio pendente: "Enviar a Hugo" é o azul do rodapé e "Ver PDF" vira secundário', async () => {
    const w = await abrirSeguro(APOLICE_NOVA);

    expect(azuis(w)).toHaveLength(1);
    expect(acao(w).text()).toBe('Enviar a Hugo');
    expect(acao(w).classes()).toContain(AZUL);
    expect(acao(w).element.closest('footer')).not.toBeNull();
    const secundaria = w.get(daCarteira('gaveta-acao-secundaria'));
    expect(secundaria.text()).toBe('Ver PDF');
    expect(secundaria.classes()).not.toContain(AZUL);
    // O botão não se repete dentro do bloco do texto.
    expect(
      w
        .get(daCarteira('palavras-simples'))
        .find(daCarteira('enviar-palavras'))
        .exists()
    ).toBe(false);
    expect(w.get(daCarteira('alterar-palavras')).text()).toBe(
      'Alterar o texto'
    );
    semRepetir(w);

    await acao(w).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Texto enviado a ');
    expect(textoDe(w, daCarteira('palavras-enviado'))).toContain('Enviado em ');
    expect(azuis(w).map(botao => botao.text())).toEqual(['Ver PDF']);
    expect(w.find(daCarteira('gaveta-acao-secundaria')).exists()).toBe(false);
  });

  it('enquanto altera o texto, o rodapé não oferece enviar', async () => {
    const w = await abrirSeguro(APOLICE_NOVA);

    await clicar(w, 'alterar-palavras');
    expect(acao(w).text()).toBe('Ver PDF');
    expect(azuis(w)).toHaveLength(1);

    await clicar(w, 'voltar-das-palavras');
    expect(acao(w).text()).toBe('Enviar a Hugo');
  });

  it('o texto que não saiu: "Conversar" é o azul do rodapé, uma vez só', async () => {
    const w = await abrirSeguro(APOLICE_NOVA, { caso: 'palavras_nao_saiu' });

    expect(azuis(w)).toHaveLength(1);
    expect(acao(w).text()).toBe('Conversar');
    expect(acao(w).classes()).toContain(AZUL);
    expect(w.get(daCarteira('gaveta-acao-secundaria')).text()).toBe('Ver PDF');
    expect(textoDe(w, daCarteira('palavras-nao-saiu'))).toBe(
      'O WhatsApp não deixou sair agora. A equipe foi avisada.'
    );
    expect(w.get(daCarteira('palavras-simples')).find('button').exists()).toBe(
      false
    );
    semRepetir(w);
  });

  it('o aviso que não saiu num seguro em renovação: "Conversar" em azul e "Abrir a renovação" ao lado', async () => {
    const w = await abrirSeguro(SEM_COTACAO, { caso: 'aviso_nao_saiu' });

    expect(azuis(w).map(botao => botao.text())).toEqual(['Conversar']);
    expect(w.get(daCarteira('gaveta-acao-secundaria')).text()).toBe(
      'Abrir a renovação'
    );
    expect(w.find(daCarteira('abrir-renovacao')).exists()).toBe(false);
    semRepetir(w);

    await clicar(w, 'gaveta-acao-secundaria');
    expect(w.emitted('abrirRenovacao')).toEqual([[SEM_COTACAO]]);
  });
});

describe('4 · quem já estava aqui, na conferência do trazer', () => {
  const frase = leitura => {
    const quem = quemJaEstava(leitura);
    return quem
      ? dizer(
          `RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.JA_ESTAVAM.${quem.chave}`,
          { count: quem.count },
          quem.count
        )
      : '';
  };
  const leitura = (pessoas, jaEstavam) => ({
    achei: { seguros: pessoas, pessoas },
    jaEstavam,
  });

  it.each([
    [leitura(120, 120), 'As 120 pessoas já estavam aqui.'],
    [leitura(120, 87), '87 dessas pessoas já estavam aqui.'],
    [leitura(120, 1), '1 dessas pessoas já estava aqui.'],
    [leitura(1, 1), 'A pessoa já estava aqui.'],
    [leitura(120, 0), ''],
  ])('%j: "%s"', (lida, esperado) => {
    expect(frase(lida)).toBe(esperado);
  });
});

describe('5 · dados de cotação com lista fechada', () => {
  it('cada dado de lista fechada tem as suas opções, em chaves curtas', () => {
    expect(opcoesDoDado('estado_civil')).toEqual([
      'solteiro',
      'casado',
      'separado',
      'divorciado',
      'viuvo',
    ]);
    expect(opcoesDoDado('quem_dirige')).toEqual([
      'a_propria_pessoa',
      'marido_ou_esposa',
      'filho_ou_filha',
      'pai_ou_mae',
      'irmao_ou_irma',
      'funcionario',
      'outra_pessoa',
    ]);
    expect(opcoesDoDado('onde_dorme')).toHaveLength(3);
    expect(opcoesDoDado('quanto_roda')).toHaveLength(4);
    expect(opcoesDoDado('tipo_do_imovel')).toHaveLength(4);
    // Os outros continuam texto.
    expect(opcoesDoDado('placa')).toBeNull();
    expect(opcoesDoDado('nascimento')).toBeNull();
    expect(opcoesDoDado('endereco')).toBeNull();
  });

  it('seguro de empresa: "A própria pessoa" não entra em quem dirige', () => {
    const daEmpresa = opcoesDoDado('quem_dirige', { deEmpresa: true });

    expect(daEmpresa).not.toContain('a_propria_pessoa');
    expect(daEmpresa).toHaveLength(6);
    expect(opcoesDoDado('estado_civil', { deEmpresa: true })).toHaveLength(5);
  });

  it('quem dirige é opcional: sem escolha, não é o que falta', () => {
    const faltou = ['placa', 'quem_dirige', 'onde_dorme'];

    expect(primeiroDadoQueFalta(faltou, { placa: 'FIC-0B10' })).toBe(
      'onde_dorme'
    );
    expect(
      primeiroDadoQueFalta(faltou, { placa: 'FIC-0B10', onde_dorme: 'x' })
    ).toBeNull();
    expect(
      dadosEscritos(faltou, { placa: ' FIC-0B10 ', onde_dorme: 'sem_garagem' })
    ).toEqual({
      placa: 'FIC-0B10',
      quem_dirige: '',
      onde_dorme: 'sem_garagem',
    });
  });

  const campo = (w, dado) =>
    w.get(`${daCarteira('escolha-que-faltou')}[data-dado="${dado}"]`);
  const opcoesDe = async (w, dado) => {
    await campo(w, dado).get('button').trigger('click');
    return campo(w, dado).findAll('[role="option"]');
  };
  const escolher = async (w, dado, rotulo) => {
    const opcao = (await opcoesDe(w, dado)).find(o => o.text() === rotulo);
    await opcao.trigger('click');
    await assentar();
  };

  it('no carro: placa e nascimento são escritos; o resto é escolha, com "Escolha" dentro e nenhum <select> nativo', async () => {
    const w = await abrirRenovacao(FALTAM_DADOS, {
      caso: 'cotacao_sem_agente',
    });

    expect(
      w
        .findAll(daCarteira('dado-que-faltou'))
        .map(c => c.attributes('data-dado'))
    ).toEqual(['placa', 'nascimento']);
    expect(
      w
        .findAll(daCarteira('escolha-que-faltou'))
        .map(c => c.attributes('data-dado'))
    ).toEqual(['estado_civil', 'quem_dirige', 'onde_dorme', 'quanto_roda']);
    expect(w.find('select').exists()).toBe(false);
    expect(campo(w, 'estado_civil').get('button').text()).toBe('Escolha');
    expect(campo(w, 'quem_dirige').get('label').text()).toBe(
      'Quem dirige o carro (opcional)'
    );

    expect((await opcoesDe(w, 'estado_civil')).map(o => o.text())).toEqual([
      'Solteiro(a)',
      'Casado(a) ou união estável',
      'Separado(a)',
      'Divorciado(a)',
      'Viúvo(a)',
    ]);
    expect((await opcoesDe(w, 'quem_dirige')).map(o => o.text())).toEqual([
      'A própria pessoa',
      'Marido ou esposa',
      'Filho ou filha',
      'Pai ou mãe',
      'Irmão ou irmã',
      'Um funcionário',
      'Outra pessoa',
    ]);
    expect((await opcoesDe(w, 'onde_dorme')).map(o => o.text())).toEqual([
      'Garagem com portão automático',
      'Garagem com portão manual',
      'Sem garagem',
    ]);
    expect((await opcoesDe(w, 'quanto_roda')).map(o => o.text())).toEqual([
      'Até 500 km',
      'Até 800 km',
      'Até 1.500 km',
      'Mais de 1.500 km',
    ]);
  });

  it('"Cotar com estes dados" sem escolha: diz o que falta, leva o foco ao campo e não reclama de quem dirige', async () => {
    const w = await abrirRenovacao(FALTAM_DADOS, {
      caso: 'cotacao_sem_agente',
    });
    const cotacao = w.get(daCarteira('cotacao'));
    const textos = w.findAll(daCarteira('dado-que-faltou'));
    await textos[0].setValue('FIC-0B10');
    await textos[1].setValue('1988-03-12');

    const botao = w.get(daCarteira('cotar-com-dado'));
    expect(botao.attributes('disabled')).toBeUndefined();
    await clicar(w, 'cotar-com-dado');

    const falta = cotacao.get('[role="alert"]');
    expect(falta.text()).toBe('Escolha o estado civil.');
    const gatilho = campo(w, 'estado_civil').get('button');
    expect(gatilho.attributes('aria-describedby')).toBe(falta.attributes('id'));
    expect(document.activeElement).toBe(gatilho.element);

    await escolher(w, 'estado_civil', 'Casado(a) ou união estável');
    expect(gatilho.text()).toBe('Casado(a) ou união estável');
    await clicar(w, 'cotar-com-dado');
    // Quem dirige ficou sem escolha e não é cobrado: o que falta é o seguinte.
    expect(cotacao.get('[role="alert"]').text()).toBe(
      'Escolha onde o carro dorme.'
    );

    await escolher(w, 'onde_dorme', 'Sem garagem');
    await clicar(w, 'cotar-com-dado');
    expect(cotacao.get('[role="alert"]').text()).toBe(
      'Escolha quanto o carro roda por mês.'
    );
    await escolher(w, 'quanto_roda', 'Até 800 km');
    await clicar(w, 'cotar-com-dado');

    expect(cotacao.attributes('data-cotacao')).toBe('COTANDO');
  });

  it('na casa: o endereço é texto e o tipo do imóvel é escolha', async () => {
    const w = await abrirRenovacao(SEM_COTACAO, {
      caso: 'cotacao_faltam_dados',
    });

    expect(w.findAll(daCarteira('dado-que-faltou'))).toHaveLength(1);
    expect((await opcoesDe(w, 'tipo_do_imovel')).map(o => o.text())).toEqual([
      'Casa',
      'Casa em condomínio',
      'Apartamento',
      'Outro',
    ]);
    await clicar(w, 'cotar-com-dado');
    expect(w.get(`${daCarteira('cotacao')} [role="alert"]`).text()).toBe(
      'Escreva o endereço do imóvel.'
    );
  });

  it('seguro de empresa: a lista de quem dirige não tem "A própria pessoa"', async () => {
    const w = await abrirPeca(DadosQueFaltam, {
      faltou: ['quem_dirige'],
      seguradoEmpresa: true,
    });

    const opcoes = (await opcoesDe(w, 'quem_dirige')).map(o => o.text());
    expect(opcoes).not.toContain('A própria pessoa');
    expect(opcoes[0]).toBe('Marido ou esposa');
    expect(opcoes).toHaveLength(6);
  });
});

describe('6 · o diálogo "Falta a senha" só explica; cotar de novo fica no card', () => {
  it('o azul do diálogo é "Entendi" e fecha; "Cotar de novo" está no card', async () => {
    const w = await abrirRenovacao(SEM_COTACAO, {
      caso: 'cotacao_parcial_prazo',
    });

    await clicar(w, 'agger-como-resolver');
    const dialogo = w.get('[data-dialogo-falso]');
    expect(dialogo.text()).toContain(
      'Entre no seu Agger, guarde a senha da Seguradora Monte Claro e volte aqui. Depois, cote de novo.'
    );
    const botoes = dialogo.findAll('button');
    expect(botoes.map(botao => botao.text())).toEqual(['Entendi']);
    expect(botoes[0].classes()).toContain(AZUL);

    await dialogo.trigger('submit');
    await assentar();
    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
    expect(w.get(daCarteira('cotacao')).attributes('data-cotacao')).toBe(
      'PARCIAL'
    );

    const cotarDeNovo = w.get(daCarteira('cotar-de-novo-com-a-senha'));
    expect(cotarDeNovo.text()).toBe('Cotar de novo');
    expect(cotarDeNovo.classes()).not.toContain(AZUL);
    expect(
      w.findAll('button').filter(botao => botao.text() === 'Cotar de novo')
    ).toHaveLength(1);
    await clicar(w, 'cotar-de-novo-com-a-senha');
    expect(w.get(daCarteira('cotacao')).attributes('data-cotacao')).toBe(
      'COTANDO'
    );
  });
});

describe('7 · o nome do arquivo na prévia diz de quem é e do quê', () => {
  it('resumo de um seguro residencial: a seguradora e o ramo', async () => {
    const w = await abrirRenovacao(SEM_COTACAO, { caso: 'cotacao_sem_pdf' });

    await clicar(w, 'enviar-ao-cliente');
    expect(w.get(daCarteira('previa-envio')).text()).toContain(
      'Resumo da cotação Seguradora Atlântica, residencial.pdf'
    );
  });

  it('resumo de um carro: a seguradora e a placa', async () => {
    const w = await abrirRenovacao(PROPOSTA_PRONTA);

    await clicar(w, 'enviar-ao-cliente');
    expect(w.get(daCarteira('previa-envio')).text()).toContain(
      'Resumo da cotação Seguradora Atlântica, placa FIC-2D12.pdf'
    );
  });

  it('a proposta segue a mesma regra', async () => {
    const w = await abrirRenovacao(SEM_COTACAO, { cotacaoDesligada: true });

    await clicar(w, 'anexar-proposta');
    await clicar(w, 'enviar-ao-cliente');
    expect(w.get(daCarteira('previa-envio')).text()).toContain(
      'Proposta Seguradora Atlântica, residencial.pdf'
    );
  });
});

describe('8 e 9 · preço sem PDF: um título só, e a frase diz que o PDF não veio desta vez', () => {
  it('o título é o mesmo da cotação com PDF; a diferença fica no bloco de baixo', async () => {
    const soOPreco = {
      etapa: 'A vencer',
      proposta: { valor: 100, semPdf: true },
    };
    expect(tituloDaRenovacao(soOPreco, COTACAO.PRECO_SEM_PDF)).toEqual({
      id: 'COTACAO_PRONTA',
    });

    const w = await abrirRenovacao(SEM_COTACAO, { caso: 'cotacao_sem_pdf' });
    expect(emQuePe(w)).toBe('A cotação está pronta. Falta enviar.');
    const cotacao = textoDe(w, daCarteira('cotacao'));
    expect(cotacao).toContain(
      'O preço chegou: Seguradora Atlântica, R$ 546,00 por ano.'
    );
    expect(cotacao).toContain(
      'A proposta em PDF desta seguradora não veio desta vez. Vai o resumo da cotação, com preço e coberturas.'
    );
    expect(w.text()).not.toContain('não tem proposta em PDF');
  });
});

describe('10 e 12 · onde ficam as renovações: "etapas", e o funil que já tenho', () => {
  const montarOnde = modelValue =>
    abrirPeca(OndeFicamAsRenovacoes, {
      modelValue: {
        onde: 'criar',
        funil: '',
        etapa: '',
        dias: 60,
        ...modelValue,
      },
      funis: FUNIS_DA_DEMO,
      rotuloId: 'titulo-de-teste',
    });

  it('criar o funil fala em etapas, a palavra do CRM', async () => {
    const w = await montarOnde({});

    expect(w.get(daCarteira('criar-funil')).text()).toContain(
      'Já vem com as etapas: A vencer, Cotando, Opções enviadas, Negociação, Renovado.'
    );
    expect(w.text()).not.toContain('passos');
  });

  it('"Usar um funil que já tenho" diz onde a renovação cai, e o campo vazio mostra "Escolha o funil"', async () => {
    const w = await montarOnde({ onde: 'usar' });

    const cartao = w.get(daCarteira('usar-funil')).text();
    expect(cartao).toContain('Usar um funil que já tenho');
    expect(cartao).toContain(
      'Você escolhe o funil e a etapa em que a renovação entra.'
    );
    expect(w.get(`${daCarteira('escolher-funil')} button`).text()).toBe(
      'Escolha o funil'
    );
  });
});

describe('11 · quem faz a cotação: a opção diz quem faz', () => {
  it('"Sozinho" virou "Automático, sem conversar com a pessoa", e a frase de baixo não repete', () => {
    const base = 'RELACIONAMENTOS_CARTEIRA.AJUSTES.QUEM_COTA';

    expect(dizer(`${base}.ROBO`)).toBe(
      'Automático, sem conversar com a pessoa'
    );
    expect(dizer(`${base}.ROBO_APOIO`)).toBe(
      'Se faltar dado, o card mostra e você preenche.'
    );
  });
});

describe('14 · depois do erro ao trazer, o botão volta a ficar livre', () => {
  it('ocupado só durante o envio; com o erro, volta a falso', async () => {
    const tela = effectScope().run(() =>
      useTrazerSeguros({
        fonte: { trazer: () => Promise.reject(new Error('fora do ar')) },
        como: ref('planilha'),
        mudarComo: () => {},
      })
    );
    tela.leitura.value = { id: 7 };

    const pedido = tela.trazer();
    expect(tela.ocupado.value).toBe(true);
    await pedido;

    expect(tela.erro.value).toBe(ERROS.TRAZER);
    expect(tela.ocupado.value).toBe(false);
  });
});

// ---- Depois dos prints da onda 6 ---------------------------------------------

describe('prints · o rodapé das gavetas não deixa botão sozinho numa linha', () => {
  const { CORRIGIR, ANEXAR_OUTRO_PDF, MARCAR_CANCELADO, VOLTAR_A_ATIVO } =
    DO_RODAPE;
  const { VER_PDF, ABRIR_RENOVACAO, CONVERSAR, ENVIAR_PALAVRAS, AVISAR } =
    PASSOS_DO_SEGURO;

  it('sem botão secundário do passo, "Corrigir" fica no rodapé, ao lado do "⋯"', () => {
    expect(rodapeDoSeguro({ azul: VER_PDF, depois: null })).toEqual({
      azul: VER_PDF,
      secundario: CORRIGIR,
      menu: [ANEXAR_OUTRO_PDF, MARCAR_CANCELADO],
    });
    expect(rodapeDoSeguro({ azul: AVISAR, depois: null })).toEqual({
      azul: AVISAR,
      secundario: CORRIGIR,
      menu: [ANEXAR_OUTRO_PDF, MARCAR_CANCELADO],
    });
  });

  it('seguro cancelado: o "⋯" oferece voltar a ativo no lugar de cancelar', () => {
    expect(
      rodapeDoSeguro({ azul: VER_PDF, depois: null }, { cancelado: true }).menu
    ).toEqual([ANEXAR_OUTRO_PDF, VOLTAR_A_ATIVO]);
  });

  it.each([
    [{ azul: CONVERSAR, depois: ABRIR_RENOVACAO }],
    [{ azul: CONVERSAR, depois: VER_PDF }],
    [{ azul: ENVIAR_PALAVRAS, depois: VER_PDF }],
  ])('com dois botões do passo (%o), "Corrigir" vai para o "⋯"', passo => {
    expect(rodapeDoSeguro(passo)).toEqual({
      azul: passo.azul,
      secundario: passo.depois,
      menu: [CORRIGIR, ANEXAR_OUTRO_PDF, MARCAR_CANCELADO],
    });
  });

  const marcasDe = raiz =>
    raiz
      .findAll('[data-carteira]')
      .map(peca => peca.attributes('data-carteira'));

  it('na gaveta do seguro com algo que não saiu: azul, um secundário e o "⋯" juntos; "Corrigir" abre pelo "⋯"', async () => {
    const w = await abrirSeguro(SEM_COTACAO, { caso: 'aviso_nao_saiu' });

    expect(acao(w).text()).toBe('Conversar');
    // O secundário e o "⋯" andam juntos: quebram de linha juntos, ou não quebram.
    const juntos = w.get(daCarteira('rodape-secundarios'));
    expect(marcasDe(juntos).slice(0, 2)).toEqual([
      'gaveta-acao-secundaria',
      'mais-do-seguro',
    ]);
    expect(juntos.get(daCarteira('gaveta-acao-secundaria')).text()).toBe(
      'Abrir a renovação'
    );
    expect(w.find(daCarteira('corrigir')).exists()).toBe(false);

    const noMenu = w.get(daCarteira('corrigir-no-menu'));
    expect(noMenu.text()).toBe('Corrigir');
    expect(noMenu.attributes('role')).toBe('menuitem');
    await noMenu.trigger('click');
    await assentar();
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
  });

  it('na gaveta do seguro sem pendência: "Corrigir" continua no rodapé e não se repete no "⋯"', async () => {
    const w = await abrirSeguro(ATIVO_COM_PDF);

    const juntos = w.get(daCarteira('rodape-secundarios'));
    expect(marcasDe(juntos).slice(0, 2)).toEqual([
      'corrigir',
      'mais-do-seguro',
    ]);
    expect(w.find(daCarteira('gaveta-acao-secundaria')).exists()).toBe(false);
    expect(w.find(daCarteira('corrigir-no-menu')).exists()).toBe(false);
  });

  it('na gaveta da renovação com o botão do passo: o azul ocupa a linha de cima e "Renovou" e "Não renovou" dividem a de baixo', async () => {
    const w = await abrirRenovacao(FALTAM_DADOS, {
      caso: 'cotacao_sem_agente',
    });

    const azul = w.get(daCarteira('cotar-com-dado'));
    expect(azul.classes()).toContain('basis-full');
    expect(azul.classes()).not.toContain('sm:basis-auto');
    const juntos = w.get(daCarteira('desfechos'));
    expect(juntos.classes()).toContain('basis-full');
    const botoes = juntos.findAll('button');
    expect(botoes.map(b => b.attributes('data-carteira'))).toEqual([
      'renovou',
      'nao-renovou',
    ]);
    botoes.forEach(botao => {
      expect(botao.classes()).toContain('flex-1');
      expect(botao.classes()).not.toContain('sm:flex-none');
    });
  });
});

describe('prints · data de nascimento é campo de data', () => {
  it('só o nascimento é data; os outros dados escritos são texto', () => {
    expect(tipoDoCampo('nascimento')).toBe('date');
    expect(tipoDoCampo('placa')).toBe('text');
  });

  it('na gaveta: o campo é de data (como os outros campos de data do seguro) e a data escolhida vai na cotação', async () => {
    const w = await abrirRenovacao(FALTAM_DADOS, {
      caso: 'cotacao_sem_agente',
    });
    const dado = nome =>
      w.get(`${daCarteira('dado-que-faltou')}[data-dado="${nome}"]`);

    expect(dado('placa').attributes('type')).toBe('text');
    expect(dado('nascimento').attributes('type')).toBe('date');

    await dado('nascimento').setValue('1988-03-12');
    expect(dado('nascimento').element.value).toBe('1988-03-12');
  });
});

// A lista de escolha fechava sozinha nos prints. O que estes testes guardam: a
// gaveta não relê a renovação por conta própria, não remonta o formulário e
// não tira o foco de quem está escolhendo.
describe('prints · a lista aberta e o que foi escrito ficam como estão', () => {
  const UM_MINUTO_MS = 60000;

  it('com a lista aberta e o tempo passando, a lista continua aberta e a placa escrita continua lá, no mesmo campo', async () => {
    const w = await abrirRenovacao(FALTAM_DADOS, {
      caso: 'cotacao_sem_agente',
    });
    const placa = w.get(`${daCarteira('dado-que-faltou')}[data-dado="placa"]`);
    await placa.setValue('FIC-0B10');
    // O aviso do que falta aparece e some sem mexer no que já foi escrito.
    await clicar(w, 'cotar-com-dado');
    const gatilho = w.get(
      `${daCarteira('escolha-que-faltou')}[data-dado="quem_dirige"] button`
    );
    await gatilho.trigger('click');
    expect(gatilho.attributes('aria-expanded')).toBe('true');
    gatilho.element.focus();

    await vi.advanceTimersByTimeAsync(UM_MINUTO_MS);
    await assentar();

    const depois = w.get(
      `${daCarteira('escolha-que-faltou')}[data-dado="quem_dirige"] button`
    );
    expect(depois.element).toBe(gatilho.element);
    expect(depois.attributes('aria-expanded')).toBe('true');
    expect(document.activeElement).toBe(gatilho.element);
    const placaDepois = w.get(
      `${daCarteira('dado-que-faltou')}[data-dado="placa"]`
    );
    expect(placaDepois.element).toBe(placa.element);
    expect(placaDepois.element.value).toBe('FIC-0B10');
  });
});

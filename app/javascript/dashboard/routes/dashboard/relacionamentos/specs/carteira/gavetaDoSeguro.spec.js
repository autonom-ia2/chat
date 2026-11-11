import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import { baixarArquivo } from '../../carteira/exportarHistoria';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  textoDe,
} from './apoio';

// A gaveta do seguro (#2897, telas 4 e 15) com a carteira fictícia e o texto de
// verdade em pt_BR: a frase e o próximo passo de cada situação, marcar como
// cancelado com desfazer, a história, e carregando, erro e "não está mais aqui".
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('../../carteira/exportarHistoria', async importOriginal => ({
  ...(await importOriginal()),
  baixarArquivo: vi.fn(),
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const EM_RENOVACAO = 1;
const ATIVO_COM_ENDOSSO = 2;
const RENOVADO = 102;
const VENCIDO = 103;
const CANCELADO = 101;
const PARCELA_ATRASADA = 108;
const NAO_EXISTE = 9999;

const fonteDaDemo = (opcoes = {}) =>
  carteiraFonte({ demo: 'cheio', atraso: 0, ...opcoes });

let aberta;
const abrir = async (apoliceId, fonte = fonteDaDemo()) => {
  aberta = mount(GavetaDoSeguro, {
    attachTo: document.body,
    props: { apoliceId, fonte },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const acao = w => w.get(daCarteira('gaveta-acao'));
const abrirMenu = async w => {
  await w.get(`${daCarteira('mais-do-seguro')} button`).trigger('click');
};

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

describe('gaveta do seguro: uma frase e um próximo passo por situação', () => {
  it('em renovação: diz quando vence e onde a renovação está, e abre a renovação', async () => {
    const w = await abrir(EM_RENOVACAO);

    expect(textoDe(w, '[data-view-title]')).toBe('Auto · Seguradora Atlântica');
    const frase = textoDe(w, daCarteira('frase-do-seguro'));
    expect(frase).toContain('Vence em 18 dias.');
    expect(frase).toContain('A renovação está em “Opções enviadas”.');
    expect(acao(w).text()).toBe('Abrir a renovação');
    expect(w.findAll(daCarteira('gaveta-acao'))).toHaveLength(1);

    await acao(w).trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Abrindo a renovação do seguro Auto');
  });

  it('o foco vai ao título da gaveta que já nasce aberta', async () => {
    const w = await abrir(EM_RENOVACAO);
    expect(document.activeElement).toBe(w.get('[data-view-title]').element);
  });

  it('ativo com PDF: o passo é ver o PDF, e o endosso aparece na história', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);

    expect(acao(w).text()).toBe('Ver PDF');
    expect(w.find(daCarteira('renovacao')).exists()).toBe(false);
    expect(textoDe(w, '[data-passo="endosso"]')).toContain(
      'Endosso · Valor do seguro: R$ 610,00 → R$ 640,00'
    );
  });

  it('renovado: falta a apólice nova, e o dado em dúvida pede conferência', async () => {
    const w = await abrir(RENOVADO);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain(
      'Falta a apólice nova.'
    );
    expect(acao(w).text()).toBe('Anexar a apólice nova');
    expect(
      w.get('[data-dado="valor"]').find(daCarteira('confira')).exists()
    ).toBe(true);
  });

  it('vencido: diz há quanto tempo e o motivo, e chama para conversar', async () => {
    const w = await abrir(VENCIDO);

    const frase = textoDe(w, daCarteira('frase-do-seguro'));
    expect(frase).toContain('Venceu há 12 dias e não foi renovado.');
    expect(frase).toContain('Motivo: achou caro.');
    expect(acao(w).text()).toMatch('Conversar com ');
  });

  it('parcela atrasada: o passo é avisar a pessoa', async () => {
    const w = await abrir(PARCELA_ATRASADA);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain(
      'está em aberto. Avise antes de o seguro cair.'
    );
    expect(acao(w).text()).toMatch('Avisar ');
    await acao(w).trigger('click');
    expect(useAlert.mock.calls[0][0]).toMatch('Abrindo a conversa com ');
  });

  it('cancelado: o menu oferece voltar a ativo, não cancelar de novo', async () => {
    const w = await abrir(CANCELADO);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Cancelado em');
    await abrirMenu(w);
    expect(w.find(daCarteira('voltar-a-ativo')).exists()).toBe(true);
    expect(w.find(daCarteira('marcar-cancelado')).exists()).toBe(false);
  });
});

describe('gaveta do seguro: marcar como cancelado', () => {
  it('cancela sem perguntar de novo, avisa e deixa desfazer', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);

    await abrirMenu(w);
    await w.get(daCarteira('marcar-cancelado')).trigger('click');
    await assentar();

    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain(
      'Seguro marcado como cancelado.'
    );
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Cancelado em');
    expect(w.emitted('mudou')).toHaveLength(1);

    await w.get(daCarteira('desfazer')).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Desfeito.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Vale até');
    expect(w.emitted('mudou')).toHaveLength(2);
  });

  it('a região do aviso já está na gaveta antes de haver aviso', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);
    const aviso = w.get(daCarteira('aviso-vivo'));
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('');
  });

  it('quando a fonte falha, diz que não conseguiu e não oferece desfazer', async () => {
    const fonte = fonteDaDemo();
    const w = await abrir(ATIVO_COM_ENDOSSO, {
      ...fonte,
      cancelar: () => Promise.reject(new Error('fora do ar')),
    });

    await abrirMenu(w);
    await w.get(daCarteira('marcar-cancelado')).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain(
      'Não consegui fazer isso. Tente de novo.'
    );
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(w.emitted('mudou')).toBeUndefined();
  });
});

describe('gaveta do seguro: a história', () => {
  it('conta a renovação inteira, do mais novo ao mais antigo', async () => {
    const w = await abrir(EM_RENOVACAO);

    const passos = w
      .findAll(daCarteira('item-da-historia'))
      .map(item => item.attributes('data-passo'));
    expect(passos).toEqual([
      'cliente_respondeu',
      'proposta_enviada',
      'proposta_pronta',
      'respondeu_algo_mudou',
      'card_nasceu',
      'chegou_agger',
    ]);
    expect(textoDe(w, '[data-passo="proposta_pronta"]')).toContain(
      'Proposta pronta: Seguradora Atlântica, R$ 2.980,80. · Subiu 8%. · Robô de renovação'
    );
    expect(textoDe(w, '[data-passo="proposta_enviada"]')).toContain(
      'Proposta enviada · Bia Lunardelli'
    );
  });

  it('"Ver proposta" e "Exportar" funcionam e dizem o que fizeram', async () => {
    const w = await abrir(EM_RENOVACAO);

    await w.get(daCarteira('ver-proposta')).trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Abrindo a proposta');

    await w.get(daCarteira('exportar')).trigger('click');
    const [nome, conteudo] = baixarArquivo.mock.calls[0];
    expect(nome).toBe('historia-AT-000451.csv');
    expect(conteudo).toContain('"Data";"Hora";"O que aconteceu";"Quem fez"');
    expect(conteudo).toContain('Chegou do Agger.');
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Arquivo baixado.');
  });

  it('se só a história falhar, o resto do seguro continua na tela', async () => {
    const fonte = fonteDaDemo();
    const falhas = { vezes: 1 };
    const w = await abrir(EM_RENOVACAO, {
      ...fonte,
      historia: id => {
        if (falhas.vezes === 0) return fonte.historia(id);
        falhas.vezes -= 1;
        return Promise.reject(new Error('fora do ar'));
      },
    });

    expect(w.find(daCarteira('historia-erro')).exists()).toBe(true);
    expect(w.find(daCarteira('exportar')).exists()).toBe(false);
    expect(acao(w).text()).toBe('Abrir a renovação');

    await w.get(`${daCarteira('historia-erro')} button`).trigger('click');
    await assentar();
    expect(w.findAll(daCarteira('item-da-historia'))).toHaveLength(6);
  });
});

describe('gaveta do seguro: carregando, erro e seguro que sumiu', () => {
  it('carregando: o esqueleto, sem botão no rodapé', async () => {
    const w = await abrir(EM_RENOVACAO, fonteDaDemo({ peca: 'carregando' }));

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
  });

  it('erro: a frase e "Tentar de novo" dentro da gaveta', async () => {
    const w = await abrir(EM_RENOVACAO, fonteDaDemo({ peca: 'erro' }));

    const erro = w.get(`${daCarteira('gaveta-seguro')} ${doBlocoA('erro')}`);
    expect(erro.text()).toContain(
      'Não consegui abrir este seguro. Tente de novo.'
    );
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
  });

  it('seguro que não existe mais: diz isso e volta para a lista', async () => {
    const w = await abrir(NAO_EXISTE);

    const vazio = w.get(daCarteira('seguro-nao-esta'));
    expect(vazio.text()).toContain('Este seguro não está mais aqui.');
    await vazio.get('button').trigger('click');
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('Esc fecha a gaveta', async () => {
    const w = await abrir(EM_RENOVACAO);
    await w.get('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('sem seguro pedido, a gaveta não existe', async () => {
    const w = await abrir(null);
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });
});

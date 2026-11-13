import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import { baixarArquivo } from '../../carteira/exportarHistoria';
import { DO_RODAPE } from '../../carteira/rodapeDoSeguro';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import {
  aoMeioDia,
  assentar,
  carregarDemonstracao,
  daCarteira,
  recusa,
  textoDe,
} from './apoio';

// A renovação na gaveta do seguro (#2898), com o texto de verdade em pt_BR: os
// selos Em renovação e Renovado, a parte "Renovação", "Renovou" e "Não renovou"
// (com o motivo em um toque), o desfazer, a apólice nova e o "Exportar" do
// histórico. Duas fontes: uma de mentira, com o seguro no formato do servidor,
// e a carteira fictícia (os caminhos inteiros). Todos os dados são inventados.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { maximumFileUploadSize: 40 } }),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
vi.mock('../../carteira/abrirPdf', () => ({ abrirPdf: vi.fn() }));
vi.mock('../../carteira/exportarHistoria', async importOriginal => ({
  ...(await importOriginal()),
  baixarArquivo: vi.fn(),
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

// Na carteira fictícia (demo/carteira.js): um seguro com a renovação aberta,
// um que renovou e um que não renovou (achou caro).
const ABERTA_NA_DEMO = 104;
const RENOVADO_NA_DEMO = 105;
const PERDIDO_NA_DEMO = 115;
const SEM_RENOVACAO_NA_DEMO = 1;

// 12/11/2026, às 10h de quem roda o teste.
const AGORA = new Date(2026, 10, 12, 10).getTime();
const HA_DOIS_DIAS = new Date(2026, 10, 10, 9, 30).getTime() / 1000;
const RENOVACAO = {
  cardId: 88,
  funil: 'Renovação',
  etapa: 'A vencer',
  desfecho: null,
  cuida: 'Bruna Teixeirão',
};
// Seguros como a fonte real entrega: selo e dias vêm do servidor.
const EM_RENOVACAO = {
  id: 7,
  pessoaId: 23,
  pessoa: { id: 23, name: 'Ana Albuquerino', phone_number: null },
  segurado: {
    tipo: 'pessoa',
    id: 23,
    nome: 'Ana Albuquerino',
    documento: null,
  },
  tipo: 'auto',
  ramoOriginal: 'Automóvel',
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  valor: 2760,
  bem: 'Carro hatch prata',
  comeca: aoMeioDia(2025, 11, 29),
  termina: aoMeioDia(2026, 11, 29),
  selo: 'em_renovacao',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: HA_DOIS_DIAS },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
  renovacao: RENOVACAO,
  renovadoEm: null,
  motivo: null,
  motivoEscrito: '',
  apoliceNova: false,
};
const RENOVADO = {
  ...EM_RENOVACAO,
  selo: 'renovado',
  renovacao: { ...RENOVACAO, desfecho: 'renovou' },
  renovadoEm: HA_DOIS_DIAS,
};
const PERDIDO = {
  ...EM_RENOVACAO,
  selo: 'ativo',
  renovacao: { ...RENOVACAO, desfecho: 'nao_renovou' },
  motivo: 'achou_caro',
};
const PERDIDO_SEM_MOTIVO = { ...PERDIDO, motivo: null };
const SEM_RENOVACAO = { ...EM_RENOVACAO, selo: 'ativo', renovacao: null };

const fonteDaDemo = () => carteiraFonte({ demo: 'cheio', atraso: 0 });
const fonteDeMentira = (seguro, resto = {}) => ({
  usaDemo: false,
  seguro: vi.fn().mockResolvedValue(seguro),
  historia: vi.fn().mockResolvedValue([]),
  opcoesDeFiltro: vi
    .fn()
    .mockResolvedValue({ tipos: ['auto'], seguradoras: [seguro.seguradora] }),
  ...resto,
});

let aberta;
const abrir = async (apoliceId, fonte, props = {}) => {
  aberta = mount(GavetaDoSeguro, {
    attachTo: document.body,
    props: { apoliceId, fonte, podeEditar: true, ...props },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const abrirDoServidor = (seguro, resto, props) =>
  abrir(seguro.id, fonteDeMentira(seguro, resto), { agora: AGORA, ...props });
const abrirDaDemo = id => abrir(id, fonteDaDemo());

const azul = w => w.get(daCarteira('gaveta-acao'));
const selo = w => w.get(daCarteira('selo')).attributes('data-selo-da-carteira');
const situacao = w => textoDe(w, daCarteira('situacao-da-renovacao'));
const avisoVivo = w => textoDe(w, daCarteira('aviso-vivo'));
const alerta = w => textoDe(w, daCarteira('alerta-da-gaveta'));
const historico = w =>
  w.findAll(daCarteira('item-da-historia')).map(item => item.text());
const doMenu = w =>
  w
    .findAll(`${daCarteira('mais-do-seguro')} [role="menuitem"]`)
    .map(item => item.attributes('data-acao'));
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const escolherNoMenu = async (w, nome) => {
  await w
    .get(`${daCarteira('mais-do-seguro')} [aria-haspopup="menu"]`)
    .trigger('click');
  await clicar(w, `[role="menuitem"][data-acao="${nome}"]`);
};
// Os diálogos de mentira ficam lado a lado: cada um é achado pela marca do que
// tem dentro.
const dialogoDe = (w, marca) =>
  w
    .findAll('[data-dialogo-falso]')
    .find(dialogo => dialogo.find(daCarteira(marca)).exists());
const motivoAberto = w => w.find(daCarteira('motivo')).exists();
const escrever = (w, campo, texto) =>
  w.get(`input[data-campo="${campo}"]`).setValue(texto);
const salvarFormulario = w => clicar(w, daCarteira('salvar-correcao'));

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  baixarArquivo.mockClear();
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
});

describe('o que a gaveta mostra de um seguro em renovação', () => {
  it('o selo, em que etapa do funil está e quem cuida', async () => {
    const w = await abrirDoServidor(EM_RENOVACAO);

    expect(selo(w)).toBe('em_renovacao');
    expect(textoDe(w, daCarteira('selo'))).toBe('Em renovação');
    expect(textoDe(w, `${daCarteira('renovacao')} h3`)).toBe('Renovação');
    expect(situacao(w)).toBe('Está no funil Renovação, na etapa A vencer.');
    expect(textoDe(w, daCarteira('quem-cuida'))).toBe(
      'Quem cuida: Bruna Teixeirão'
    );
  });

  it('o azul é "Renovou", "Não renovou" fica ao lado e o resto vai para o "⋯"', async () => {
    const w = await abrirDoServidor(EM_RENOVACAO);

    expect(azul(w).text()).toBe('Renovou');
    expect(azul(w).attributes('data-acao')).toBe(DO_RODAPE.RENOVOU);
    expect(w.findAll(daCarteira('gaveta-acao'))).toHaveLength(1);
    expect(textoDe(w, daCarteira('nao-renovou'))).toBe('Não renovou');
    expect(w.find(daCarteira('corrigir')).exists()).toBe(false);
    expect(doMenu(w)).toEqual([
      DO_RODAPE.VER_PDF,
      DO_RODAPE.CORRIGIR,
      DO_RODAPE.GUARDAR_OUTRO_PDF,
      DO_RODAPE.APAGAR_PDF,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });

  it('"Abrir no CRM" avisa quem abriu a gaveta, com o card', async () => {
    const w = await abrirDoServidor(EM_RENOVACAO);

    await clicar(w, daCarteira('abrir-no-crm'));

    expect(w.emitted('abrirCard')).toEqual([[88]]);
  });

  it('"Corrigir", pelo "⋯", abre o formulário de sempre', async () => {
    const w = await abrirDoServidor(EM_RENOVACAO);

    await escolherNoMenu(w, DO_RODAPE.CORRIGIR);

    expect(textoDe(w, '[data-view-title]')).toBe('Corrigir o seguro Auto');
    expect(w.get('input[data-campo="numero"]').element.value).toBe('AT-000451');
  });

  it('seguro sem renovação não mostra a parte "Renovação"', async () => {
    const w = await abrirDoServidor(SEM_RENOVACAO);

    expect(w.find(daCarteira('renovacao')).exists()).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
    expect(textoDe(w, daCarteira('corrigir'))).toBe('Corrigir');
    expect(w.find(daCarteira('nao-renovou')).exists()).toBe(false);
  });

  it('quem só pode ver lê a renovação e não tem "Renovou" nem "Não renovou"', async () => {
    const w = await abrirDoServidor(
      PERDIDO_SEM_MOTIVO,
      {},
      {
        podeEditar: false,
      }
    );

    expect(situacao(w)).toBe('Não renovou. Ninguém disse o motivo.');
    expect(w.find(daCarteira('dizer-o-motivo')).exists()).toBe(false);
    expect(w.find(daCarteira('nao-renovou')).exists()).toBe(false);
    expect(w.find(daCarteira('mais-do-seguro')).exists()).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
  });
});

describe('"Renovou"', () => {
  it('não pede confirmação: guarda, avisa com Desfazer e o próximo passo vira a apólice nova', async () => {
    const renovou = vi.fn().mockResolvedValue(RENOVADO);
    const w = await abrirDoServidor(EM_RENOVACAO, { renovou });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(renovou).toHaveBeenCalledTimes(1);
    expect(renovou.mock.calls[0][0]).toBe(7);
    expect(avisoVivo(w)).toContain('Marcado como renovado.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(true);
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(selo(w)).toBe('renovado');
    expect(textoDe(w, daCarteira('selo'))).toBe('Renovado');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toBe(
      'Renovado em 10/11/2026.'
    );
    expect(situacao(w)).toBe('Renovou. Falta guardar a apólice nova.');
    expect(azul(w).text()).toBe('Guardar a apólice nova');
    expect(textoDe(w, daCarteira('corrigir'))).toBe('Corrigir');
  });

  it('"Desfazer", no aviso, reabre a renovação', async () => {
    const renovou = vi.fn().mockResolvedValue(RENOVADO);
    const desfazerDesfecho = vi.fn().mockResolvedValue(EM_RENOVACAO);
    const w = await abrirDoServidor(EM_RENOVACAO, {
      renovou,
      desfazerDesfecho,
    });
    await clicar(w, daCarteira('gaveta-acao'));

    await clicar(w, daCarteira('desfazer'));

    expect(desfazerDesfecho).toHaveBeenCalledTimes(1);
    expect(desfazerDesfecho.mock.calls[0][0]).toBe(7);
    expect(avisoVivo(w)).toBe('Desfeito.');
    expect(azul(w).text()).toBe('Renovou');
    expect(w.emitted('mudou')).toHaveLength(2);
  });

  it('se não der certo, diz o que fazer e o seguro continua em renovação', async () => {
    const renovou = vi.fn().mockRejectedValue(new Error('Network Error'));
    const w = await abrirDoServidor(EM_RENOVACAO, { renovou });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(alerta(w)).toBe('Não consegui fazer isso. Tente de novo.');
    expect(azul(w).text()).toBe('Renovou');
    expect(w.emitted('mudou')).toBeUndefined();
  });
});

describe('"Não renovou" e o motivo em um toque', () => {
  it('pergunta o motivo, e um toque guarda', async () => {
    const naoRenovou = vi.fn().mockResolvedValue(PERDIDO);
    const w = await abrirDoServidor(EM_RENOVACAO, { naoRenovou });

    await clicar(w, daCarteira('nao-renovou'));

    expect(motivoAberto(w)).toBe(true);
    expect(naoRenovou).not.toHaveBeenCalled();

    await clicar(w, '[data-motivo="achou_caro"]');

    expect(naoRenovou).toHaveBeenCalledWith(7, { motivo: 'achou_caro' });
    expect(motivoAberto(w)).toBe(false);
    expect(avisoVivo(w)).toContain('Marcado como não renovado.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(true);
    expect(situacao(w)).toBe('Não renovou: achou caro.');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('"Outro motivo" guarda o que a pessoa escreveu', async () => {
    const naoRenovou = vi.fn().mockResolvedValue({
      ...PERDIDO,
      motivo: 'outro',
      motivoEscrito: 'Mudou de país',
    });
    const w = await abrirDoServidor(EM_RENOVACAO, { naoRenovou });
    await clicar(w, daCarteira('nao-renovou'));
    await clicar(w, daCarteira('motivo-outro'));
    await w.get(daCarteira('motivo-escrito')).setValue('Mudou de país');

    await dialogoDe(w, 'motivo').get('[data-confirmar]').trigger('click');
    await assentar();

    expect(naoRenovou).toHaveBeenCalledWith(7, {
      motivo: 'outro',
      texto: 'Mudou de país',
    });
    expect(situacao(w)).toBe('Não renovou. Motivo: Mudou de país');
  });

  it('fechar o diálogo sem escolher não guarda nada', async () => {
    const naoRenovou = vi.fn();
    const w = await abrirDoServidor(EM_RENOVACAO, { naoRenovou });
    await clicar(w, daCarteira('nao-renovou'));

    await dialogoDe(w, 'motivo').get('[data-cancelar]').trigger('click');
    await assentar();

    expect(naoRenovou).not.toHaveBeenCalled();
    expect(motivoAberto(w)).toBe(false);
    expect(azul(w).text()).toBe('Renovou');
  });

  it('quem não renovou continua com o selo do seguro e ganha o desfazer no "⋯"', async () => {
    const w = await abrirDoServidor(PERDIDO);

    expect(selo(w)).toBe('ativo');
    expect(azul(w).text()).toBe('Ver PDF');
    expect(doMenu(w)).toEqual([
      DO_RODAPE.GUARDAR_OUTRO_PDF,
      DO_RODAPE.APAGAR_PDF,
      DO_RODAPE.DESFAZER_RENOVACAO,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
    expect(textoDe(w, `[data-acao="${DO_RODAPE.DESFAZER_RENOVACAO}"]`)).toBe(
      'Desfazer o resultado da renovação'
    );
  });

  it('o desfazer do "⋯" reabre a renovação e diz o que aconteceu', async () => {
    const desfazerDesfecho = vi.fn().mockResolvedValue(EM_RENOVACAO);
    const w = await abrirDoServidor(PERDIDO, { desfazerDesfecho });

    await escolherNoMenu(w, DO_RODAPE.DESFAZER_RENOVACAO);

    expect(desfazerDesfecho).toHaveBeenCalledTimes(1);
    expect(avisoVivo(w)).toBe(
      'Resultado desfeito. O seguro voltou a estar em renovação.'
    );
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(azul(w).text()).toBe('Renovou');
  });
});

describe('renovação fechada sem motivo', () => {
  it('convida a dizer o motivo, e dizer só completa o que faltava', async () => {
    const naoRenovou = vi.fn().mockResolvedValue(PERDIDO);
    const w = await abrirDoServidor(PERDIDO_SEM_MOTIVO, { naoRenovou });

    expect(situacao(w)).toBe('Não renovou. Ninguém disse o motivo.');
    expect(textoDe(w, daCarteira('dizer-o-motivo'))).toBe(
      'Dizer por que não renovou'
    );

    await clicar(w, daCarteira('dizer-o-motivo'));
    await clicar(w, '[data-motivo="achou_caro"]');

    expect(naoRenovou).toHaveBeenCalledWith(7, { motivo: 'achou_caro' });
    expect(avisoVivo(w)).toBe('Motivo guardado.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(w.find(daCarteira('dizer-o-motivo')).exists()).toBe(false);
    expect(situacao(w)).toBe('Não renovou: achou caro.');
  });
});

describe('guardar a apólice nova', () => {
  const NOVA = { ...SEM_RENOVACAO, id: 8, numero: 'AT-000987' };
  const fonteQueGuarda = () => {
    const apoliceNova = vi.fn().mockResolvedValue(NOVA);
    const fonte = fonteDeMentira(RENOVADO, { apoliceNova });
    // Depois de guardar, o seguro anterior passa a dizer que já tem a nova.
    apoliceNova.mockImplementation(async () => {
      fonte.seguro.mockResolvedValue({ ...RENOVADO, apoliceNova: true });
      return NOVA;
    });
    return { fonte, apoliceNova };
  };
  const abrirFormulario = async fonte => {
    const w = await abrir(RENOVADO.id, fonte, { agora: AGORA });
    await clicar(w, daCarteira('gaveta-acao'));
    return w;
  };

  it('abre o formulário já com o que não muda, e com o número e o valor em branco', async () => {
    const { fonte } = fonteQueGuarda();

    const w = await abrirFormulario(fonte);

    expect(textoDe(w, '[data-view-title]')).toBe('Apólice nova do seguro Auto');
    expect(w.get('input[data-campo="numero"]').element.value).toBe('');
    expect(w.get('input[data-campo="valor"]').element.value).toBe('');
    expect(w.get('input[data-campo="comeca"]').element.value).toBe(
      '2026-11-29'
    );
    expect(w.get('input[data-campo="termina"]').element.value).toBe(
      '2027-11-29'
    );
    expect(w.get('input[data-campo="bem"]').element.value).toBe(
      'Carro hatch prata'
    );
    expect(w.text()).toContain(
      'Já veio com o que não muda de um ano para o outro.'
    );
  });

  it('sem o número, Salvar diz o que falta e não guarda', async () => {
    const { fonte, apoliceNova } = fonteQueGuarda();
    const w = await abrirFormulario(fonte);

    await salvarFormulario(w);

    expect(w.text()).toContain('Escreva o número da apólice.');
    expect(apoliceNova).not.toHaveBeenCalled();
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
  });

  it('com o número, guarda a apólice nova e volta ao seguro, que já diz que a tem', async () => {
    const { fonte, apoliceNova } = fonteQueGuarda();
    const w = await abrirFormulario(fonte);
    await escrever(w, 'numero', 'AT-000987');

    await salvarFormulario(w);

    expect(apoliceNova).toHaveBeenCalledWith(7, {
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      numero: 'AT-000987',
      comeca: aoMeioDia(2026, 11, 29),
      termina: aoMeioDia(2027, 11, 29),
      bem: 'Carro hatch prata',
    });
    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(avisoVivo(w)).toBe(
      'Apólice nova guardada. Ela já aparece na lista de seguros.'
    );
    expect(situacao(w)).toBe('Renovou. A apólice nova já está guardada.');
    expect(azul(w).text()).toBe('Ver PDF');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('apólice repetida: a frase diz o que conferir e o formulário continua aberto', async () => {
    const apoliceNova = vi.fn().mockRejectedValue(recusa('apolice_repetida'));
    const w = await abrirFormulario(fonteDeMentira(RENOVADO, { apoliceNova }));
    await escrever(w, 'numero', 'AT-000451');

    await salvarFormulario(w);

    expect(alerta(w)).toBe(
      'Já existe um seguro com essa seguradora, esse número e essa data de término. Confira o número da apólice.'
    );
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(w.get('input[data-campo="numero"]').element.value).toBe('AT-000451');
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('"Voltar" sem escrever nada sai sem perguntar', async () => {
    const { fonte, apoliceNova } = fonteQueGuarda();
    const w = await abrirFormulario(fonte);

    await clicar(w, daCarteira('voltar-da-correcao'));

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(azul(w).text()).toBe('Guardar a apólice nova');
    expect(apoliceNova).not.toHaveBeenCalled();
  });
});

describe('o histórico e o "Exportar"', () => {
  const PASSOS = [
    {
      tipo: 'nao_renovou',
      quando: HA_DOIS_DIAS,
      quem: { nome: 'Bruna Teixeirão' },
      valores: { motivo: 'achou_caro' },
      mudancas: null,
    },
    {
      tipo: 'card_nasceu',
      quando: HA_DOIS_DIAS,
      quem: null,
      valores: {},
      mudancas: null,
    },
  ];
  const comHistorico = () => ({
    historia: vi.fn().mockResolvedValue(PASSOS),
  });

  it('conta os passos da renovação', async () => {
    const w = await abrirDoServidor(PERDIDO, comHistorico());
    const [naoRenovou, comecou] = historico(w);

    expect(naoRenovou).toContain('Não renovou: achou caro.');
    expect(naoRenovou).toContain('Bruna Teixeirão');
    expect(comecou).toContain('A renovação começou.');
  });

  it('quem pode exportar baixa o histórico e lê que baixou', async () => {
    const w = await abrirDoServidor(PERDIDO, comHistorico(), {
      podeExportar: true,
    });

    await clicar(w, daCarteira('exportar-historico'));

    expect(baixarArquivo).toHaveBeenCalledTimes(1);
    const [nome, conteudo] = baixarArquivo.mock.calls[0];
    expect(nome).toBe('historico-do-seguro.csv');
    expect(conteudo).toContain('"Não renovou: achou caro."');
    expect(conteudo).not.toContain('AT-000451');
    expect(avisoVivo(w)).toBe('Histórico baixado.');
  });

  it('quem não pode exportar não vê o botão', async () => {
    const w = await abrirDoServidor(PERDIDO, comHistorico());

    expect(w.find(daCarteira('exportar-historico')).exists()).toBe(false);
  });
});

describe('na carteira fictícia, do começo ao fim', () => {
  it('"Renovou" e depois "Desfazer" voltam o seguro para em renovação', async () => {
    const w = await abrirDaDemo(ABERTA_NA_DEMO);

    expect(selo(w)).toBe('em_renovacao');
    expect(situacao(w)).toContain('Está no funil Renovação, na etapa ');

    await clicar(w, daCarteira('gaveta-acao'));

    expect(selo(w)).toBe('renovado');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Renovado em ');
    expect(historico(w)[0]).toContain('Renovou.');
    expect(azul(w).text()).toBe('Guardar a apólice nova');

    await clicar(w, daCarteira('desfazer'));

    expect(selo(w)).toBe('em_renovacao');
    expect(azul(w).text()).toBe('Renovou');
    expect(historico(w).join(' ')).not.toContain('Renovou.');
  });

  it('"Não renovou" com o motivo aparece na situação e no histórico', async () => {
    const w = await abrirDaDemo(ABERTA_NA_DEMO);

    await clicar(w, daCarteira('nao-renovou'));
    await clicar(w, '[data-motivo="vendeu_o_bem"]');

    expect(situacao(w)).toBe('Não renovou: vendeu o bem.');
    expect(historico(w)[0]).toContain('Não renovou: vendeu o bem.');
    expect(doMenu(w)).toContain(DO_RODAPE.DESFAZER_RENOVACAO);
  });

  it('o seguro que renovou guarda a apólice nova e passa a dizer que já a tem', async () => {
    const fonte = fonteDaDemo();
    const w = await abrir(RENOVADO_NA_DEMO, fonte);

    expect(situacao(w)).toBe('Renovou. Falta guardar a apólice nova.');

    await clicar(w, daCarteira('gaveta-acao'));
    await escrever(w, 'numero', 'NOVA-000105');
    await salvarFormulario(w);

    expect(situacao(w)).toBe('Renovou. A apólice nova já está guardada.');
    expect(azul(w).attributes('data-acao')).not.toBe(
      DO_RODAPE.GUARDAR_APOLICE_NOVA
    );
    // A fonte da demonstração responde depois de um instante do relógio falso.
    const pedido = fonte.listar({ busca: 'NOVA-000105' });
    await assentar();
    const { itens } = await pedido;
    expect(itens).toHaveLength(1);
    expect(itens[0].renovacao).toBeNull();
  });

  it('o que não renovou diz o motivo e conta a história inteira', async () => {
    const w = await abrirDaDemo(PERDIDO_NA_DEMO);

    expect(situacao(w)).toBe('Não renovou: achou caro.');
    expect(historico(w).join(' ')).toContain('Não renovou: achou caro.');
    expect(historico(w).join(' ')).toContain('A renovação começou.');
  });

  it('seguro sem renovação continua como sempre', async () => {
    const w = await abrirDaDemo(SEM_RENOVACAO_NA_DEMO);

    expect(w.find(daCarteira('renovacao')).exists()).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
    expect(textoDe(w, daCarteira('corrigir'))).toBe('Corrigir');
  });
});

import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import { abrirPdf } from '../../carteira/abrirPdf';
import { DO_RODAPE } from '../../carteira/rodapeDoSeguro';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { NAO_ACHEI, SEM_ACESSO } from '../../ficha/falhas';
import {
  aoMeioDia,
  assentar,
  carregarDemonstracao,
  daCarteira,
  recusa,
  textoDe,
} from './apoio';

// A gaveta do seguro (#2897) com o texto de verdade em pt_BR. Duas fontes: a
// carteira fictícia (os caminhos inteiros: cancelar e desfazer, corrigir, o
// PDF) e uma fonte de mentira com o seguro no formato do servidor (selo e dias
// prontos, recusas com código).

// O limite de anexo da instalação, em MB: a gaveta confere o PDF antes de
// enviar (carteira/useLimiteDoPdf.js).
const { LIMITE_EM_MB } = vi.hoisted(() => ({ LIMITE_EM_MB: 40 }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { maximumFileUploadSize: LIMITE_EM_MB } }),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
vi.mock('../../carteira/abrirPdf', () => ({ abrirPdf: vi.fn() }));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

// Na carteira fictícia (demo/carteira.js).
const COM_PDF = 1;
const SEM_PDF = 2;
const SEM_COMECO_NEM_VALOR = 3;
const VENCIDO_SEM_PDF = 116;
const CANCELADO = 117;
const NAO_EXISTE = 999999;
const BYTES_POR_MB = 1024 * 1024;
const PDF_GRANDE_DEMAIS =
  'Este PDF é grande demais para guardar aqui. Peça à seguradora o PDF da apólice, não a cópia escaneada, e guarde esse.';

// 12/11/2026, às 10h de quem roda o teste.
const AGORA = new Date(2026, 10, 12, 10).getTime();
const CHEGOU_EM = new Date(2026, 9, 23, 9).getTime() / 1000;
// Um seguro como a fonte real entrega: selo e dias vêm do servidor.
const DO_SERVIDOR = {
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
  selo: 'ativo',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: CHEGOU_EM },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
};
// Outro seguro da mesma conta, para a gaveta trocar de um para o outro.
const OUTRO_DO_SERVIDOR = {
  ...DO_SERVIDOR,
  id: 8,
  tipo: 'residencial',
  seguradora: 'Horizonte Seguros',
  numero: 'HZ-002318',
};
const CANCELADO_NO_SERVIDOR = {
  ...DO_SERVIDOR,
  selo: 'cancelado',
  canceladoEm: 1,
};

const fonteDaDemo = (opcoes = {}) =>
  carteiraFonte({ demo: 'cheio', atraso: 0, ...opcoes });
const fonteDeMentira = (seguro = DO_SERVIDOR, resto = {}) => ({
  usaDemo: false,
  seguro: vi.fn().mockResolvedValue(seguro),
  historia: vi.fn().mockResolvedValue([]),
  opcoesDeFiltro: vi
    .fn()
    .mockResolvedValue({ tipos: ['auto'], seguradoras: [seguro.seguradora] }),
  ...resto,
});

let aberta;
const abrir = async (apoliceId, fonte = fonteDaDemo(), props = {}) => {
  aberta = mount(GavetaDoSeguro, {
    attachTo: document.body,
    props: { apoliceId, fonte, podeEditar: true, ...props },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const abrirDoServidor = (seguro, resto, props) =>
  abrir(seguro?.id ?? DO_SERVIDOR.id, fonteDeMentira(seguro, resto), {
    agora: AGORA,
    ...props,
  });

const azul = w => w.get(daCarteira('gaveta-acao'));
const semEspacoDuro = texto => texto.replaceAll(' ', ' ');
const dado = (w, chave) => semEspacoDuro(textoDe(w, `[data-dado="${chave}"]`));
const selo = w => w.get(daCarteira('selo')).attributes('data-selo-da-carteira');
const avisoVivo = w => textoDe(w, daCarteira('aviso-vivo'));
const alerta = w => textoDe(w, daCarteira('alerta-da-gaveta'));
const temAlerta = w => w.find(daCarteira('alerta-da-gaveta')).exists();
const historico = w =>
  w.findAll(daCarteira('mudanca-da-historia')).map(item => item.text());
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
const estaAberto = (w, marca) => w.find(daCarteira(marca)).exists();
const responderNo = async (w, marca, botao) => {
  await dialogoDe(w, marca).get(botao).trigger('click');
  await assentar();
};
const confirmarNo = (w, marca) => responderNo(w, marca, '[data-confirmar]');
const voltarNo = (w, marca) => responderNo(w, marca, '[data-cancelar]');
const abrirCorrecao = w => clicar(w, daCarteira('corrigir'));
const salvar = w => clicar(w, daCarteira('salvar-correcao'));
const escrever = (w, campo, texto) =>
  w.get(`input[data-campo="${campo}"]`).setValue(texto);
const escolherArquivo = async (w, arquivo) => {
  const seletor = w.get('input[type="file"]');
  Object.defineProperty(seletor.element, 'files', {
    value: [arquivo],
    configurable: true,
  });
  await seletor.trigger('change');
  await assentar();
};
const umPdf = () =>
  new File(['%PDF-1.4'], 'contrato-da-ana.pdf', { type: 'application/pdf' });
// Um PDF que passa do limite da instalação (só o tamanho declarado é grande).
const umPdfGrande = () =>
  Object.defineProperty(umPdf(), 'size', {
    value: (LIMITE_EM_MB + 1) * BYTES_POR_MB,
  });
// Uma resposta da fonte que só chega quando o teste manda.
const respostaNaMao = () => {
  const naMao = {};
  naMao.promessa = new Promise((resolver, recusar) => {
    naMao.resolver = resolver;
    naMao.recusar = recusar;
  });
  return naMao;
};
// Uma fonte de mentira que conhece dois seguros, cada um pelo seu id.
const fonteDeDois = resto =>
  fonteDeMentira(DO_SERVIDOR, {
    seguro: vi.fn(async id =>
      id === OUTRO_DO_SERVIDOR.id ? OUTRO_DO_SERVIDOR : DO_SERVIDOR
    ),
    ...resto,
  });
const trocarDeSeguro = async (w, apoliceId) => {
  await w.setProps({ apoliceId });
  await assentar();
};
// Os três jeitos de fechar a gaveta sem passar pelo rodapé.
const JEITOS_DE_FECHAR = {
  'o X': w => w.get('[role="dialog"] header button').trigger('click'),
  'o Esc': w => w.get('[role="dialog"]').trigger('keydown', { key: 'Escape' }),
  'o clique fora': w =>
    w.get('div.fixed.inset-0[aria-hidden="true"]').trigger('click'),
};

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  // "Ver PDF" pede o link e, no teste, não abre aba nenhuma.
  abrirPdf.mockImplementation(async pedirLink => {
    try {
      await pedirLink();
      return null;
    } catch (falha) {
      return falha;
    }
  });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
});

describe('o que a gaveta mostra', () => {
  it('fechada, não desenha nada', async () => {
    const w = await abrir(null);

    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });

  it('o título diz o tipo e a seguradora, e recebe o foco', async () => {
    const w = await abrir(COM_PDF);
    const titulo = w.get('[data-view-title]');

    expect(titulo.text()).toBe('Auto · Seguradora Atlântica');
    expect(document.activeElement).toBe(titulo.element);
  });

  it('ativo com PDF: uma frase com os dias e a data, e o azul é "Ver PDF"', async () => {
    const w = await abrirDoServidor();

    expect(selo(w)).toBe('ativo');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toBe(
      'Vence em 17 dias, em 29/11/2026.'
    );
    expect(azul(w).text()).toBe('Ver PDF');
    expect(w.findAll(daCarteira('gaveta-acao'))).toHaveLength(1);
    expect(textoDe(w, daCarteira('corrigir'))).toBe('Corrigir');
    expect(doMenu(w)).toEqual([
      DO_RODAPE.GUARDAR_OUTRO_PDF,
      DO_RODAPE.APAGAR_PDF,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
  });

  it('no "⋯", o que não tem volta fácil vem em vermelho', async () => {
    const w = await abrirDoServidor();
    const item = nome => w.get(`[role="menuitem"][data-acao="${nome}"]`);

    expect(item(DO_RODAPE.APAGAR_PDF).text()).toBe('Apagar o PDF');
    expect(item(DO_RODAPE.APAGAR_PDF).classes()).toContain('text-n-ruby-11');
    expect(item(DO_RODAPE.MARCAR_CANCELADO).classes()).toContain(
      'text-n-ruby-11'
    );
    expect(item(DO_RODAPE.GUARDAR_OUTRO_PDF).classes()).not.toContain(
      'text-n-ruby-11'
    );
  });

  it('o selo e os dias são os do servidor, não os do relógio', async () => {
    const w = await abrirDoServidor({
      ...DO_SERVIDOR,
      selo: 'vencido',
      dias: -3,
    });

    expect(selo(w)).toBe('vencido');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toBe('Venceu há 3 dias.');
  });

  it('ativo sem PDF: a frase avisa e o azul é "Guardar o PDF"', async () => {
    const w = await abrir(SEM_PDF);

    const frase = textoDe(w, daCarteira('frase-do-seguro'));
    expect(frase).toContain('Vale até ');
    expect(frase).toContain('Ainda não tem o PDF guardado.');
    expect(azul(w).text()).toBe('Guardar o PDF');
    expect(doMenu(w)).toEqual([DO_RODAPE.MARCAR_CANCELADO]);
  });

  it('vencido sem PDF: sem botão azul, e guardar o PDF vai para o "⋯"', async () => {
    const w = await abrir(VENCIDO_SEM_PDF);

    expect(selo(w)).toBe('vencido');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toBe('Venceu há 4 dias.');
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('corrigir'))).toBe('Corrigir');
    expect(doMenu(w)).toEqual([
      DO_RODAPE.GUARDAR_PDF,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
  });

  it('cancelado sem PDF: diz quando foi e oferece desfazer o cancelamento', async () => {
    const w = await abrir(CANCELADO);

    expect(selo(w)).toBe('cancelado');
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain(
      'Cancelado em '
    );
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
    expect(doMenu(w)).toEqual([
      DO_RODAPE.GUARDAR_PDF,
      DO_RODAPE.DESFAZER_CANCELAMENTO,
    ]);
    expect(textoDe(w, `[data-acao="${DO_RODAPE.DESFAZER_CANCELAMENTO}"]`)).toBe(
      'Desfazer o cancelamento'
    );
  });

  it('os dados: número que não quebra, valor com centavos, datas inteiras', async () => {
    const w = await abrirDoServidor();

    const numero = w.get(
      `[data-dado="numero"] ${daCarteira('numero-da-apolice')}`
    );
    expect(numero.text()).toBe('AT-000451');
    expect(numero.classes()).toContain('whitespace-nowrap');
    expect(w.find('[data-dado="numero"] [data-copiar]').exists()).toBe(true);
    expect(dado(w, 'tipo')).toContain('Auto');
    expect(dado(w, 'ramo')).toContain('Na planilha estava como');
    expect(dado(w, 'ramo')).toContain('Automóvel');
    expect(dado(w, 'seguradora')).toContain('Seguradora Atlântica');
    expect(dado(w, 'comeca')).toContain('29/11/2025');
    expect(dado(w, 'termina')).toContain('29/11/2026');
    expect(dado(w, 'valor')).toContain('Valor que o cliente paga');
    expect(dado(w, 'valor')).toContain('R$ 2.760,00');
    expect(dado(w, 'bem')).toContain('Carro hatch prata');
    expect(dado(w, 'origem')).toContain('Chegou por planilha, em 23/10');
  });

  it('o que falta diz "Não informado", e a linha do ramo some sem valor', async () => {
    const w = await abrir(SEM_COMECO_NEM_VALOR);

    expect(dado(w, 'comeca')).toContain('Não informado');
    expect(dado(w, 'valor')).toContain('Não informado');
    expect(dado(w, 'bem')).toContain('Não informado');
    expect(w.find('[data-dado="ramo"]').exists()).toBe(false);
  });

  it('a origem não mostra o nome do arquivo da planilha', async () => {
    const w = await abrir(COM_PDF);

    expect(dado(w, 'origem')).toContain('Chegou por planilha, em ');
    expect(document.body.textContent).not.toContain('Carteira 2026');
    expect(document.body.textContent).not.toContain('.xlsx');
  });

  it('seguro que não veio de planilha diz só quando chegou', async () => {
    const w = await abrirDoServidor({
      ...DO_SERVIDOR,
      origem: { tipo: 'manual', arquivo: null, em: CHEGOU_EM },
    });

    expect(dado(w, 'origem')).toContain('Chegou em 23/10');
    expect(dado(w, 'origem')).not.toContain('planilha');
  });

  it('seguro sem número não mostra o copiar', async () => {
    const w = await abrirDoServidor({ ...DO_SERVIDOR, numero: null });

    expect(dado(w, 'numero')).toContain('Não informado');
    expect(w.find('[data-dado="numero"] [data-copiar]').exists()).toBe(false);
  });

  it('o topo diz de quem é o seguro, e o nome leva à ficha', async () => {
    const w = await abrirDoServidor();
    const nome = w.get(
      `${daCarteira('de-quem')} ${daCarteira('abrir-segurado')}`
    );

    expect(textoDe(w, daCarteira('de-quem'))).toContain('Seguro de');
    expect(nome.text()).toContain('Ana Albuquerino');
    expect(nome.text()).toContain('Abrir a ficha');
    expect(nome.attributes('aria-label')).toBe('Ana Albuquerino Abrir a ficha');
    expect(w.find('[data-dado="segurado"]').exists()).toBe(false);

    await nome.trigger('click');

    expect(w.emitted('abrirSegurado')).toEqual([[DO_SERVIDOR.segurado]]);
  });

  it('seguro no nome da empresa leva à ficha da empresa', async () => {
    const segurado = {
      tipo: 'empresa',
      id: 5,
      nome: 'Padaria Aurora Fictícia',
      documento: null,
    };
    const w = await abrirDoServidor({ ...DO_SERVIDOR, segurado });

    await w.get(daCarteira('abrir-segurado')).trigger('click');

    expect(w.emitted('abrirSegurado')).toEqual([[segurado]]);
  });

  it('trocar de seguro relê tudo e sai da correção', async () => {
    const w = await abrir(COM_PDF);
    await abrirCorrecao(w);

    await w.setProps({ apoliceId: SEM_PDF });
    await assentar();

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(textoDe(w, '[data-view-title]')).toBe(
      'Residencial · Horizonte Seguros'
    );
  });
});

describe('o histórico', () => {
  it('conta o que chegou de novo pela planilha, com o que mudou', async () => {
    const w = await abrir(SEM_PDF);

    expect(textoDe(w, `${daCarteira('historia')} h3`)).toBe('Histórico');
    const passos = w
      .findAll(daCarteira('item-da-historia'))
      .map(item => item.attributes('data-passo'));
    expect(passos).toEqual(['chegou_de_novo', 'chegou_planilha']);
    expect(textoDe(w, '[data-passo="chegou_de_novo"]')).toContain(
      'Chegou de novo por planilha.'
    );
    expect(historico(w).map(semEspacoDuro)).toEqual([
      'Valor que o cliente paga: era R$ 610,00, ficou R$ 640,00',
    ]);
  });

  it('diz quem fez, e escreve data e campo vazio do jeito da tela', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      historia: vi.fn().mockResolvedValue([
        {
          tipo: 'corrigido',
          quando: CHEGOU_EM,
          quem: { id: 1, nome: 'Bia Lunardelli' },
          mudancas: [
            {
              campo: 'termina',
              antes: aoMeioDia(2026, 11, 20),
              depois: aoMeioDia(2026, 11, 29),
            },
            { campo: 'comeca', antes: null, depois: aoMeioDia(2025, 11, 29) },
            { campo: 'tipo', antes: 'outro', depois: 'auto' },
            { campo: 'bem', antes: '', depois: 'Carro hatch prata' },
          ],
        },
      ]),
    });

    const passo = textoDe(w, '[data-passo="corrigido"]');
    expect(passo).toContain('23/10');
    expect(passo).toContain('Seguro corrigido à mão.');
    expect(passo).toContain('Bia Lunardelli');
    expect(historico(w)).toEqual([
      'Termina: era 20/11/2026, ficou 29/11/2026',
      'Começa: era não informado, ficou 29/11/2025',
      'Tipo de seguro: era Outro, ficou Auto',
      'O que está segurado: era não informado, ficou Carro hatch prata',
    ]);
  });

  it('se o histórico falha, o resto do seguro continua na tela', async () => {
    const historia = vi.fn().mockRejectedValue(new Error('rede'));
    const w = await abrirDoServidor(DO_SERVIDOR, { historia });

    expect(textoDe(w, daCarteira('historia-erro'))).toContain(
      'Não consegui mostrar o histórico. Tente de novo.'
    );
    expect(w.find(daCarteira('dados-do-seguro')).exists()).toBe(true);

    historia.mockResolvedValue([
      { tipo: 'cancelado', quando: CHEGOU_EM, quem: null, mudancas: null },
    ]);
    await clicar(w, `${daCarteira('historia-erro')} button`);

    expect(w.find(daCarteira('historia-erro')).exists()).toBe(false);
    expect(textoDe(w, '[data-passo="cancelado"]')).toContain(
      'Seguro marcado como cancelado.'
    );
  });
});

describe('marcar como cancelado e desfazer o cancelamento', () => {
  it('cancela sem perguntar, avisa quem abriu e deixa desfazer', async () => {
    const w = await abrir(COM_PDF);

    await escolherNoMenu(w, DO_RODAPE.MARCAR_CANCELADO);

    expect(selo(w)).toBe('cancelado');
    expect(avisoVivo(w)).toContain('Seguro marcado como cancelado.');
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(doMenu(w)).toContain(DO_RODAPE.DESFAZER_CANCELAMENTO);
    expect(textoDe(w, '[data-passo="cancelado"]')).toContain('Bia Lunardelli');

    await clicar(w, daCarteira('desfazer'));

    expect(selo(w)).toBe('ativo');
    expect(avisoVivo(w)).toBe('Desfeito.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(w.emitted('mudou')).toHaveLength(2);
  });

  it('"Desfazer o cancelamento" diz o que fez e não tem o que desfazer', async () => {
    const w = await abrir(CANCELADO);

    await escolherNoMenu(w, DO_RODAPE.DESFAZER_CANCELAMENTO);

    expect(selo(w)).toBe('vencido');
    expect(avisoVivo(w)).toBe('Cancelamento desfeito.');
    expect(textoDe(w, '[data-passo="voltou_a_ativo"]')).toContain(
      'Cancelamento desfeito.'
    );
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(doMenu(w)).toContain(DO_RODAPE.MARCAR_CANCELADO);
  });

  it('se outra pessoa já tinha desfeito o cancelamento, diz isso e relê', async () => {
    const seguro = vi
      .fn()
      .mockResolvedValueOnce(CANCELADO_NO_SERVIDOR)
      .mockResolvedValue(DO_SERVIDOR);
    const w = await abrirDoServidor(CANCELADO_NO_SERVIDOR, {
      seguro,
      voltarAAtivo: vi.fn().mockRejectedValue(recusa('nao_cancelado')),
    });

    await escolherNoMenu(w, DO_RODAPE.DESFAZER_CANCELAMENTO);

    expect(alerta(w)).toBe(
      'Este seguro já não estava cancelado. Atualizei a tela.'
    );
    expect(selo(w)).toBe('ativo');
  });

  it('se outra pessoa já tinha cancelado, diz isso e relê o seguro', async () => {
    const seguro = vi
      .fn()
      .mockResolvedValueOnce(DO_SERVIDOR)
      .mockResolvedValue(CANCELADO_NO_SERVIDOR);
    const w = await abrirDoServidor(DO_SERVIDOR, {
      seguro,
      cancelar: vi.fn().mockRejectedValue(recusa('ja_cancelado')),
    });

    await escolherNoMenu(w, DO_RODAPE.MARCAR_CANCELADO);

    expect(alerta(w)).toBe(
      'Este seguro já estava marcado como cancelado. Atualizei a tela.'
    );
    expect(selo(w)).toBe('cancelado');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('falha sem código diz a frase de sempre e não mexe no seguro', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      cancelar: vi.fn().mockRejectedValue(new Error('rede')),
    });

    await escolherNoMenu(w, DO_RODAPE.MARCAR_CANCELADO);

    expect(alerta(w)).toBe('Não consegui fazer isso. Tente de novo.');
    expect(selo(w)).toBe('ativo');
    expect(w.emitted('mudou')).toBeUndefined();
  });
});

describe('a resposta que chega depois de a gaveta trocar de seguro', () => {
  it('o cancelamento atrasado de um seguro não entra no que abriu depois', async () => {
    const resposta = respostaNaMao();
    const cancelar = vi.fn(() => resposta.promessa);
    const fonte = fonteDeDois({ cancelar });
    const w = await abrir(DO_SERVIDOR.id, fonte, { agora: AGORA });

    await escolherNoMenu(w, DO_RODAPE.MARCAR_CANCELADO);
    await trocarDeSeguro(w, OUTRO_DO_SERVIDOR.id);
    resposta.resolver(CANCELADO_NO_SERVIDOR);
    await assentar();

    expect(cancelar.mock.calls[0][0]).toBe(DO_SERVIDOR.id);
    expect(textoDe(w, '[data-view-title]')).toBe(
      'Residencial · Horizonte Seguros'
    );
    expect(selo(w)).toBe('ativo');
    expect(dado(w, 'numero')).toContain(OUTRO_DO_SERVIDOR.numero);
    expect(avisoVivo(w)).toBe('');
    expect(temAlerta(w)).toBe(false);
    expect(fonte.historia.mock.calls.at(-1)).toEqual([OUTRO_DO_SERVIDOR.id]);
    // Quem abriu a gaveta relê: o outro seguro mudou de verdade.
    expect(w.emitted('mudou')).toHaveLength(1);
    // E o seguro que está aberto continua podendo ser cancelado.
    expect(doMenu(w)).toContain(DO_RODAPE.MARCAR_CANCELADO);
  });

  it('a recusa atrasada não vira aviso nem releitura no seguro errado', async () => {
    const resposta = respostaNaMao();
    const fonte = fonteDeDois({ cancelar: vi.fn(() => resposta.promessa) });
    const w = await abrir(DO_SERVIDOR.id, fonte, { agora: AGORA });

    await escolherNoMenu(w, DO_RODAPE.MARCAR_CANCELADO);
    await trocarDeSeguro(w, OUTRO_DO_SERVIDOR.id);
    resposta.recusar(recusa('ja_cancelado'));
    await assentar();

    expect(temAlerta(w)).toBe(false);
    expect(avisoVivo(w)).toBe('');
    expect(selo(w)).toBe('ativo');
    expect(fonte.seguro.mock.calls.map(([id]) => id)).toEqual([
      DO_SERVIDOR.id,
      OUTRO_DO_SERVIDOR.id,
    ]);
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('a correção atrasada não fecha o formulário nem grava no seguro errado', async () => {
    const resposta = respostaNaMao();
    const fonte = fonteDeDois({ corrigir: vi.fn(() => resposta.promessa) });
    const w = await abrir(DO_SERVIDOR.id, fonte, { agora: AGORA });
    await abrirCorrecao(w);
    await escrever(w, 'bem', 'Carro sedã preto');
    await salvar(w);

    await trocarDeSeguro(w, OUTRO_DO_SERVIDOR.id);
    resposta.resolver({ ...DO_SERVIDOR, bem: 'Carro sedã preto' });
    await assentar();

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(dado(w, 'numero')).toContain(OUTRO_DO_SERVIDOR.numero);
    expect(dado(w, 'bem')).toContain('Carro hatch prata');
    expect(avisoVivo(w)).toBe('');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('o PDF guardado no diálogo do seguro anterior não entra no que abriu depois', async () => {
    const resposta = respostaNaMao();
    const semPdf = { ...DO_SERVIDOR, temPdf: false };
    const fonte = fonteDeMentira(semPdf, {
      seguro: vi.fn(async id =>
        id === OUTRO_DO_SERVIDOR.id ? OUTRO_DO_SERVIDOR : semPdf
      ),
      guardarPdf: vi.fn(() => resposta.promessa),
    });
    const w = await abrir(semPdf.id, fonte, { agora: AGORA });
    await clicar(w, daCarteira('gaveta-acao'));
    await escolherArquivo(w, umPdf());

    await trocarDeSeguro(w, OUTRO_DO_SERVIDOR.id);
    resposta.resolver({ ...semPdf, temPdf: true });
    await assentar();

    expect(dado(w, 'numero')).toContain(OUTRO_DO_SERVIDOR.numero);
    expect(avisoVivo(w)).toBe('');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(fonte.historia.mock.calls.at(-1)).toEqual([OUTRO_DO_SERVIDOR.id]);
    expect(w.emitted('mudou')).toHaveLength(1);
  });
});

describe('corrigir', () => {
  it('troca o conteúdo da gaveta pelo formulário e volta', async () => {
    const w = await abrir(COM_PDF);

    await abrirCorrecao(w);

    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(textoDe(w, '[data-view-title]')).toBe('Corrigir o seguro Auto');
    expect(w.get('input[data-campo="numero"]').element.value).toBe('AT-000451');
    expect(w.get('input[data-campo="valor"]').element.value).toBe('2760,00');
    expect(textoDe(w, daCarteira('salvar-correcao'))).toBe('Salvar');
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);

    await clicar(w, daCarteira('voltar-da-correcao'));

    expect(estaAberto(w, 'sair-sem-salvar')).toBe(false);
    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('"Voltar" com algo mudado pergunta antes, e dá para continuar corrigindo', async () => {
    const w = await abrirDoServidor();
    await abrirCorrecao(w);
    await escrever(w, 'bem', 'Carro sedã preto');

    await clicar(w, daCarteira('voltar-da-correcao'));

    const pergunta = dialogoDe(w, 'sair-sem-salvar');
    expect(pergunta.text()).toContain('Sair sem salvar?');
    expect(pergunta.text()).toContain('O que você mudou não fica guardado.');
    expect(pergunta.get('[data-confirmar]').text()).toBe('Sair sem salvar');
    expect(pergunta.get('[data-cancelar]').text()).toBe('Continuar corrigindo');
    expect(pergunta.attributes('data-fechar-fora')).toBe('false');

    await voltarNo(w, 'sair-sem-salvar');

    expect(estaAberto(w, 'sair-sem-salvar')).toBe(false);
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(w.get('input[data-campo="bem"]').element.value).toBe(
      'Carro sedã preto'
    );
  });

  it('"Sair sem salvar" volta ao seguro e não grava nada', async () => {
    const corrigir = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { corrigir });
    await abrirCorrecao(w);
    await escrever(w, 'bem', 'Carro sedã preto');

    await clicar(w, daCarteira('voltar-da-correcao'));
    await confirmarNo(w, 'sair-sem-salvar');

    expect(estaAberto(w, 'sair-sem-salvar')).toBe(false);
    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(dado(w, 'bem')).toContain('Carro hatch prata');
    expect(corrigir).not.toHaveBeenCalled();
    expect(w.emitted('fechar')).toBeUndefined();
  });

  it.each(Object.keys(JEITOS_DE_FECHAR))(
    'fechar a gaveta por %s com algo mudado também pergunta',
    async jeito => {
      const w = await abrirDoServidor();
      await abrirCorrecao(w);
      await escrever(w, 'bem', 'Carro sedã preto');

      await JEITOS_DE_FECHAR[jeito](w);
      await assentar();

      expect(estaAberto(w, 'sair-sem-salvar')).toBe(true);
      expect(w.emitted('fechar')).toBeUndefined();

      await confirmarNo(w, 'sair-sem-salvar');

      expect(w.emitted('fechar')).toHaveLength(1);
    }
  );

  it('sem nada mudado, fechar a gaveta no meio da correção não pergunta', async () => {
    const w = await abrirDoServidor();
    await abrirCorrecao(w);

    await w.get('[role="dialog"] header button').trigger('click');

    expect(estaAberto(w, 'sair-sem-salvar')).toBe(false);
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('salvar sem mudar nada diz que nada mudou e não grava', async () => {
    const corrigir = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { corrigir });
    await abrirCorrecao(w);

    await salvar(w);

    expect(textoDe(w, daCarteira('nada-mudou'))).toBe(
      'Você ainda não mudou nada. Mude o que está errado e salve.'
    );
    expect(corrigir).not.toHaveBeenCalled();
  });

  it('o botão Salvar está sempre ligado: clicar diz o que falta, no campo', async () => {
    const corrigir = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { corrigir });
    await abrirCorrecao(w);
    await escrever(w, 'numero', '');
    await escrever(w, 'valor', 'dois mil');

    expect(
      w.get(daCarteira('salvar-correcao')).attributes('disabled')
    ).toBeUndefined();
    await salvar(w);

    const numero = w.get('input[data-campo="numero"]');
    expect(w.findAll(daCarteira('falta')).map(falta => falta.text())).toEqual([
      'Escreva o número da apólice.',
      'Escreva o valor que o cliente paga em reais, como 1.250,00. Se não souber, deixe em branco.',
    ]);
    expect(numero.attributes('aria-invalid')).toBe('true');
    expect(document.activeElement).toBe(numero.element);
    expect(corrigir).not.toHaveBeenCalled();
  });

  it('salva só o que mudou, volta para o seguro e conta no histórico', async () => {
    const w = await abrir(COM_PDF);
    await abrirCorrecao(w);
    await escrever(w, 'valor', '3.000,00');

    await salvar(w);

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(avisoVivo(w)).toBe('Salvo.');
    expect(dado(w, 'valor')).toContain('R$ 3.000,00');
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(historico(w).map(semEspacoDuro)).toEqual([
      'Valor que o cliente paga: era R$ 2.760,00, ficou R$ 3.000,00',
    ]);
  });

  it('o campo do valor diz que é o que o cliente paga, em reais', async () => {
    const w = await abrirDoServidor();
    await abrirCorrecao(w);

    const campo = w.get('input[data-campo="valor"]');
    expect(w.get(`label[for="${campo.attributes('id')}"]`).text()).toBe(
      'Valor que o cliente paga (R$)'
    );
  });

  it('manda à fonte só os campos que mudaram', async () => {
    const corrigir = vi.fn().mockResolvedValue({ ...DO_SERVIDOR, valor: null });
    const w = await abrirDoServidor(DO_SERVIDOR, { corrigir });
    await abrirCorrecao(w);
    await escrever(w, 'valor', '');
    await escrever(w, 'bem', ' Carro sedã preto ');

    await salvar(w);

    expect(corrigir).toHaveBeenCalledWith(DO_SERVIDOR.id, {
      valor: null,
      bem: 'Carro sedã preto',
    });
  });

  it('quando o servidor recusa, diz o motivo sem repetir o que foi digitado', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      corrigir: vi.fn().mockRejectedValue(recusa('apolice_repetida')),
    });
    await abrirCorrecao(w);
    await escrever(w, 'numero', 'AT-999999');

    await salvar(w);

    expect(alerta(w)).toBe(
      'Já existe um seguro com essa seguradora, esse número e essa data de término. Confira o número da apólice.'
    );
    expect(alerta(w)).not.toContain('AT-999999');
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(w.get('input[data-campo="numero"]').element.value).toBe('AT-999999');
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('falha sem código ao salvar diz a frase de sempre', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      corrigir: vi.fn().mockRejectedValue(new Error('rede')),
    });
    await abrirCorrecao(w);
    await escrever(w, 'bem', 'Carro sedã preto');

    await salvar(w);

    expect(alerta(w)).toBe('Não consegui salvar. Tente de novo.');
  });

  it('sem a lista de seguradoras da conta, o formulário abre mesmo assim', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      opcoesDeFiltro: vi.fn().mockRejectedValue(new Error('rede')),
    });

    await abrirCorrecao(w);

    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(w.find('input[data-campo="outraSeguradora"]').exists()).toBe(false);
  });
});

describe('o PDF', () => {
  it('"Ver PDF" pede o link na hora do clique', async () => {
    const pdf = vi.fn().mockResolvedValue('https://arquivos.example/apolice');
    const w = await abrirDoServidor(DO_SERVIDOR, { pdf });

    expect(pdf).not.toHaveBeenCalled();
    await clicar(w, daCarteira('gaveta-acao'));

    expect(pdf).toHaveBeenCalledWith(DO_SERVIDOR.id);
    expect(w.find(daCarteira('alerta-da-gaveta')).exists()).toBe(false);
  });

  it('se o PDF foi apagado por outra pessoa, diz isso e relê o seguro', async () => {
    const seguro = vi
      .fn()
      .mockResolvedValueOnce(DO_SERVIDOR)
      .mockResolvedValue({ ...DO_SERVIDOR, temPdf: false });
    const w = await abrirDoServidor(DO_SERVIDOR, {
      seguro,
      pdf: vi.fn().mockRejectedValue(recusa('sem_pdf')),
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(alerta(w)).toBe(
      'Este seguro não tem mais PDF guardado. Atualizei a tela.'
    );
    expect(azul(w).text()).toBe('Guardar o PDF');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('se o link não vem, diz que não abriu', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {
      pdf: vi.fn().mockRejectedValue(new Error('rede')),
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(alerta(w)).toBe('Não consegui abrir o PDF. Tente de novo.');
  });

  it('guardar o PDF é um passo só, e dá para desfazer quando não havia PDF', async () => {
    const w = await abrir(SEM_PDF);

    await clicar(w, daCarteira('gaveta-acao'));
    expect(textoDe(w, '[data-relacionamentos="titulo-do-dialogo"]')).toBe(
      'Guardar o PDF do seguro Residencial'
    );
    await clicar(w, daCarteira('usar-exemplo'));

    expect(w.find(daCarteira('guardar-pdf')).exists()).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
    expect(avisoVivo(w)).toContain('PDF guardado.');
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(textoDe(w, '[data-passo="pdf_anexado"]')).toContain('PDF guardado.');

    await clicar(w, daCarteira('desfazer'));

    expect(azul(w).text()).toBe('Guardar o PDF');
    expect(avisoVivo(w)).toBe('Desfeito.');
  });

  it('o arquivo escolhido vai inteiro à fonte, e o nome dele não aparece', async () => {
    const guardarPdf = vi
      .fn()
      .mockResolvedValue({ ...DO_SERVIDOR, temPdf: true });
    const arquivo = umPdf();
    const w = await abrirDoServidor(
      { ...DO_SERVIDOR, temPdf: false },
      { guardarPdf }
    );

    await clicar(w, daCarteira('gaveta-acao'));
    expect(w.find(daCarteira('usar-exemplo')).exists()).toBe(false);
    await escolherArquivo(w, arquivo);

    expect(guardarPdf).toHaveBeenCalledWith(DO_SERVIDOR.id, arquivo);
    expect(azul(w).text()).toBe('Ver PDF');
    expect(document.body.textContent).not.toContain('contrato-da-ana');
  });

  it('no seguro vencido, "Guardar o PDF" do "⋯" abre o mesmo diálogo', async () => {
    const w = await abrir(VENCIDO_SEM_PDF);

    await escolherNoMenu(w, DO_RODAPE.GUARDAR_PDF);
    await clicar(w, daCarteira('usar-exemplo'));

    expect(azul(w).text()).toBe('Ver PDF');
    expect(avisoVivo(w)).toContain('PDF guardado.');
  });

  it('trocar o PDF pede confirmação depois de escolher, e não tem desfazer', async () => {
    const w = await abrir(COM_PDF);

    await escolherNoMenu(w, DO_RODAPE.GUARDAR_OUTRO_PDF);
    const dialogo = textoDe(w, daCarteira('guardar-pdf'));
    expect(dialogo).toContain('Guardar outro PDF do seguro Auto');
    expect(dialogo).toContain('Depois de escolher, você confirma a troca.');
    await clicar(w, daCarteira('usar-exemplo'));

    const pergunta = dialogoDe(w, 'trocar-pdf');
    expect(pergunta.text()).toContain('Trocar o PDF deste seguro?');
    expect(pergunta.text()).toContain(
      'O PDF que está guardado sai e não volta. O novo entra no lugar.'
    );
    expect(pergunta.get('[data-confirmar]').text()).toBe('Trocar o PDF');
    expect(pergunta.get('[data-cancelar]').text()).toBe('Voltar');
    expect(pergunta.attributes('data-fechar-fora')).toBe('false');
    expect(w.find('[data-passo="pdf_anexado"]').exists()).toBe(false);

    await confirmarNo(w, 'trocar-pdf');

    expect(estaAberto(w, 'trocar-pdf')).toBe(false);
    expect(estaAberto(w, 'guardar-pdf')).toBe(false);
    expect(avisoVivo(w)).toBe('PDF trocado.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(textoDe(w, '[data-passo="pdf_anexado"]')).toContain('PDF guardado.');
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('"Voltar" na pergunta da troca deixa o PDF que estava', async () => {
    const guardarPdf = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { guardarPdf });

    await escolherNoMenu(w, DO_RODAPE.GUARDAR_OUTRO_PDF);
    await escolherArquivo(w, umPdf());
    await voltarNo(w, 'trocar-pdf');

    expect(guardarPdf).not.toHaveBeenCalled();
    expect(estaAberto(w, 'trocar-pdf')).toBe(false);
    expect(estaAberto(w, 'guardar-pdf')).toBe(true);
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('a troca confirmada manda à fonte o arquivo que a pessoa escolheu', async () => {
    const guardarPdf = vi.fn().mockResolvedValue(DO_SERVIDOR);
    const arquivo = umPdf();
    const w = await abrirDoServidor(DO_SERVIDOR, { guardarPdf });

    await escolherNoMenu(w, DO_RODAPE.GUARDAR_OUTRO_PDF);
    await escolherArquivo(w, arquivo);
    await confirmarNo(w, 'trocar-pdf');

    expect(guardarPdf).toHaveBeenCalledWith(DO_SERVIDOR.id, arquivo);
    expect(avisoVivo(w)).toBe('PDF trocado.');
    expect(document.body.textContent).not.toContain('contrato-da-ana');
  });

  it('o que não é PDF fica no diálogo, com a frase do motivo', async () => {
    const w = await abrirDoServidor(
      { ...DO_SERVIDOR, temPdf: false },
      { guardarPdf: vi.fn().mockRejectedValue(recusa('tipo')) }
    );

    await clicar(w, daCarteira('gaveta-acao'));
    await escolherArquivo(w, umPdf());

    expect(textoDe(w, daCarteira('erro-pdf'))).toBe(
      'Este arquivo não é um PDF. Escolha o PDF da apólice.'
    );
    expect(w.find(daCarteira('soltar-pdf')).exists()).toBe(true);
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it('PDF grande demais nem é enviado, e a frase diz o que fazer', async () => {
    const guardarPdf = vi.fn();
    const w = await abrirDoServidor(
      { ...DO_SERVIDOR, temPdf: false },
      { guardarPdf }
    );
    await clicar(w, daCarteira('gaveta-acao'));

    await escolherArquivo(w, umPdfGrande());

    expect(guardarPdf).not.toHaveBeenCalled();
    expect(textoDe(w, daCarteira('erro-pdf'))).toBe(PDF_GRANDE_DEMAIS);
    expect(w.find(daCarteira('soltar-pdf')).exists()).toBe(true);
  });

  it('PDF grande demais não chega a perguntar pela troca', async () => {
    const guardarPdf = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { guardarPdf });
    await escolherNoMenu(w, DO_RODAPE.GUARDAR_OUTRO_PDF);

    await escolherArquivo(w, umPdfGrande());

    expect(estaAberto(w, 'trocar-pdf')).toBe(false);
    expect(textoDe(w, daCarteira('erro-pdf'))).toBe(PDF_GRANDE_DEMAIS);
    expect(guardarPdf).not.toHaveBeenCalled();
  });

  it('a recusa do servidor por tamanho e a falha sem código têm cada uma a sua frase', async () => {
    const guardarPdf = vi.fn().mockRejectedValue(recusa('arquivo_grande'));
    const w = await abrirDoServidor(
      { ...DO_SERVIDOR, temPdf: false },
      { guardarPdf }
    );
    await clicar(w, daCarteira('gaveta-acao'));

    await escolherArquivo(w, umPdf());
    expect(textoDe(w, daCarteira('erro-pdf'))).toBe(PDF_GRANDE_DEMAIS);

    guardarPdf.mockRejectedValue(new Error('rede'));
    await escolherArquivo(w, umPdf());
    expect(textoDe(w, daCarteira('erro-pdf'))).toBe(
      'Não consegui guardar o PDF. Tente de novo.'
    );
  });

  it('apagar o PDF pede confirmação, porque não tem volta', async () => {
    const w = await abrir(COM_PDF);

    await escolherNoMenu(w, DO_RODAPE.APAGAR_PDF);
    const pergunta = dialogoDe(w, 'apagar-pdf');
    expect(pergunta.text()).toContain('Apagar o PDF deste seguro?');
    expect(pergunta.get('[data-confirmar]').text()).toBe('Apagar o PDF');
    expect(pergunta.attributes('data-fechar-fora')).toBe('false');
    expect(azul(w).text()).toBe('Ver PDF');

    await confirmarNo(w, 'apagar-pdf');

    expect(estaAberto(w, 'apagar-pdf')).toBe(false);
    expect(azul(w).text()).toBe('Guardar o PDF');
    expect(avisoVivo(w)).toBe('PDF apagado.');
    expect(textoDe(w, '[data-passo="pdf_tirado"]')).toContain('PDF apagado.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('"Voltar" na pergunta de apagar não apaga nada', async () => {
    const tirarPdf = vi.fn();
    const w = await abrirDoServidor(DO_SERVIDOR, { tirarPdf });

    await escolherNoMenu(w, DO_RODAPE.APAGAR_PDF);
    await voltarNo(w, 'apagar-pdf');

    expect(tirarPdf).not.toHaveBeenCalled();
    expect(estaAberto(w, 'apagar-pdf')).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
  });

  it('se apagar não dá certo, a pergunta fica aberta com a frase dentro', async () => {
    const tirarPdf = vi.fn().mockRejectedValue(new Error('rede'));
    const w = await abrirDoServidor(DO_SERVIDOR, { tirarPdf });
    await escolherNoMenu(w, DO_RODAPE.APAGAR_PDF);

    await confirmarNo(w, 'apagar-pdf');

    expect(estaAberto(w, 'apagar-pdf')).toBe(true);
    expect(textoDe(w, daCarteira('alerta-do-dialogo'))).toBe(
      'Não consegui fazer isso. Tente de novo.'
    );
    expect(temAlerta(w)).toBe(false);
    expect(azul(w).text()).toBe('Ver PDF');
    expect(w.emitted('mudou')).toBeUndefined();

    tirarPdf.mockResolvedValue({ ...DO_SERVIDOR, temPdf: false });
    await confirmarNo(w, 'apagar-pdf');

    expect(estaAberto(w, 'apagar-pdf')).toBe(false);
    expect(avisoVivo(w)).toBe('PDF apagado.');
    expect(azul(w).text()).toBe('Guardar o PDF');
  });

  it('se o PDF já tinha sido apagado, a pergunta fecha e a gaveta relê', async () => {
    const seguro = vi
      .fn()
      .mockResolvedValueOnce(DO_SERVIDOR)
      .mockResolvedValue({ ...DO_SERVIDOR, temPdf: false });
    const w = await abrirDoServidor(DO_SERVIDOR, {
      seguro,
      tirarPdf: vi.fn().mockRejectedValue(recusa('sem_pdf')),
    });
    await escolherNoMenu(w, DO_RODAPE.APAGAR_PDF);

    await confirmarNo(w, 'apagar-pdf');

    expect(estaAberto(w, 'apagar-pdf')).toBe(false);
    expect(alerta(w)).toBe(
      'Este seguro não tem mais PDF guardado. Atualizei a tela.'
    );
    expect(azul(w).text()).toBe('Guardar o PDF');
    expect(w.emitted('mudou')).toHaveLength(1);
  });
});

describe('quem só pode ver', () => {
  it('com PDF, tem só "Ver PDF"', async () => {
    const w = await abrirDoServidor(DO_SERVIDOR, {}, { podeEditar: false });

    expect(azul(w).text()).toBe('Ver PDF');
    expect(w.find(daCarteira('corrigir')).exists()).toBe(false);
    expect(w.find(daCarteira('mais-do-seguro')).exists()).toBe(false);
    expect(w.find(daCarteira('dados-do-seguro')).exists()).toBe(true);
  });

  it('sem PDF, não tem rodapé nem botão desligado', async () => {
    const w = await abrirDoServidor(
      { ...DO_SERVIDOR, temPdf: false },
      {},
      { podeEditar: false }
    );

    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
    expect(w.find('footer').exists()).toBe(false);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });
});

describe('carregando, erro e seguro que não está', () => {
  it('enquanto carrega mostra o esqueleto e o título diz que está abrindo', async () => {
    const w = await abrir(COM_PDF, fonteDaDemo({ demo: 'carregando' }));

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(textoDe(w, '[data-view-title]')).toBe('Abrindo o seguro');
    expect(w.find('footer').exists()).toBe(false);
  });

  it('no erro, diz a frase e tenta de novo', async () => {
    const seguro = vi
      .fn()
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValue(DO_SERVIDOR);
    const w = await abrirDoServidor(DO_SERVIDOR, { seguro });

    expect(textoDe(w, daCarteira('erro'))).toContain(
      'Não consegui abrir este seguro. Tente de novo.'
    );
    await clicar(w, `${daCarteira('erro')} button`);

    expect(w.find(daCarteira('dados-do-seguro')).exists()).toBe(true);
  });

  it('seguro que não existe mais: diz isso e o botão fecha', async () => {
    const w = await abrir(NAO_EXISTE);

    expect(textoDe(w, daCarteira('seguro-nao-esta'))).toContain(
      'Este seguro não está mais aqui.'
    );
    await w.get(`${daCarteira('seguro-nao-esta')} button`).trigger('click');

    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it.each([
    [NAO_ACHEI, 'seguro-nao-esta', 'Este seguro não está mais aqui.'],
    [SEM_ACESSO, 'seguro-sem-acesso', 'Você não tem acesso a este seguro.'],
  ])('a falha %s do servidor vira a tela certa', async (name, marca, frase) => {
    const falha = Object.assign(new Error('x'), { name });
    const w = await abrirDoServidor(DO_SERVIDOR, {
      seguro: vi.fn().mockRejectedValue(falha),
    });

    expect(textoDe(w, daCarteira(marca))).toContain(frase);
    expect(w.find('footer').exists()).toBe(false);
  });
});

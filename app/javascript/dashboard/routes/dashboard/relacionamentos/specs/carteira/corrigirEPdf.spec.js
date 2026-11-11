import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import SoltarArquivo from '../../components/trazer/SoltarArquivo.vue';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { assentar, carregarDemonstracao, daCarteira, textoDe } from './apoio';

// Corrigir o seguro e anexar o PDF (#2897, telas 5 e 6), dentro da gaveta, com
// a carteira fictícia e o texto de verdade em pt_BR. Nenhum botão fica
// desligado por falta de preenchimento: o clique diz o que falta, leva o foco
// ao campo e marca o campo para o leitor de tela.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const EM_RENOVACAO = 1;
const ATIVO = 2;
const RENOVADO = 102;

const fonteDaDemo = () => carteiraFonte({ demo: 'cheio', atraso: 0 });

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
const corrigir = async w => {
  await w.get(daCarteira('corrigir')).trigger('click');
  await assentar();
};
const campo = (w, nome) => w.get(`input[data-campo="${nome}"]`);
const salvar = async w => {
  await w.get(daCarteira('salvar-correcao')).trigger('click');
  await assentar();
};
const abrirPdfPeloMenu = async w => {
  await w.get(`${daCarteira('mais-do-seguro')} button`).trigger('click');
  await w.get(daCarteira('anexar-outro-pdf')).trigger('click');
};
const soltar = async (w, nome) => {
  w.getComponent(SoltarArquivo).vm.$emit('arquivo', { name: nome });
  await assentar();
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

describe('corrigir o seguro', () => {
  it('troca o conteúdo da gaveta, com os dados de agora, e o foco vai ao título', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
    expect(textoDe(w, '[data-view-title]')).toBe('Corrigir o seguro Auto');
    expect(document.activeElement).toBe(w.get('[data-view-title]').element);
    expect(campo(w, 'numero').element.value).toBe('AT-000451');
    expect(campo(w, 'valor').element.value).toBe('2760,00');
  });

  it('Salvar fica sempre ligado; sem mudança, diz isso e leva o foco ao primeiro campo', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    const botao = w.get(daCarteira('salvar-correcao'));
    expect(botao.attributes('disabled')).toBeUndefined();
    await salvar(w);

    const aviso = w.get(daCarteira('nada-mudou'));
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toBe(
      'Você ainda não mudou nada. Mude o que está errado e salve.'
    );
    expect(document.activeElement.getAttribute('aria-describedby')).toContain(
      aviso.attributes('id')
    );
    expect(w.find(daCarteira('corrigir-gaveta')).exists()).toBe(true);
  });

  it('campo vazio: o aviso fala o que falta, o campo fica marcado e recebe o foco', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    await campo(w, 'numero').setValue('');
    await salvar(w);

    const numero = campo(w, 'numero');
    const aviso = w.get(daCarteira('falta'));
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toBe('Escreva o número da apólice.');
    expect(numero.attributes('aria-invalid')).toBe('true');
    expect(numero.attributes('aria-describedby')).toBe(aviso.attributes('id'));
    expect(document.activeElement).toBe(numero.element);
    expect(w.get(daCarteira('salvar-correcao')).attributes('disabled')).toBe(
      undefined
    );

    await numero.setValue('AT-000999');
    expect(w.find(daCarteira('falta')).exists()).toBe(false);
    expect(numero.attributes('aria-invalid')).toBeUndefined();
  });

  it('data de término antes do começo: avisa no campo de término', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    await campo(w, 'termina').setValue('2001-01-01');
    await salvar(w);

    expect(w.get(daCarteira('falta')).text()).toBe(
      'O seguro termina depois de começar. Confira as duas datas.'
    );
    expect(document.activeElement).toBe(campo(w, 'termina').element);
  });

  it('salva, volta para o seguro, avisa "Salvo." e a história registra', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    await campo(w, 'valor').setValue('2.900,50');
    await salvar(w);

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Salvo.');
    expect(textoDe(w, '[data-dado="valor"]')).toContain('R$ 2.900,50 por ano');
    expect(textoDe(w, '[data-passo="corrigido"]')).toContain(
      'Seguro corrigido à mão. · Você'
    );
    expect(w.emitted('mudou')).toHaveLength(1);
  });

  it('se salvar falhar, fica no formulário e diz que não conseguiu', async () => {
    const fonte = fonteDaDemo();
    const w = await abrir(EM_RENOVACAO, {
      ...fonte,
      corrigir: () => Promise.reject(new Error('fora do ar')),
    });
    await corrigir(w);

    await campo(w, 'valor').setValue('2.900,50');
    await salvar(w);

    const erro = w.get(daCarteira('erro-correcao'));
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toBe('Não consegui salvar. Tente de novo.');
    expect(campo(w, 'valor').element.value).toBe('2.900,50');
  });

  it('Voltar sai sem salvar', async () => {
    const w = await abrir(EM_RENOVACAO);
    await corrigir(w);

    await campo(w, 'valor').setValue('1,00');
    await w.get(daCarteira('voltar-da-correcao')).trigger('click');
    await assentar();

    expect(textoDe(w, '[data-dado="valor"]')).toContain('R$ 2.760,00 por ano');
    expect(w.emitted('mudou')).toBeUndefined();
  });
});

describe('anexar o PDF e ver o que mudou', () => {
  it('a área de soltar só convida: não fala de custo nem de planilha', async () => {
    const w = await abrir(ATIVO);
    await abrirPdfPeloMenu(w);

    expect(textoDe(w, daCarteira('soltar-pdf'))).toBe(
      'Arraste o PDF aqui ou clique para escolher'
    );
  });

  it('arquivo que não é PDF e PDF que não deu para ler: cada um com a sua frase', async () => {
    const w = await abrir(ATIVO);
    await abrirPdfPeloMenu(w);

    await soltar(w, 'foto.png');
    expect(w.get(daCarteira('erro-pdf')).text()).toBe(
      'Este arquivo não é um PDF de apólice. Escolha outro.'
    );

    await soltar(w, 'ilegivel.pdf');
    expect(w.get(daCarteira('erro-pdf')).text()).toBe(
      'Não consegui ler este PDF. Tente de novo.'
    );
    expect(w.get(daCarteira('erro-pdf')).attributes('role')).toBe('alert');
  });

  it('PDF que confere: só guarda', async () => {
    const w = await abrir(ATIVO);
    await abrirPdfPeloMenu(w);
    await w.get(daCarteira('usar-exemplo')).trigger('click');
    await assentar();

    expect(w.find(daCarteira('o-que-mudou')).exists()).toBe(false);
    expect(w.get('[data-foco-do-passo]').text()).toBe(
      'O PDF confere com o que já estava aqui.'
    );
    expect(w.find(daCarteira('manter')).exists()).toBe(false);

    await w.get(daCarteira('usar-pdf')).trigger('submit');
    await assentar();

    expect(w.find(daCarteira('anexar-pdf')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('PDF guardado.');
  });

  it('renovado: o PDF é a apólice nova; mostra o que mudou e usa o que está no PDF', async () => {
    const w = await abrir(RENOVADO);
    await w.get(daCarteira('gaveta-acao')).trigger('click');
    expect(w.find(daCarteira('soltar-pdf')).exists()).toBe(true);
    expect(textoDe(w, daCarteira('anexar-pdf'))).toContain(
      'Anexar a apólice nova'
    );

    await w.get(daCarteira('usar-exemplo')).trigger('click');
    await assentar();

    const tabela = w.get(daCarteira('o-que-mudou'));
    expect(
      tabela.findAll('[data-mudanca]').map(l => l.attributes('data-mudanca'))
    ).toEqual(['numero', 'comeca', 'termina', 'valor']);
    expect(document.activeElement).toBe(w.get('[data-foco-do-passo]').element);
    expect(w.get(daCarteira('usar-pdf')).text()).toBe('Usar o que está no PDF');
    expect(w.get(daCarteira('manter')).text()).toBe('Manter como está');

    await w.get(daCarteira('usar-pdf')).trigger('submit');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain(
      'Apólice nova guardada.'
    );
    expect(w.get(daCarteira('gaveta-acao')).text()).toBe('Ver PDF');
    expect(w.find('[data-passo="apolice_nova"]').text()).toContain(
      'A anterior era a nº AU-77031.'
    );

    await w.get(daCarteira('desfazer')).trigger('click');
    await assentar();
    expect(w.get(daCarteira('gaveta-acao')).text()).toBe(
      'Anexar a apólice nova'
    );
  });

  it('o que foi corrigido à mão fica, a não ser que a pessoa peça o do PDF', async () => {
    const w = await abrir(ATIVO);
    await corrigir(w);
    await campo(w, 'valor').setValue('700,00');
    await salvar(w);

    await abrirPdfPeloMenu(w);
    await w.get(daCarteira('usar-exemplo')).trigger('click');
    await assentar();

    const tabela = w.get(daCarteira('o-que-mudou'));
    expect(tabela.text()).toContain('Você corrigiu à mão. Fica o seu.');
    await tabela.get(daCarteira('usar-o-do-pdf')).trigger('click');
    expect(tabela.text()).toContain('Vai ficar o do PDF.');

    await w.get(daCarteira('usar-pdf')).trigger('submit');
    await assentar();
    expect(textoDe(w, '[data-dado="valor"]')).toContain('R$ 640,00 por ano');
  });

  it('"Manter como está" guarda o PDF sem mexer nos dados', async () => {
    const w = await abrir(RENOVADO);
    await w.get(daCarteira('gaveta-acao')).trigger('click');
    await w.get(daCarteira('usar-exemplo')).trigger('click');
    await assentar();

    await w.get(daCarteira('manter')).trigger('click');
    await assentar();

    expect(textoDe(w, '[data-dado="numero"]')).toContain('AU-77031');
    expect(w.find(daCarteira('anexar-pdf')).exists()).toBe(false);
  });
});

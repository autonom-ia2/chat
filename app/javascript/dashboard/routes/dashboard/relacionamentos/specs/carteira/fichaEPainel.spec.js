import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import PainelDeSeguros from '../../components/carteira/PainelDeSeguros.vue';
import FichaDaEmpresaPage from '../../pages/FichaDaEmpresaPage.vue';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';
import { segurosNoPainel } from '../../carteira/segurosNoPainel';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { usarDemo } from '../../fonte/modoDemo';
import { formatarMes } from '../../ficha/formatos';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  textoDe,
} from './apoio';

// Os seguros na ficha da pessoa, na ficha da empresa e no painel da conversa
// (#2897, telas 3 e 7), com a carteira fictícia e o texto em pt_BR. A
// demonstração entra pelo endereço (`?demo=`), como no navegador.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
// As fontes de demonstração sem o atraso de 300 ms.
const semAtraso = vi.hoisted(() => nome => async importOriginal => {
  const real = await importOriginal();
  return { ...real, [nome]: opcoes => real[nome]({ ...opcoes, atraso: 0 }) };
});
vi.mock('../../fonte/fichaFonte', semAtraso('fichaFonte'));
vi.mock('../../fonte/carteiraFonte', semAtraso('carteiraFonte'));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const COM_TRES_SEGUROS = 23;
const SEM_SEGURO = 27;
const COM_SEGURO_EM_OUTRA_CORRETORA = 20;
const EMPRESA_SEGURADA = 23;

const rota = useRoute();
const roteador = useRouter();

let aberta;
const montar = async pagina => {
  aberta = mount(pagina, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  await assentar();
  return aberta;
};
const abrirPessoa = (id, query = {}) => {
  rota.query = { demo: 'cheio', ...query };
  rota.params = { contactId: String(id) };
  return montar(FichaDaPessoaPage);
};
const abrirEmpresa = id => {
  rota.query = { demo: 'cheio' };
  rota.params = { companyId: String(id) };
  return montar(FichaDaEmpresaPage);
};
const seguros = w => w.findAll(daCarteira('seguro'));
const apolices = w => seguros(w).map(s => s.attributes('data-apolice'));
// A fonte espera em setTimeout: quem pergunta direto a ela anda o relógio.
const daFonte = async pergunta => {
  const resposta = pergunta(carteiraFonte({ demo: 'cheio' }));
  await assentar();
  return resposta;
};
const noEndereco = busca => window.history.replaceState({}, '', `/${busca}`);

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  usarDemo({ demo: 'desligado' });
  noEndereco('');
  vi.clearAllMocks();
});

describe('ficha da pessoa: o bloco Seguros', () => {
  it('é o primeiro da coluna principal, com um seguro por linha, o mais urgente em cima', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS);

    const coluna = w.get(doBlocoA('coluna-principal'));
    expect(coluna.element.firstElementChild).toBe(
      w.get(daCarteira('seguros')).element
    );
    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros (3)');
    expect(apolices(w)).toEqual(['1', '2', '3']);

    const primeiro = textoDe(w, daCarteira('seguro'));
    expect(primeiro).toContain('Auto');
    expect(primeiro).toContain('Em renovação');
    expect(primeiro).toContain('Seguradora Atlântica · nº AT-000451');
    expect(primeiro).toContain('Vence em 18 dias · ');
  });

  it('o bloco não tem botão cheio: o da ficha continua sendo o único', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS);

    const botoes = w.get(daCarteira('seguros')).findAll('button');
    expect(botoes.some(b => b.classes().includes('bg-n-blue-11'))).toBe(false);
  });

  it('o botão PDF diz de qual seguro é e avisa o que vai abrir', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS);

    const pdf = w.get(daCarteira('seguro-pdf'));
    expect(pdf.attributes('aria-label')).toBe('Ver o PDF do seguro Auto');
    await pdf.trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Abrindo o PDF do seguro Auto');
  });

  it('clicar na linha põe o seguro no endereço e abre a gaveta', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS);

    await seguros(w)[1].get('button[aria-label^="Abrir"]').trigger('click');
    await assentar();

    expect(rota.query).toEqual({ demo: 'cheio', apolice: '2' });
    expect(textoDe(w, '[data-view-title]')).toBe(
      'Residencial · Horizonte Seguros'
    );
  });

  it('o endereço com o seguro já abre a gaveta', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS, { apolice: '1' });

    expect(w.find(daCarteira('gaveta-seguro')).exists()).toBe(true);
    expect(w.get(daCarteira('gaveta-acao')).text()).toBe('Abrir a renovação');
  });

  it('"Cliente desde" passa a ser o começo do seguro mais antigo', async () => {
    const todos = await daFonte(fonte => fonte.daPessoa(COM_TRES_SEGUROS));
    const maisAntigo = Math.min(...todos.map(seguro => seguro.comeca));

    const w = await abrirPessoa(COM_TRES_SEGUROS);

    expect(textoDe(w, doBlocoA('ficha-pessoa'))).toContain(
      `Cliente desde ${formatarMes(maisAntigo, 'pt-BR')}`
    );
  });

  it('sem seguro: só a frase', async () => {
    const w = await abrirPessoa(SEM_SEGURO);

    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros (0)');
    expect(w.get(daCarteira('seguros-vazio')).text()).toBe(
      'Nenhum seguro ainda.'
    );
    expect(w.get(daCarteira('seguros')).find('button').exists()).toBe(false);
  });

  it('seguro em outra corretora: só informa, com o lembrete', async () => {
    const w = await abrirPessoa(COM_SEGURO_EM_OUTRA_CORRETORA);

    const linha = w.get(daCarteira('seguro'));
    const texto = textoDe(w, daCarteira('seguro'));
    expect(texto).toContain('Em outra corretora');
    expect(texto).toContain('Seguradora Aurora · está em outra corretora');
    expect(texto).toContain('Vamos lembrar você em ');
    expect(texto).toContain(', 60 dias antes de vencer.');
    expect(linha.find('button').exists()).toBe(false);
  });

  it('seguro sem PDF: "Anexar PDF" abre o passo de anexar', async () => {
    const { itens } = await daFonte(fonte => fonte.listarTodos({}));
    const semPdf = itens.find(seguro => !seguro.temPdf && !seguro.canceladoEm);

    const w = await abrirPessoa(semPdf.pessoaId);
    await w
      .get(`${daCarteira('seguro')}[data-apolice="${semPdf.id}"]`)
      .get(daCarteira('seguro-anexar'))
      .trigger('click');

    expect(w.find(daCarteira('soltar-pdf')).exists()).toBe(true);
  });

  it('carregando só os seguros: o esqueleto no cartão, o resto da ficha na tela', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS, {
      'demo-carteira': 'carregando',
    });

    expect(w.find(daCarteira('seguros-carregando')).exists()).toBe(true);
    expect(w.find(doBlocoA('conversas')).exists()).toBe(true);
  });

  it('erro só nos seguros: a frase e "Tentar de novo" no cartão, o resto continua', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS, { 'demo-carteira': 'erro' });

    const erro = w.get(daCarteira('seguros-erro'));
    expect(erro.text()).toContain(
      'Não consegui mostrar os seguros. Tente de novo.'
    );
    expect(erro.find('button').exists()).toBe(true);
    expect(w.find(doBlocoA('conversas')).exists()).toBe(true);
  });

  it('conta de outro segmento: a ficha é a do bloco A, sem o bloco', async () => {
    const w = await abrirPessoa(COM_TRES_SEGUROS, { demo: 'fora-do-segmento' });

    expect(w.find(doBlocoA('ficha-pessoa')).exists()).toBe(true);
    expect(w.find(daCarteira('seguros')).exists()).toBe(false);
  });
});

describe('ficha da empresa: os seguros em nome dela', () => {
  it('vêm depois de Pessoas, com o título da empresa', async () => {
    const w = await abrirEmpresa(EMPRESA_SEGURADA);

    const bloco = w.get(daCarteira('seguros-da-empresa'));
    expect(bloco.get('h2').text()).toBe('Seguros da empresa (1)');
    expect(textoDe(w, daCarteira('seguro'))).toContain('Empresarial');
    expect(bloco.element.previousElementSibling).toBe(
      w.get(doBlocoA('pessoas-da-empresa')).element
    );
  });
});

describe('painel da conversa: os seguros da pessoa', () => {
  const abrirPainel = async (busca = '') => {
    usarDemo({ demo: 'cheio' });
    noEndereco(busca);
    return montar(PainelDeSeguros);
  };

  it('só existe na demonstração de conta de seguros', () => {
    expect(segurosNoPainel('')).toBeNull();
    expect(segurosNoPainel('?demo=fora-do-segmento')).toBeNull();
    expect(segurosNoPainel('?demo=cheio')).not.toBeNull();
  });

  it('uma linha compacta por seguro, aberto por padrão; o título recolhe e abre', async () => {
    const w = await abrirPainel();

    const linhas = w.findAll(daCarteira('painel-seguro'));
    expect(linhas).toHaveLength(3);
    const primeira = textoDe(w, daCarteira('painel-seguro'));
    expect(primeira).toContain('Auto');
    expect(primeira).toContain('Em renovação');
    expect(primeira).toContain('vence em 18 dias');

    const titulo = w.get(daCarteira('painel-titulo'));
    expect(titulo.text()).toBe('Seguros');
    expect(titulo.attributes('aria-expanded')).toBe('true');
    await titulo.trigger('click');
    expect(titulo.attributes('aria-expanded')).toBe('false');
    expect(linhas[0].isVisible()).toBe(false);
  });

  it('a linha abre a gaveta por cima da conversa; o PDF e os links funcionam', async () => {
    const w = await abrirPainel();

    await w.get(daCarteira('painel-pdf')).trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Abrindo o PDF do seguro Auto');

    await w.get(daCarteira('painel-guardar-de-fora')).trigger('click');
    expect(useAlert).toHaveBeenLastCalledWith(
      'Abrindo o passo de guardar o seguro de outra corretora'
    );

    await w.get(daCarteira('painel-ver-ficha')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: COM_TRES_SEGUROS },
    });

    await w
      .get(`${daCarteira('painel-seguro')} button[aria-label^="Abrir"]`)
      .trigger('click');
    await assentar();
    expect(w.get(daCarteira('gaveta-acao')).text()).toBe('Abrir a renovação');
  });

  it('sem seguro: a frase e o link de guardar o de outra corretora', async () => {
    const w = await abrirPainel('?demo-carteira=vazio');

    expect(w.get(daCarteira('painel-vazio')).text()).toBe(
      'Nenhum seguro com você.'
    );
    expect(w.find(daCarteira('painel-guardar-de-fora')).exists()).toBe(true);
    expect(w.find(daCarteira('painel-ver-ficha')).exists()).toBe(false);
  });

  it('carregando e erro', async () => {
    const carregando = await abrirPainel('?demo-carteira=carregando');
    expect(carregando.find(daCarteira('painel-carregando')).exists()).toBe(
      true
    );
    carregando.unmount();

    const comErro = await abrirPainel('?demo-carteira=erro');
    expect(comErro.get(daCarteira('painel-erro')).text()).toContain(
      'Não consegui mostrar os seguros. Tente de novo.'
    );
  });
});

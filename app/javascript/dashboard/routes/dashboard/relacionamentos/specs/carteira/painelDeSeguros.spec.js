import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { useAlert } from 'dashboard/composables';
import PainelDeSeguros from '../../components/carteira/PainelDeSeguros.vue';
import { abrirPdf } from '../../carteira/abrirPdf';
import { gavetaDoSeguroAberta } from '../../carteira/segurosNoPainel';
import { daCarteira, erroHttp, textoDe } from './apoio';

// Os seguros de quem está na conversa, no painel do contato (#2897), com o
// texto de verdade em pt_BR e lendo do servidor (o cliente de API é de
// mentira): as linhas, o tom de quem vence logo, a pessoa sem seguro, o erro,
// "Ver PDF", a gaveta por cima da conversa e os caminhos para a ficha. Quem
// decide se a peça é montada é o painel (painelForaDaCarteira.spec.js e
// painelNaConversa.spec.js).
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    daPessoa: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
    linkDoPdf: vi.fn(),
  },
}));
vi.mock('../../carteira/abrirPdf', () => ({ abrirPdf: vi.fn() }));
vi.mock('vue-router', () => {
  const roteador = { push: vi.fn() };
  return { useRouter: () => roteador, useRoute: () => ({ query: {} }) };
});

withFullI18n('pt_BR');

const roteador = useRouter();

const PESSOA = 23;

// Um seguro como o servidor manda: datas sem hora, selo e dias já prontos.
const doServidor = (id, mais = {}) => ({
  id,
  pessoaId: PESSOA,
  pessoa: { id: PESSOA, name: 'Ana Albuquerino', phone_number: null },
  segurado: {
    tipo: 'pessoa',
    id: PESSOA,
    nome: 'Ana Albuquerino',
    documento: null,
  },
  tipo: 'auto',
  ramoOriginal: null,
  seguradora: 'Seguradora Atlântica',
  numero: `AT-00045${id}`,
  valor: 2760,
  bem: '',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'ativo',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: 1790000000 },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
  ...mais,
});

const VENCE_LOGO = doServidor(7);
const VENCE_LONGE = doServidor(8, {
  tipo: 'residencial',
  seguradora: 'Horizonte Seguros',
  termina: '2027-05-31',
  dias: 200,
  temPdf: false,
});
const VENCIDO = doServidor(9, {
  tipo: 'vida',
  termina: '2026-11-09',
  selo: 'vencido',
  dias: -3,
  temPdf: false,
});

const servidorManda = (...seguros) =>
  SegurosAPI.daPessoa.mockResolvedValue({ data: seguros });

let aberta;
const abrir = async (props = {}) => {
  aberta = mount(PainelDeSeguros, {
    attachTo: document.body,
    props: { contactId: PESSOA, ...props },
    global: { stubs: { transition: true } },
  });
  await flushPromises();
  return aberta;
};

const bloco = w => w.find(daCarteira('painel-seguros'));
const linhas = w => w.findAll(daCarteira('painel-seguro'));
const apolices = w =>
  linhas(w).map(item => Number(item.attributes('data-apolice')));
const linha = (w, id) =>
  w.get(`${daCarteira('painel-seguro')}[data-apolice="${id}"]`);
const clicar = async (alvo, seletor) => {
  await alvo.get(seletor).trigger('click');
  await flushPromises();
};
const abrirGaveta = async (w, seguro) => {
  SegurosAPI.seguro.mockResolvedValue({ data: seguro });
  SegurosAPI.historia.mockResolvedValue({ data: [] });
  await clicar(linha(w, seguro.id), 'button');
};

beforeEach(() => {
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
  aberta?.unmount();
  aberta = null;
});

describe('os seguros de quem está na conversa', () => {
  it('lê os seguros da pessoa da conversa e mostra na ordem que o servidor mandou', async () => {
    servidorManda(VENCIDO, VENCE_LOGO, VENCE_LONGE);

    const w = await abrir();

    expect(SegurosAPI.daPessoa).toHaveBeenCalledWith(PESSOA);
    expect(bloco(w).get('h3').text()).toBe('Seguros');
    expect(apolices(w)).toEqual([VENCIDO.id, VENCE_LOGO.id, VENCE_LONGE.id]);
  });

  it('cada linha diz o tipo, o selo, a seguradora e quando vence, sem o número da apólice', async () => {
    servidorManda(VENCE_LOGO);

    const w = await abrir();
    const primeira = linha(w, VENCE_LOGO.id);

    expect(primeira.get('button').text()).toBe('Auto');
    expect(primeira.get(daCarteira('selo')).text()).toBe('Ativo');
    expect(primeira.text()).toContain('Seguradora Atlântica');
    expect(textoDe(primeira, daCarteira('painel-quando'))).toBe(
      'Vence em 17 dias · 29/11/2026'
    );
    expect(primeira.text()).not.toContain(VENCE_LOGO.numero);
  });

  it('o seguro que vence em até 30 dias chama atenção em âmbar, no selo e na frase', async () => {
    servidorManda(VENCE_LOGO);

    const w = await abrir();
    const primeira = linha(w, VENCE_LOGO.id);

    expect(primeira.attributes('data-tom')).toBe('ambar');
    expect(primeira.get(daCarteira('selo')).attributes('data-selo')).toBe(
      'ambar'
    );
    expect(primeira.get(daCarteira('painel-quando')).classes()).toContain(
      'text-n-amber-11'
    );
  });

  it('o vencido fica em vermelho e o que vence longe não chama atenção', async () => {
    servidorManda(VENCIDO, VENCE_LONGE);

    const w = await abrir();
    const vencido = linha(w, VENCIDO.id);
    const longe = linha(w, VENCE_LONGE.id);

    expect(vencido.get(daCarteira('selo')).text()).toBe('Vencido');
    expect(textoDe(vencido, daCarteira('painel-quando'))).toBe(
      'Venceu há 3 dias'
    );
    expect(vencido.get(daCarteira('painel-quando')).classes()).toContain(
      'text-n-ruby-11'
    );
    expect(longe.attributes('data-tom')).toBe('verde');
    expect(textoDe(longe, daCarteira('painel-quando'))).toBe(
      'Vence em 31/05/2027'
    );
    expect(longe.get(daCarteira('painel-quando')).classes()).toContain(
      'text-n-slate-11'
    );
  });

  it('nenhum botão fica desligado', async () => {
    servidorManda(VENCIDO, VENCE_LOGO, VENCE_LONGE);

    const w = await abrir();

    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });
});

describe('quando não há o que mostrar', () => {
  it('pessoa sem seguro: a peça não desenha nada, nem título nem frase', async () => {
    servidorManda();

    const w = await abrir();

    expect(SegurosAPI.daPessoa).toHaveBeenCalledWith(PESSOA);
    expect(bloco(w).exists()).toBe(false);
    expect(w.text()).toBe('');
  });

  it('enquanto a leitura não chega, nada é desenhado (o painel não pisca)', async () => {
    SegurosAPI.daPessoa.mockReturnValue(new Promise(() => {}));

    const w = await abrir();

    expect(bloco(w).exists()).toBe(false);
    expect(w.text()).toBe('');
  });

  it('conversa sem contato: não pergunta nada ao servidor', async () => {
    const w = await abrir({ contactId: null });

    expect(SegurosAPI.daPessoa).not.toHaveBeenCalled();
    expect(bloco(w).exists()).toBe(false);
  });

  it.each([
    [404, 'a conta não tem a carteira'],
    [401, 'quem atende não pode ver a pessoa'],
    [403, 'quem atende não pode ver a pessoa'],
  ])('com %i (%s) a peça some, sem erro na tela', async status => {
    SegurosAPI.daPessoa.mockRejectedValue(erroHttp(status));

    const w = await abrir();

    expect(bloco(w).exists()).toBe(false);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('se a leitura falha, o bloco diz que não deu e tenta de novo', async () => {
    SegurosAPI.daPessoa
      .mockRejectedValueOnce(erroHttp(500))
      .mockResolvedValue({ data: [VENCE_LOGO] });
    const w = await abrir();

    expect(bloco(w).get('h3').text()).toBe('Seguros');
    expect(bloco(w).text()).toContain(
      'Não deu para carregar esta parte agora.'
    );
    await clicar(w, '[data-test-id="erro-da-parte"] button');

    expect(apolices(w)).toEqual([VENCE_LOGO.id]);
  });
});

describe('"Ver PDF" direto da linha', () => {
  it('só aparece em quem tem o PDF guardado', async () => {
    servidorManda(VENCE_LOGO, VENCE_LONGE);

    const w = await abrir();

    const verPdf = linha(w, VENCE_LOGO.id).get(daCarteira('painel-pdf'));

    expect(verPdf.text()).toBe('Ver PDF');
    expect(verPdf.attributes('aria-label')).toBe('Ver o PDF do seguro Auto');
    expect(
      linha(w, VENCE_LONGE.id).find(daCarteira('painel-pdf')).exists()
    ).toBe(false);
  });

  it('pede o link na hora e abre, sem abrir a gaveta', async () => {
    servidorManda(VENCE_LOGO);
    SegurosAPI.linkDoPdf.mockResolvedValue({ data: { url: 'about:blank' } });
    const w = await abrir();

    await clicar(w, daCarteira('painel-pdf'));

    expect(SegurosAPI.linkDoPdf).toHaveBeenCalledWith(VENCE_LOGO.id);
    expect(abrirPdf).toHaveBeenCalledTimes(1);
    expect(useAlert).not.toHaveBeenCalled();
    expect(SegurosAPI.seguro).not.toHaveBeenCalled();
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });

  it('se o PDF não está mais lá, avisa e relê os seguros', async () => {
    servidorManda(VENCE_LOGO);
    SegurosAPI.linkDoPdf.mockRejectedValue(erroHttp(422, { error: 'sem_pdf' }));
    const w = await abrir();

    await clicar(w, daCarteira('painel-pdf'));

    expect(useAlert).toHaveBeenCalledWith(
      'Este seguro não tem mais PDF guardado. Atualizei a tela.'
    );
    expect(SegurosAPI.daPessoa).toHaveBeenCalledTimes(2);
  });
});

describe('a gaveta do seguro por cima da conversa', () => {
  it('clicar na linha abre o seguro sem trocar de endereço', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();
    expect(gavetaDoSeguroAberta()).toBe(false);

    await abrirGaveta(w, VENCE_LOGO);

    expect(SegurosAPI.seguro).toHaveBeenCalledWith(VENCE_LOGO.id);
    expect(textoDe(w, '[data-view-title]')).toBe('Auto · Seguradora Atlântica');
    expect(roteador.push).not.toHaveBeenCalled();
    // É por esta marca que o painel sabe que não deve fechar "ao clicar fora".
    expect(gavetaDoSeguroAberta()).toBe(true);
  });

  it('é leitura: tem "Ver PDF", sem Corrigir nem os três pontinhos', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();

    await abrirGaveta(w, VENCE_LOGO);

    expect(
      w.find(`${daCarteira('gaveta-acao')}[data-acao="VER_PDF"]`).exists()
    ).toBe(true);
    expect(w.find(daCarteira('corrigir')).exists()).toBe(false);
    expect(w.find(daCarteira('mais-do-seguro')).exists()).toBe(false);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });

  it('fechar a gaveta volta ao painel', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();
    await abrirGaveta(w, VENCE_LOGO);

    await clicar(w, '[role="dialog"] header button');

    expect(w.find('[role="dialog"]').exists()).toBe(false);
    expect(gavetaDoSeguroAberta()).toBe(false);
    expect(apolices(w)).toEqual([VENCE_LOGO.id]);
  });

  it('o nome do segurado leva à ficha dele, já com este seguro aberto', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();
    await abrirGaveta(w, VENCE_LOGO);

    await clicar(w, daCarteira('abrir-segurado'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: PESSOA },
      query: { apolice: String(VENCE_LOGO.id) },
    });
  });

  it('quando o segurado é uma empresa, leva à ficha da empresa', async () => {
    const daEmpresa = doServidor(11, {
      tipo: 'empresarial',
      segurado: {
        tipo: 'empresa',
        id: 5,
        nome: 'Oficina Exemplo',
        documento: null,
      },
    });
    servidorManda(daEmpresa);
    const w = await abrir();
    await abrirGaveta(w, daEmpresa);

    await clicar(w, daCarteira('abrir-segurado'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_empresa',
      params: { companyId: 5 },
      query: { apolice: '11' },
    });
  });
});

describe('o caminho para a ficha e o resto da lista', () => {
  it('"Ver na ficha" leva à ficha da pessoa da conversa', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();

    await clicar(w, daCarteira('painel-ver-ficha'));

    expect(textoDe(w, daCarteira('painel-ver-ficha'))).toBe('Ver na ficha');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: PESSOA },
    });
  });

  it('até três seguros aparecem todos, sem "Ver os outros"', async () => {
    servidorManda(VENCIDO, VENCE_LOGO, VENCE_LONGE);

    const w = await abrir();

    expect(linhas(w)).toHaveLength(3);
    expect(w.find(daCarteira('painel-ver-outros')).exists()).toBe(false);
  });

  it('com mais de três mostra os três primeiros; o resto abre e recolhe ali mesmo', async () => {
    servidorManda(
      VENCIDO,
      VENCE_LOGO,
      VENCE_LONGE,
      doServidor(12),
      doServidor(13)
    );
    const w = await abrir();
    const verOutros = () => w.get(daCarteira('painel-ver-outros'));

    expect(apolices(w)).toEqual([VENCIDO.id, VENCE_LOGO.id, VENCE_LONGE.id]);
    expect(verOutros().text()).toBe('Ver os outros 2 seguros');
    expect(verOutros().attributes('aria-expanded')).toBe('false');

    await clicar(w, daCarteira('painel-ver-outros'));
    expect(linhas(w)).toHaveLength(5);
    expect(verOutros().text()).toBe('Mostrar menos');
    expect(verOutros().attributes('aria-expanded')).toBe('true');

    await clicar(w, daCarteira('painel-ver-outros'));
    expect(linhas(w)).toHaveLength(3);
  });

  it('com um só a mais, a frase fala no singular', async () => {
    servidorManda(VENCIDO, VENCE_LOGO, VENCE_LONGE, doServidor(12));

    const w = await abrir();

    expect(textoDe(w, daCarteira('painel-ver-outros'))).toBe(
      'Ver o outro seguro'
    );
  });
});

describe('ao trocar de conversa', () => {
  it('lê os seguros da outra pessoa, fecha a gaveta e não mostra os da anterior enquanto espera', async () => {
    servidorManda(VENCE_LOGO);
    const w = await abrir();
    await abrirGaveta(w, VENCE_LOGO);
    SegurosAPI.daPessoa.mockReturnValue(new Promise(() => {}));

    await w.setProps({ contactId: 48 });
    await flushPromises();

    expect(SegurosAPI.daPessoa).toHaveBeenLastCalledWith(48);
    expect(w.find('[role="dialog"]').exists()).toBe(false);
    expect(bloco(w).exists()).toBe(false);
  });
});

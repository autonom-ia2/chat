import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { useAlert } from 'dashboard/composables';
import SegurosDaFicha from '../../components/carteira/SegurosDaFicha.vue';
import { abrirPdf } from '../../carteira/abrirPdf';
import { DO_RODAPE } from '../../carteira/rodapeDoSeguro';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  erroHttp,
  textoDe,
} from './apoio';

// O bloco Seguros das fichas da pessoa e da empresa (#2897), com o texto de
// verdade em pt_BR: as linhas em ordem de urgência, vazio, carregando, erro e
// escondido, o PDF direto da linha e a gaveta pelo endereço. Na demonstração lê
// a carteira fictícia; sem ela, o servidor (o cliente de API é de mentira).
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
    daEmpresa: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
    linkDoPdf: vi.fn(),
  },
}));
vi.mock('../../carteira/abrirPdf', () => ({ abrirPdf: vi.fn() }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relacionamentos_pessoa' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();

const PESSOA_DAS_JORNADAS = 23;
const COM_PDF = 1;
const SEM_PDF = 2;

// Um seguro como o servidor manda (datas sem hora, selo e dias prontos).
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
  ramoOriginal: null,
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
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
};

let aberta;
const abrir = async ({ demo = 'cheio', query = {}, ...props } = {}) => {
  rota.query = query;
  aberta = mount(SegurosDaFicha, {
    attachTo: document.body,
    props: {
      donoId: PESSOA_DAS_JORNADAS,
      demo,
      podeEditar: true,
      ...props,
    },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};

const seguros = w => w.findAll(daCarteira('seguro'));
const apolices = w =>
  seguros(w).map(seguro => Number(seguro.attributes('data-apolice')));
const linha = (w, id) => w.get(`${daCarteira('seguro')}[data-apolice="${id}"]`);
const clicar = async (alvo, seletor) => {
  await alvo.get(seletor).trigger('click');
  await assentar();
};

// Uma empresa da carteira fictícia que é o segurado de algum seguro.
const carteira = { empresa: null };
beforeAll(async () => {
  await carregarDemonstracao();
  const fonte = carteiraFonte({ demo: 'cheio', atraso: 0 });
  const paginas = await Promise.all(
    [1, 2].map(pagina =>
      fonte.listar({ filtros: { tipo: 'empresarial' }, pagina })
    )
  );
  carteira.empresa = paginas
    .flatMap(pagina => pagina.itens)
    .find(seguro => seguro.segurado.tipo === 'empresa').segurado;
}, 60000);
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

describe('o bloco Seguros da ficha da pessoa', () => {
  it('mostra os seguros dela em ordem de urgência, com a contagem no título', async () => {
    const w = await abrir();

    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros (3)');
    expect(apolices(w)).toEqual([1, 2, 3]);
  });

  it('cada linha diz o tipo, o selo, a seguradora com o número e quando vence', async () => {
    const w = await abrir();
    const primeira = linha(w, COM_PDF);

    expect(primeira.get('button').text()).toBe('Auto');
    expect(primeira.get(daCarteira('selo')).text()).toBe('Ativo');
    expect(primeira.text()).toContain('Seguradora Atlântica · nº AT-000451');
    expect(primeira.text()).toContain('Vence em 18 dias · ');
    const numero = primeira.get(daCarteira('numero-da-apolice'));
    expect(numero.text()).toBe('nº AT-000451');
    expect(numero.classes()).toContain('whitespace-nowrap');
  });

  it('quem tem PDF mostra "Ver PDF"; quem não tem oferece guardar', async () => {
    const w = await abrir();

    expect(textoDe(linha(w, COM_PDF), daCarteira('seguro-pdf'))).toBe(
      'Ver PDF'
    );
    expect(
      linha(w, COM_PDF).find(daCarteira('seguro-guardar-pdf')).exists()
    ).toBe(false);
    expect(textoDe(linha(w, SEM_PDF), daCarteira('seguro-guardar-pdf'))).toBe(
      'Guardar PDF'
    );
  });

  it('quem só pode ver a pessoa não vê "Guardar PDF", nem botão desligado', async () => {
    const w = await abrir({ podeEditar: false });

    expect(w.find(daCarteira('seguro-guardar-pdf')).exists()).toBe(false);
    expect(w.find(daCarteira('seguro-pdf')).exists()).toBe(true);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });

  it('sem seguro, é só uma frase e o título não conta', async () => {
    const w = await abrir({ demo: 'sem-seguros' });

    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros');
    expect(textoDe(w, daCarteira('seguros-vazio'))).toBe(
      'Nenhum seguro ainda.'
    );
  });

  it('enquanto carrega mostra o esqueleto, sem "(0)" no título', async () => {
    const w = await abrir({ demo: 'carregando' });

    expect(w.find(daCarteira('seguros-carregando')).exists()).toBe(true);
    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros');
  });
});

describe('o bloco Seguros da ficha da empresa', () => {
  it('mostra os seguros em que a empresa é o segurado', async () => {
    const w = await abrir({ donoId: carteira.empresa.id, daEmpresa: true });

    expect(w.find(daCarteira('seguros')).exists()).toBe(false);
    expect(w.get(`${daCarteira('seguros-da-empresa')} h2`).text()).toContain(
      'Seguros da empresa ('
    );
    expect(seguros(w).length).toBeGreaterThan(0);
    expect(seguros(w)[0].get('button').text()).toBe('Empresarial');
  });

  it('lê do servidor pela leitura da empresa', async () => {
    SegurosAPI.daEmpresa.mockResolvedValue({ data: [DO_SERVIDOR] });

    const w = await abrir({ demo: null, donoId: 9, daEmpresa: true });

    expect(SegurosAPI.daEmpresa).toHaveBeenCalledWith(9);
    expect(SegurosAPI.daPessoa).not.toHaveBeenCalled();
    expect(apolices(w)).toEqual([DO_SERVIDOR.id]);
  });
});

describe('o PDF direto da linha', () => {
  it('"Ver PDF" pede o link na hora e abre', async () => {
    const w = await abrir();

    await clicar(linha(w, COM_PDF), daCarteira('seguro-pdf'));

    expect(abrirPdf).toHaveBeenCalledTimes(1);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('se o PDF não está mais lá, avisa e relê os seguros', async () => {
    SegurosAPI.daPessoa.mockResolvedValue({ data: [DO_SERVIDOR] });
    SegurosAPI.linkDoPdf.mockRejectedValue(erroHttp(422, { error: 'sem_pdf' }));
    const w = await abrir({ demo: null });

    await clicar(w, daCarteira('seguro-pdf'));

    expect(SegurosAPI.linkDoPdf).toHaveBeenCalledWith(DO_SERVIDOR.id);
    expect(useAlert).toHaveBeenCalledWith(
      'Este seguro não tem mais PDF guardado. Atualizei a tela.'
    );
    expect(SegurosAPI.daPessoa).toHaveBeenCalledTimes(2);
  });

  it('"Guardar PDF" guarda em um passo e a linha passa a mostrar "Ver PDF"', async () => {
    const w = await abrir();

    await clicar(linha(w, SEM_PDF), daCarteira('seguro-guardar-pdf'));
    expect(textoDe(w, '[data-relacionamentos="titulo-do-dialogo"]')).toBe(
      'Guardar o PDF do seguro Residencial'
    );
    await clicar(w, daCarteira('usar-exemplo'));

    expect(useAlert).toHaveBeenCalledWith('PDF guardado.');
    expect(linha(w, SEM_PDF).find(daCarteira('seguro-pdf')).exists()).toBe(
      true
    );
    expect(w.find(daCarteira('seguros-carregando')).exists()).toBe(false);
  });
});

describe('a gaveta do seguro pela ficha', () => {
  it('clicar na linha põe o seguro no endereço e abre a gaveta', async () => {
    const w = await abrir();

    await clicar(linha(w, SEM_PDF), 'button');

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { apolice: String(SEM_PDF) },
    });
    expect(textoDe(w, '[data-view-title]')).toBe(
      'Residencial · Horizonte Seguros'
    );
  });

  it('o que muda na gaveta muda o bloco, sem piscar o esqueleto', async () => {
    const w = await abrir({ query: { apolice: String(COM_PDF) } });

    await w
      .get(`${daCarteira('mais-do-seguro')} [aria-haspopup="menu"]`)
      .trigger('click');
    await clicar(
      w,
      `[role="menuitem"][data-acao="${DO_RODAPE.MARCAR_CANCELADO}"]`
    );

    // O cancelado vai para o fim da fila.
    expect(apolices(w)).toEqual([2, 3, 1]);
    expect(linha(w, COM_PDF).get(daCarteira('selo')).text()).toBe('Cancelado');
    expect(linha(w, COM_PDF).text()).toContain('Cancelado em ');
  });

  it('fechar a gaveta tira o seguro do endereço', async () => {
    const w = await abrir({ query: { apolice: String(COM_PDF) } });

    await clicar(w, '[role="dialog"] header button');

    expect(roteador.push).toHaveBeenLastCalledWith({ query: {} });
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });

  it('o nome do segurado na gaveta avisa a ficha', async () => {
    const w = await abrir({ query: { apolice: String(COM_PDF) } });

    await w.get(daCarteira('abrir-segurado')).trigger('click');

    expect(w.emitted('abrirSegurado')).toHaveLength(1);
    expect(w.emitted('abrirSegurado')[0][0]).toMatchObject({
      tipo: 'pessoa',
      id: PESSOA_DAS_JORNADAS,
    });
  });
});

describe('fora da demonstração (o servidor)', () => {
  it('lê os seguros da pessoa e escreve o que o servidor mandou', async () => {
    SegurosAPI.daPessoa.mockResolvedValue({ data: [DO_SERVIDOR] });

    const w = await abrir({ demo: null });

    expect(SegurosAPI.daPessoa).toHaveBeenCalledWith(PESSOA_DAS_JORNADAS);
    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros (1)');
    expect(seguros(w)[0].text()).toContain('Vence em 17 dias · 29/11/2026');
  });

  it('seguro sem número mostra só a seguradora', async () => {
    SegurosAPI.daPessoa.mockResolvedValue({
      data: [{ ...DO_SERVIDOR, numero: null }],
    });

    const w = await abrir({ demo: null });

    expect(seguros(w)[0].text()).toContain('Seguradora Atlântica');
    expect(w.find(daCarteira('numero-da-apolice')).exists()).toBe(false);
    expect(seguros(w)[0].text()).not.toContain('nº');
  });

  it('trocar de pessoa lê os seguros da outra', async () => {
    SegurosAPI.daPessoa.mockResolvedValue({ data: [DO_SERVIDOR] });
    const w = await abrir({ demo: null });

    await w.setProps({ donoId: 48 });
    await assentar();

    expect(SegurosAPI.daPessoa).toHaveBeenLastCalledWith(48);
  });

  it('no erro, o bloco diz a frase e tenta de novo; o resto da ficha continua', async () => {
    SegurosAPI.daPessoa
      .mockRejectedValueOnce(erroHttp(500))
      .mockResolvedValue({ data: [DO_SERVIDOR] });
    const w = await abrir({ demo: null });

    expect(textoDe(w, daCarteira('seguros-erro'))).toContain(
      'Não consegui mostrar os seguros. Tente de novo.'
    );
    await clicar(w, `${daCarteira('seguros-erro')} button`);

    expect(apolices(w)).toEqual([DO_SERVIDOR.id]);
  });

  it.each([
    [404, 'a conta não tem a carteira'],
    [401, 'quem olha não pode ver a pessoa'],
    [403, 'quem olha não pode ver a pessoa'],
  ])('com %i (%s) o bloco some, sem erro na tela', async status => {
    SegurosAPI.daPessoa.mockRejectedValue(erroHttp(status));

    const w = await abrir({ demo: null });

    expect(w.find(daCarteira('seguros')).exists()).toBe(false);
    expect(w.find(daCarteira('seguros-erro')).exists()).toBe(false);
    expect(useAlert).not.toHaveBeenCalled();
  });
});

import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FidelidadePage from '../pages/FidelidadePage.vue';
import FidelidadeDaFicha from '../../relacionamentos/components/ficha/FidelidadeDaFicha.vue';
import { cupomParaOServidor } from '../fonte';
import * as fonte from '../fonte';
import { cupomNovo, programaNovo } from '../regras';
import {
  GRUPO_DO_CUPOM,
  RECEITA_DO_CUPOM,
  receitaDaFidelidade,
  requerDaReceita,
} from '../../automacoes/livre/passosNovos/fidelidadeNaAutomacao';
import {
  fraseDoPassoNovo,
  linhaDoEnsaioComMotor,
} from '../../automacoes/livre/passosNovos/frasesDosNovos';
import {
  novoPassoNovo,
  passoNovoPronto,
} from '../../automacoes/livre/passosNovos/passosNovos';

// #3100 — os cupons ligados ao servidor: a aba Cupons (relatório, conferir,
// marcar como usado, mandar, pausar), marcar como usado pela ficha e o passo
// "Mandar cupom" na Automação livre, com o texto real em pt_BR.
withFullI18n('pt_BR');

const alertas = vi.hoisted(() => []);
const rotas = vi.hoisted(() => ({ query: {}, pushes: [] }));
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => true,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: rotas.query }),
  useRouter: () => ({
    push: destino => rotas.pushes.push(destino),
    replace: () => {},
  }),
}));
vi.mock('../fonte', async original => ({
  ...(await original()),
  lerPrograma: vi.fn(),
  lerResumo: vi.fn(),
  lerCupons: vi.fn(),
  ligarCupom: vi.fn(),
  conferirCupom: vi.fn(),
  usarCodigo: vi.fn(),
  fidelidadeDaPessoa: vi.fn(),
}));

const AGORA = Date.UTC(2026, 10, 23, 15);
const S = AGORA / 1000;
const PROGRAMA = { ...programaNovo(), premio: 'Lavagem grátis', ligado: true };
const CUPOM = {
  id: 3,
  nome: 'Volta de dezembro',
  oferta: { tipo: 'porcentagem', valor: 10 },
  moeda: 'BRL',
  prefixo: 'VOLTA',
  validade_dias: 15,
  ligado: true,
  mandados: 0,
  usados: 0,
  vendas: [],
};
const VALE = {
  id: 9,
  codigo: 'VOLTA-7KD2',
  estado: 'valido',
  oferta: { tipo: 'porcentagem', valor: 10 },
  moeda: 'BRL',
  cliente: 'Maria Souza',
  vale_ate: S + 86400 * 7,
  usado_em: null,
};
const stubs = {
  Dialog: {
    template:
      '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
  TeleportWithDirection: { template: '<div><slot /></div>' },
};
const sel = nome => `[data-fidelidade="${nome}"]`;

beforeEach(() => {
  alertas.length = 0;
  rotas.query = {};
  rotas.pushes.length = 0;
});

describe('cupomParaOServidor', () => {
  it('manda só o que o servidor aceita, com o nome e o presente sem espaços nas pontas', () => {
    const cupom = {
      ...cupomNovo(),
      nome: '  Volta  ',
      prefixo: 'VOLTA',
      oferta: { tipo: 'presente', valor: null, texto: ' Uma lavagem ' },
    };
    expect(cupomParaOServidor(cupom)).toEqual({
      nome: 'Volta',
      oferta: { tipo: 'presente', valor: null, texto: 'Uma lavagem' },
      prefixo: 'VOLTA',
      validade_dias: 15,
    });
  });
});

describe('FidelidadePage, aba Cupons', () => {
  const montar = async () => {
    rotas.query = { aba: 'cupons' };
    fonte.lerPrograma.mockResolvedValue(PROGRAMA);
    fonte.lerResumo.mockResolvedValue({ com_saldo: 0, perto: 0 });
    fonte.lerCupons.mockResolvedValue([CUPOM]);
    const pagina = mount(FidelidadePage, { global: { stubs } });
    await flushPromises();
    return pagina;
  };

  it('abre na aba Cupons com o relatório do servidor', async () => {
    const pagina = await montar();

    expect(fonte.lerCupons).toHaveBeenCalledTimes(1);
    expect(pagina.find(sel('cupom-3')).exists()).toBe(true);
    expect(pagina.find(sel('conferir')).exists()).toBe(true);
  });

  it('conferir pergunta ao servidor e "Marcar como usado" marca o código que voltou', async () => {
    fonte.conferirCupom.mockResolvedValue(VALE);
    fonte.usarCodigo.mockResolvedValue({ codigo: VALE, ja_estava: false });
    const pagina = await montar();

    await pagina.find(sel('codigo')).setValue(' volta-7kd2 ');
    await pagina.find(sel('botao-conferir')).trigger('submit');
    await flushPromises();
    expect(fonte.conferirCupom).toHaveBeenCalledWith('VOLTA-7KD2');
    expect(pagina.find(sel('resultado')).attributes('data-estado')).toBe(
      'valido'
    );

    await pagina.find(sel('usar')).trigger('click');
    await flushPromises();
    expect(fonte.usarCodigo).toHaveBeenCalledWith(9);
    expect(pagina.find(sel('usado-ok')).text()).toContain(
      'Dê 10% de desconto ao cliente.'
    );
  });

  it('código vencido no servidor diz que não dá mais para usar', async () => {
    fonte.conferirCupom.mockResolvedValue(VALE);
    fonte.usarCodigo.mockRejectedValue({
      response: { status: 422, data: { error: 'vencido' } },
    });
    const pagina = await montar();

    await pagina.find(sel('codigo')).setValue('VOLTA-7KD2');
    await pagina.find(sel('botao-conferir')).trigger('submit');
    await flushPromises();
    await pagina.find(sel('usar')).trigger('click');
    await flushPromises();

    expect(alertas).toEqual(['Este cupom venceu. Não dá mais para usar.']);
    expect(pagina.find(sel('usado-ok')).exists()).toBe(false);
  });

  it('"Mandar este cupom" abre a automação pronta com o cupom', async () => {
    const pagina = await montar();

    await pagina.find(sel('mandar-cupom')).trigger('click');

    expect(rotas.pushes.at(-1)).toEqual({
      name: 'automacoes_livre_nova',
      query: { receita: RECEITA_DO_CUPOM, cupom: 3 },
    });
  });

  it('pausar grava e troca o cupom pelo que o servidor devolveu', async () => {
    fonte.ligarCupom.mockResolvedValue({ ...CUPOM, ligado: false });
    const pagina = await montar();

    await pagina.find(sel('pausar-cupom')).trigger('click');
    await flushPromises();

    expect(fonte.ligarCupom).toHaveBeenCalledWith(3, false);
    expect(pagina.find(sel('ligar-cupom')).exists()).toBe(true);
    expect(alertas).toEqual([
      'Pronto, o cupom está pausado. Quem já recebeu ainda pode usar.',
    ]);
  });
});

describe('FidelidadeDaFicha, marcar cupom como usado', () => {
  const DA_PESSOA = {
    programa: PROGRAMA,
    tem: 3,
    vencem: null,
    historico: [],
    historico_total: 0,
    cupons: [VALE],
  };
  const montar = async podeEditar => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(DA_PESSOA);
    const peca = mount(FidelidadeDaFicha, {
      props: { donoId: 7, nome: 'Maria', agora: AGORA, podeEditar },
      global: { stubs },
    });
    await flushPromises();
    return peca;
  };

  it('só quem pode editar o contato vê "Marcar como usado"', async () => {
    expect((await montar(false)).find(sel('usar-cupom')).exists()).toBe(false);
    expect((await montar(true)).find(sel('usar-cupom')).exists()).toBe(true);
  });

  it('confirmar marca o código e o bloco mostra o cupom usado', async () => {
    fonte.usarCodigo.mockResolvedValue({
      codigo: { ...VALE, estado: 'usado', usado_em: S },
      ja_estava: false,
    });
    const peca = await montar(true);

    await peca.find(sel('usar-cupom')).trigger('click');
    await peca.findAll('[data-confirmar]').at(0).trigger('click');
    await flushPromises();

    expect(fonte.usarCodigo).toHaveBeenCalledWith(9);
    expect(peca.find('[data-cupom="usado"]').exists()).toBe(true);
    expect(alertas).toEqual([
      'Pronto, o cupom VOLTA-7KD2 foi marcado como usado.',
    ]);
  });
});

describe('o passo "Mandar cupom" na Automação livre', () => {
  const t = (chave, valores) => {
    const partes = Object.entries(valores || {}).map(([k, v]) => `${k}=${v}`);
    return [chave, ...partes].join('|');
  };

  it('nasce com o código no texto e só fica pronto com o cupom escolhido', () => {
    const passo = novoPassoNovo('mandar_cupom', 'p1', t);

    expect(passo.texto).toContainEqual({ $valor: 'cupom.codigo' });
    expect(passoNovoPronto(passo)).toBe(false);
    expect(passoNovoPronto({ ...passo, cupom_id: 3 })).toBe(true);
    expect(
      passoNovoPronto({ ...passo, cupom_id: 3, texto: ['Sem código'] })
    ).toBe(false);
  });

  it('sem o cupom carregado, o Confira diz só "Mandar um cupom"', () => {
    expect(fraseDoPassoNovo({ tipo: 'mandar_cupom', cupom_id: 3 }, t)).toBe(
      'FIDELIDADE.AUTOMACAO.CUPOM.FRASE_SEM_CUPOM'
    );
  });

  it('o ensaio diz se o código é novo ou o mesmo, e por que nada sairia', () => {
    const no = (faria, dados = {}) => ({ tipo: 'mandar_cupom', faria, dados });

    expect(
      linhaDoEnsaioComMotor(
        no('mandar_cupom', { cupom: 'Volta', mesmo_codigo: false }),
        t
      ).destaque
    ).toBe('FIDELIDADE.AUTOMACAO.CUPOM.ENSAIO_NOVO|cupom=Volta');
    expect(
      linhaDoEnsaioComMotor(
        no('mandar_cupom', { cupom: 'Volta', mesmo_codigo: true }),
        t
      ).destaque
    ).toBe('FIDELIDADE.AUTOMACAO.CUPOM.ENSAIO_MESMO|cupom=Volta');
    [
      ['sem_cupom', 'ENSAIO_SEM_CUPOM'],
      ['cupom_pausado', 'ENSAIO_PAUSADO'],
      ['cupom_sem_contato', 'ENSAIO_SEM_CONTATO'],
      ['cupom_ja_usado', 'ENSAIO_USADO'],
      ['cupom_vencido', 'ENSAIO_VENCIDO'],
    ].forEach(([faria, chave]) =>
      expect(linhaDoEnsaioComMotor(no(faria), t).aviso).toBe(
        `FIDELIDADE.AUTOMACAO.CUPOM.${chave}`
      )
    );
  });

  it('a receita "Mandar este cupom" vai para quem parou de comprar, com o cupom', () => {
    const { receita } = receitaDaFidelidade(RECEITA_DO_CUPOM, t, null, 3);

    expect(receita.gatilho).toEqual({
      tipo: 'contato.entrou_no_grupo_de_compra',
      grupo_de_compra: GRUPO_DO_CUPOM,
    });
    expect(receita.passos).toHaveLength(1);
    expect(receita.passos[0]).toMatchObject({
      tipo: 'mandar_cupom',
      cupom_id: 3,
    });
    expect(requerDaReceita(RECEITA_DO_CUPOM)).toContain(
      'automacao_passos_novos'
    );
  });
});

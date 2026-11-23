import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FidelidadeDaFicha from '../../relacionamentos/components/ficha/FidelidadeDaFicha.vue';
import {
  fraseDoPassoNovo,
  linhaDoEnsaioComMotor,
} from '../../automacoes/livre/passosNovos/frasesDosNovos';
import { programaNovo } from '../regras';
import * as fonte from '../fonte';

// #3100 — a peça da ficha que lê o cartão da pessoa e dá o prêmio, e as frases
// do passo "Dar carimbos" na Automação livre, com o texto real em pt_BR.
withFullI18n('pt_BR');

const alertas = vi.hoisted(() => []);
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));
vi.mock('../fonte', async original => ({
  ...(await original()),
  fidelidadeDaPessoa: vi.fn(),
  movimentosDaPessoa: vi.fn(),
  darPremio: vi.fn(),
  usarCodigo: vi.fn(),
}));

const AGORA = Date.UTC(2026, 10, 23, 15);
const PROGRAMA = { ...programaNovo(), premio: 'Lavagem grátis', ligado: true };
const MOV = id => ({ id, tipo: 'compra', quantos: 1, em: AGORA / 1000 });
const DA_PESSOA = {
  programa: PROGRAMA,
  tem: 10,
  vencem: null,
  historico: [MOV(1)],
  historico_total: 3,
  cupons: [],
};
const stubs = {
  TeleportWithDirection: { template: '<div><slot /></div>' },
  Dialog: {
    template:
      '<div data-dialog><slot /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};
const sel = nome => `[data-fidelidade="${nome}"]`;

const montar = async (props = {}) => {
  const peca = mount(FidelidadeDaFicha, {
    props: { donoId: 7, nome: 'Maria', agora: AGORA, ...props },
    global: { stubs },
  });
  await flushPromises();
  return peca;
};

// O bloco tem dois diálogos (marcar cupom como usado e dar o prêmio): o do
// prêmio vem por último.
const confirmarPremio = peca =>
  peca.findAll('[data-confirmar]').at(-1).trigger('click');

beforeEach(() => {
  alertas.length = 0;
});

describe('FidelidadeDaFicha', () => {
  it('sem cartão na conta (resposta vazia) ou sem acesso, o bloco não aparece', async () => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(null);
    expect((await montar()).find(sel('da-ficha')).exists()).toBe(false);

    fonte.fidelidadeDaPessoa.mockRejectedValue({ response: { status: 403 } });
    expect((await montar()).find(sel('da-ficha')).exists()).toBe(false);
  });

  it('a leitura falhou: o cartão do bloco com "Tentar de novo", que relê', async () => {
    fonte.fidelidadeDaPessoa.mockRejectedValueOnce({
      response: { status: 500 },
    });
    const peca = await montar();
    expect(peca.find('[data-relacionamentos="falha-da-parte"]').exists()).toBe(
      true
    );

    fonte.fidelidadeDaPessoa.mockResolvedValueOnce(DA_PESSOA);
    await peca
      .find('[data-relacionamentos="falha-da-parte"] button')
      .trigger('click');
    await flushPromises();
    expect(peca.find('[data-relacionamentos="fidelidade"]').exists()).toBe(
      true
    );
  });

  it('"Dar o prêmio" só para quem pode editar o contato', async () => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(DA_PESSOA);
    expect((await montar()).find(sel('dar-premio')).exists()).toBe(false);
    expect(
      (await montar({ podeEditar: true })).find(sel('dar-premio')).exists()
    ).toBe(true);
  });

  it('confirmar o prêmio manda uma chave por toque e refaz o bloco com a resposta', async () => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(DA_PESSOA);
    fonte.darPremio.mockResolvedValue({
      fidelidade: { ...DA_PESSOA, tem: 0 },
    });
    const peca = await montar({ podeEditar: true });

    await confirmarPremio(peca);
    await flushPromises();

    const [id, chave] = fonte.darPremio.mock.calls[0];
    expect(id).toBe(7);
    expect(typeof chave).toBe('string');
    expect(chave.length).toBeGreaterThan(10);
    expect(peca.find(sel('dar-premio')).exists()).toBe(false);
    expect(alertas).toEqual(['Pronto, o prêmio de Maria ficou anotado.']);
  });

  it('sem o cartão completo no servidor, diz que ainda não dá', async () => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(DA_PESSOA);
    fonte.darPremio.mockRejectedValue({
      response: { status: 422, data: { error: 'saldo_insuficiente' } },
    });
    const peca = await montar({ podeEditar: true });

    await confirmarPremio(peca);
    await flushPromises();

    expect(alertas).toEqual([
      'O cartão ainda não está completo. Confira o saldo.',
    ]);
  });

  it('"Ver tudo" troca os 5 da ficha pela primeira página e junta as seguintes', async () => {
    fonte.fidelidadeDaPessoa.mockResolvedValue(DA_PESSOA);
    fonte.movimentosDaPessoa
      .mockResolvedValueOnce({ itens: [MOV(1), MOV(2)], total: 3, pagina: 1 })
      .mockResolvedValueOnce({ itens: [MOV(3)], total: 3, pagina: 2 });
    const peca = await montar();
    const verTudo = () =>
      peca
        .findAll('button')
        .find(botao => botao.text() === 'Ver tudo')
        .trigger('click');

    await verTudo();
    await flushPromises();
    expect(peca.findAll('[data-movimento]')).toHaveLength(2);
    await verTudo();
    await flushPromises();
    expect(peca.findAll('[data-movimento]')).toHaveLength(3);
    expect(fonte.movimentosDaPessoa.mock.calls).toEqual([
      [7, 1],
      [7, 2],
    ]);
  });
});

describe('o passo "Dar carimbos" nas frases da Automação livre', () => {
  const t = (chave, valores, plural) => {
    const partes = Object.entries(valores || {}).map(([k, v]) => `${k}=${v}`);
    return [chave, plural, ...partes].filter(Boolean).join('|');
  };
  const passo = { tipo: 'dar_carimbos', quantos: 2, motivo: 'aniversário' };

  it('o Confira diz quantos e o motivo', () => {
    expect(fraseDoPassoNovo(passo, t)).toContain('FRASE_COM_MOTIVO');
    expect(fraseDoPassoNovo({ ...passo, motivo: '' }, t)).toContain(
      'DAR.FRASE|'
    );
  });

  it('o ensaio diz com quantos ficaria, ou que completaria o cartão', () => {
    const no = ficaria => ({
      tipo: 'dar_carimbos',
      faria: 'dar_carimbos',
      dados: {
        quantos: 2,
        tem: ficaria - 2,
        ficaria,
        meta: 10,
        unidade: 'carimbos',
      },
    });
    expect(linhaDoEnsaioComMotor(no(5), t, passo).destaque).toContain(
      'ENSAIO_FICA'
    );
    expect(linhaDoEnsaioComMotor(no(10), t, passo).destaque).toContain(
      'ENSAIO_COMPLETA'
    );
  });

  it('sem cartão, pausado ou sem contato, o ensaio avisa que ninguém receberia', () => {
    [
      ['sem_cartao_fidelidade', 'ENSAIO_SEM_CARTAO'],
      ['cartao_fidelidade_pausado', 'ENSAIO_PAUSADO'],
      ['fidelidade_sem_contato', 'ENSAIO_SEM_CONTATO'],
    ].forEach(([faria, chave]) =>
      expect(
        linhaDoEnsaioComMotor({ tipo: 'dar_carimbos', faria }, t, passo).aviso
      ).toContain(chave)
    );
  });
});

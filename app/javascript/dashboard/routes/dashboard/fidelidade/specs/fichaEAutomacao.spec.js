import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import SecaoFidelidade from '../../relacionamentos/components/ficha/SecaoFidelidade.vue';
import DialogoDarPremio from '../../relacionamentos/components/ficha/DialogoDarPremio.vue';
import LivreDarCarimbos from '../../automacoes/livre/passosNovos/LivreDarCarimbos.vue';
import LivreMandarCupom from '../../automacoes/livre/passosNovos/LivreMandarCupom.vue';
import {
  VALORES_DA_FIDELIDADE,
  novoDarCarimbos,
} from '../../automacoes/livre/passosNovos/fidelidadeNaAutomacao';
import { programaNovo } from '../regras';

// #3100 — o bloco Fidelidade da ficha, o diálogo do prêmio e os dois passos da
// Automação livre, com o texto real em pt_BR.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 23, 15);
const S = AGORA / 1000;
const DIA = 86400;
const PROGRAMA = { ...programaNovo(), premio: 'Lavagem grátis' };
// Junta as linhas e os espaços repetidos do texto da tela (sem expressão
// regular). O Intl separa "R$" do número com espaço que não quebra.
const texto = wrapper =>
  wrapper
    .text()
    .replaceAll('\n', ' ')
    .replaceAll('\u00a0', ' ')
    .split(' ')
    .filter(Boolean)
    .join(' ');
const sel = nome => `[data-fidelidade="${nome}"]`;
const stubs = {
  TeleportWithDirection: { template: '<div><slot /></div>' },
  Dialog: {
    template:
      '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};

const CUPOM = {
  codigo: 'VOLTA-7KD2',
  estado: 'valido',
  oferta: { tipo: 'porcentagem', valor: 10 },
  moeda: 'BRL',
  vale_ate: S + 8 * DIA,
};

describe('SecaoFidelidade (ficha)', () => {
  const montar = (saldo, extra = {}) =>
    mount(SecaoFidelidade, {
      props: { programa: PROGRAMA, saldo, agora: AGORA, ...extra },
      global: { stubs },
    });

  it('sem nada ainda, diz como ganha o primeiro', () => {
    const secao = montar(null);
    expect(secao.find(sel('ficha-vazia')).exists()).toBe(true);
    expect(texto(secao)).toContain('Ainda não tem carimbos.');
    expect(texto(secao)).toContain('R$ 50');
  });

  it('no meio do cartão, mostra o histórico, o que vence e o cupom', async () => {
    const secao = montar(
      {
        tem: 7,
        vencem: { quantos: 2, em: S + 12 * DIA },
        historico: [
          {
            id: 1,
            tipo: 'compra',
            quantos: 2,
            em: S - DIA,
            valor: { total: 120, moeda: 'BRL' },
          },
          {
            id: 2,
            tipo: 'premio',
            quantos: -10,
            em: S - 30 * DIA,
            quem: 'Ana',
          },
        ],
        historico_total: 5,
        cupons: [CUPOM],
      },
      { podeUsarCupom: true }
    );
    expect(texto(secao)).toContain('Faltam 3 carimbos para o prêmio');
    expect(texto(secao)).toContain('2 carimbos vencem em');
    expect(texto(secao)).toContain('Recebeu 2 carimbos na compra de R$ 120');
    expect(texto(secao)).toContain('Ana deu o prêmio');
    expect(secao.find(sel('completo')).exists()).toBe(false);
    await secao.find(sel('usar-cupom')).trigger('click');
    expect(secao.emitted('usarCupom')).toBeUndefined();
    expect(texto(secao)).toContain('Marcar o cupom VOLTA-7KD2 como usado?');
    await secao.find('[data-confirmar]').trigger('click');
    expect(secao.emitted('usarCupom')[0][0].codigo).toBe('VOLTA-7KD2');
  });

  it('cartão completo: faixa verde e Dar o prêmio para quem pode', async () => {
    const secao = montar(
      { tem: 12, historico: [], cupons: [] },
      { podeDarPremio: true }
    );
    expect(texto(secao)).toContain('Cartão completo!');
    expect(texto(secao)).toContain('Pode dar o prêmio.');
    expect(secao.find(sel('sobra')).text()).toBe(
      'Ficam 2 carimbos para o próximo cartão.'
    );
    await secao.find(sel('dar-premio')).trigger('click');
    expect(secao.emitted('darPremio')).toHaveLength(1);
  });

  it('quem não pode mexer no contato vê o cartão sem o botão', () => {
    const secao = montar({ tem: 10, historico: [], cupons: [] });
    expect(secao.find(sel('dar-premio')).exists()).toBe(false);
  });

  it('a parte que falhou oferece tentar de novo', () => {
    const secao = montar(null, { falhou: true });
    expect(secao.find(sel('ficha-vazia')).exists()).toBe(false);
  });
});

describe('DialogoDarPremio', () => {
  it('diz quantos saem e quantos ficam para o próximo', async () => {
    const dialogo = mount(DialogoDarPremio, {
      props: { programa: PROGRAMA, tem: 12, nome: 'Maria' },
      global: { stubs },
    });
    expect(texto(dialogo)).toContain('Dar o prêmio para Maria?');
    expect(texto(dialogo)).toContain('Prêmio: Lavagem grátis.');
    expect(texto(dialogo)).toContain('Saem 10 carimbos do cartão.');
    expect(texto(dialogo)).toContain('Ficam 2 carimbos para o próximo cartão.');
    await dialogo.find('[data-confirmar]').trigger('click');
    expect(dialogo.emitted('confirmar')).toHaveLength(1);
  });
});

describe('passo Dar carimbos ou pontos', () => {
  it('sem cartão na conta, pede para criar', async () => {
    const passo = mount(LivreDarCarimbos, {
      props: { modelValue: novoDarCarimbos('p1'), programa: null },
    });
    expect(passo.find(sel('sem-programa')).exists()).toBe(true);
    await passo.find(`${sel('sem-programa')} button`).trigger('click');
    expect(passo.emitted('criarPrograma')).toHaveLength(1);
  });

  it('lembra que a compra já dá carimbos e mostra o exemplo', () => {
    const passo = mount(LivreDarCarimbos, {
      props: {
        modelValue: { ...novoDarCarimbos('p1'), quantos: 2 },
        programa: PROGRAMA,
      },
    });
    expect(texto(passo)).toContain('A compra já dá carimbos sozinha.');
    expect(passo.find(sel('exemplo')).text()).toContain(
      'quem tem 7 fica com 9 de 10 carimbos'
    );
  });
});

describe('passo Mandar cupom', () => {
  const CUPONS = [
    {
      id: 1,
      nome: 'Volta de dezembro',
      oferta: { tipo: 'porcentagem', valor: 10 },
      moeda: 'BRL',
      prefixo: 'VOLTA',
      validade_dias: 15,
    },
  ];
  const montar = (modelValue, cupons = CUPONS) =>
    mount(LivreMandarCupom, {
      props: {
        modelValue,
        cupons,
        catalogo: { valores: VALORES_DA_FIDELIDADE },
        atributosDo: () => [],
        agora: AGORA,
      },
    });

  it('a prévia troca o código pelo exemplo', () => {
    const passo = montar({
      id: 'p2',
      tipo: 'mandar_cupom',
      cupom_id: 1,
      texto: [
        'Seu cupom ',
        { $valor: 'cupom.codigo' },
        ' dá ',
        { $valor: 'cupom.oferta' },
        '.',
      ],
    });
    expect(passo.find(sel('previa-mensagem')).text()).toContain(
      'Seu cupom VOLTA-7KD2 dá 10% de desconto.'
    );
    expect(passo.find(sel('sem-codigo')).exists()).toBe(false);
  });

  it('sem o código no texto, avisa', () => {
    const passo = montar({
      id: 'p2',
      tipo: 'mandar_cupom',
      cupom_id: 1,
      texto: ['Oi!'],
    });
    expect(passo.find(sel('sem-codigo')).exists()).toBe(true);
  });

  it('sem cupom criado, pede para criar', () => {
    const passo = montar(
      { id: 'p2', tipo: 'mandar_cupom', cupom_id: null, texto: [] },
      []
    );
    expect(passo.find(sel('sem-cupom')).exists()).toBe(true);
  });
});

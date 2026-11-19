import { mount } from '@vue/test-utils';
import LivreLigar from '../components/LivreLigar.vue';
import { falta, motivoIncompleto, primeiroIncompleto } from '../receita';

// #2982 — o aviso de "falta completar" diz qual passo e o que falta nele. Antes
// era uma frase só, sobre o "Se", mesmo quando o incompleto era o "Fazer para
// cada" sem passo dentro: a pessoa não achava o que consertar.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores?.nome ? `${chave} [${valores.nome}]` : chave,
  }),
}));

const GATILHO = { tipo: 'card.entrou_na_etapa' };
const aviso = { id: 'p9', tipo: 'mensagem', texto: ['Oi'] };
const paraCada = cada => ({
  id: 'p1',
  tipo: 'repetir_lista',
  lista: { de: 'etapa', etapa_id: 3 },
  teto: 50,
  cada,
});
const bloco = blocoId => ({ id: 'p2', tipo: 'usar_bloco', bloco_id: blocoId });
const se = (entao, condicao = { campo: { $valor: 'x' }, op: 'vazio' }) => ({
  id: 'p3',
  tipo: 'se',
  condicao,
  entao,
});

const STUBS = {
  Button: {
    props: ['label', 'disabled'],
    template: '<button :disabled="disabled">{{ label }}</button>',
  },
  Switch: { template: '<span data-switch />' },
};
const ligar = passos =>
  mount(LivreLigar, {
    props: { receita: { gatilho: GATILHO, passos }, podeMudar: true },
    global: { mocks: { $t: chave => chave }, stubs: STUBS },
  });

describe('o que falta em cada passo', () => {
  it('"Fazer para cada" sem passo dentro', () => {
    expect(motivoIncompleto(paraCada([]))).toBe('CADA');
    expect(motivoIncompleto(paraCada([aviso]))).toBeNull();
  });

  it('passo novo que ainda não está montado', () => {
    expect(motivoIncompleto(bloco(null))).toBe('NOVO');
    expect(motivoIncompleto(bloco(7))).toBeNull();
  });

  it('"Se" sem condição ou sem passo em Então', () => {
    expect(motivoIncompleto(se([aviso], null))).toBe('SE');
    expect(motivoIncompleto(se([]))).toBe('SE');
    expect(motivoIncompleto(se([aviso]))).toBeNull();
  });

  it('"Esperar até" sem condição', () => {
    expect(motivoIncompleto({ id: 'p4', tipo: 'esperar_ate' })).toBe('ESPERAR');
  });

  it('acha o incompleto dentro de um galho', () => {
    const passos = [se([paraCada([])])];
    expect(primeiroIncompleto(passos).id).toBe('p1');
    expect(falta({ gatilho: GATILHO, passos })).toBe('COMPLETAR');
  });
});

describe('o aviso ao lado do Ligar', () => {
  it('"Fazer para cada" vazio fala do passo pelo nome, não do "Se"', () => {
    const texto = ligar([paraCada([])]).text();

    expect(texto).toContain(
      'AUTOMACAO_LIVRE.LIGAR.COMPLETAR.CADA [AUTOMACAO_LIVRE.PASSOS_NOVOS.REPETIR.NOME]'
    );
    expect(texto).not.toContain('COMPLETAR.SE');
  });

  it('bloco sem escolha pede para abrir o passo', () => {
    expect(ligar([bloco(null)]).text()).toContain(
      'AUTOMACAO_LIVRE.LIGAR.COMPLETAR.NOVO [AUTOMACAO_LIVRE.PASSOS_NOVOS.BLOCO.NOME]'
    );
  });

  it('"Se" incompleto mantém a frase do "Se"', () => {
    expect(ligar([se([])]).text()).toContain(
      'AUTOMACAO_LIVRE.LIGAR.COMPLETAR.SE'
    );
  });

  it('completa, o Ligar fica livre', () => {
    const wrapper = ligar([paraCada([aviso])]);

    const botao = wrapper.find('[data-ligar]');

    expect(wrapper.text()).not.toContain('COMPLETAR');
    expect(botao.attributes('disabled')).toBeUndefined();
  });
});

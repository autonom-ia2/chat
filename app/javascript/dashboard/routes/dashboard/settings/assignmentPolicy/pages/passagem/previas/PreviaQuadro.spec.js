import { flushPromises, mount } from '@vue/test-utils';
import PreviaQuadro from './PreviaQuadro.vue';
import PreviaColunas from './PreviaColunas.vue';
import { ETAPA_DESLIGADA, ETAPA_IGUAL, ETAPA_PROPRIA } from '../passagem';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));

// jsdom não tem layout. Simula um quadro de 500 px com colunas de 100 px lado a lado, que andam com o scrollLeft do
// trilho (o mesmo arranjo do spec do FunilQuadro).
const LARGURA = 500;
const COLUNA = 100;
const caixa = (left, width) => ({
  left,
  right: left + width,
  width,
  top: 0,
  bottom: 100,
  height: 100,
});

let retangulo;
let rolagem;
beforeEach(() => {
  retangulo = Object.getOwnPropertyDescriptor(
    Element.prototype,
    'getBoundingClientRect'
  );
  rolagem = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollLeft');
  Object.defineProperty(Element.prototype, 'scrollLeft', {
    configurable: true,
    get() {
      return this.posicao || 0;
    },
    set(valor) {
      this.posicao = valor;
    },
  });
  Element.prototype.getBoundingClientRect = function medida() {
    if (this.hasAttribute('data-previa-trilho')) return caixa(0, LARGURA);
    if (this.hasAttribute('data-coluna')) {
      const indice = [...this.parentElement.children].indexOf(this);
      return caixa(indice * COLUNA - this.parentElement.scrollLeft, COLUNA);
    }
    return caixa(0, 0);
  };
});
afterEach(() => {
  Object.defineProperty(Element.prototype, 'getBoundingClientRect', retangulo);
  if (rolagem) Object.defineProperty(Element.prototype, 'scrollLeft', rolagem);
  else delete Element.prototype.scrollLeft;
});

const regra = (campos = {}) => ({
  enabled: true,
  mode: 'round_robin',
  handoff_mode: 'r2_direct',
  pool_type: 'inbox',
  pool_id: null,
  escalation_action: 'renotify',
  ...campos,
});
const NOMES = [
  'Novo contato',
  'Em conversa',
  'Qualificado',
  'Visita marcada',
  'Proposta enviada',
  'Negociação',
  'Contrato',
  'Fechado',
];
const funil = (n, modos = {}) =>
  NOMES.slice(0, n).map((nome, id) => ({
    id,
    nome,
    modo: modos[id] || ETAPA_IGUAL,
    regra: regra({ handoff_mode: 'r3_invite' }),
  }));

const montar = (Componente, etapas, props = {}) =>
  mount(Componente, {
    props: { nome: 'Vendas', etapas, regra: regra(), ...props },
    attachTo: document.body,
  });

describe('PreviaColunas: o quadro rola para o lado como o do funil', () => {
  it('até cinco etapas: colunas, sem setas nem aviso', async () => {
    // Arrange / Act
    const quadro = montar(PreviaColunas, funil(5));
    await flushPromises();

    // Assert
    expect(quadro.findAll('[data-coluna]')).toHaveLength(5);
    expect(quadro.find('[data-previa-depois]').exists()).toBe(false);
    expect(quadro.find('[data-previa-aviso]').exists()).toBe(false);
    quadro.unmount();
  });

  it('oito etapas: continuam colunas, com a seta e o aviso de mais 3', async () => {
    // Arrange / Act
    const quadro = montar(
      PreviaColunas,
      funil(8, { 4: ETAPA_PROPRIA, 7: ETAPA_DESLIGADA })
    );
    await flushPromises();

    // Assert
    expect(quadro.findAll('[data-coluna]')).toHaveLength(8);
    expect(quadro.find('[data-previa-antes]').exists()).toBe(false);
    expect(quadro.get('[data-previa-depois]').attributes('aria-label')).toBe(
      'CRM_KANBAN.PASSAGEM.PREVIA.VER_DEPOIS {"n":3}'
    );
    expect(quadro.get('[data-previa-aviso]').text()).toContain(
      'MAIS_DEPOIS {"n":3}'
    );
    expect(quadro.get('[data-coluna="Proposta enviada"]').text()).toContain(
      'CRM_KANBAN.PASSAGEM.JEITO.CURTO.CONVITE_EQUIPE'
    );
    expect(quadro.get('[data-coluna="Fechado"]').text()).toContain(
      'QUADRO.NAO'
    );
    quadro.unmount();
  });

  it('a seta avança sem pular etapa e mostra a seta de voltar', async () => {
    // Arrange
    const quadro = montar(PreviaColunas, funil(8));
    await flushPromises();

    // Act
    await quadro.get('[data-previa-depois]').trigger('click');
    await quadro.get('[data-previa-trilho]').trigger('scroll');
    await flushPromises();

    // Assert — a última coluna inteira (a 5ª) vai para a borda de cá e vira a primeira à vista
    expect(quadro.get('[data-previa-trilho]').element.scrollLeft).toBe(400);
    expect(quadro.find('[data-previa-antes]').exists()).toBe(true);
    expect(quadro.find('[data-previa-depois]').exists()).toBe(false);
    quadro.unmount();
  });

  it('a etapa aberta rola sozinha até o meio do quadro', async () => {
    // Arrange / Act
    const quadro = montar(PreviaColunas, funil(8), { acesa: 6 });
    await flushPromises();

    // Assert — coluna 7 (600–700) centrada num quadro de 500: rola 400
    expect(quadro.get('[data-previa-trilho]').element.scrollLeft).toBe(400);
    expect(quadro.get('[data-coluna="Contrato"]').attributes()).toHaveProperty(
      'aria-current',
      'true'
    );
    quadro.unmount();
  });
});

describe('PreviaQuadro: o que acontece se a Ana pedir uma pessoa', () => {
  it('com mais de duas etapas do seu jeito, junta os nomes numa frase só', async () => {
    // Arrange / Act
    const quadro = montar(
      PreviaQuadro,
      funil(8, { 1: ETAPA_PROPRIA, 4: ETAPA_PROPRIA, 6: ETAPA_PROPRIA })
    );
    await flushPromises();

    // Assert
    const percurso = quadro.get('[data-previa-percurso]').text();
    expect(percurso).toContain('PERCURSO_PROPRIAS');
    expect(percurso).not.toContain('PERCURSO_PROPRIA ');
    quadro.unmount();
  });
});

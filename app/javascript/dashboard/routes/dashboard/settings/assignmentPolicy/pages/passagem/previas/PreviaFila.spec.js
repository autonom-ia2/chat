import { mount } from '@vue/test-utils';
import PreviaFila from './PreviaFila.vue';
import { agenteQueNaoRecebe, regraQueVale } from '../passagem';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
  }),
}));

// #1593 — agente de IA parado é como pessoa fora: a prévia diz o mesmo que o aviso ao lado (vai para a equipe).
const REGRA = { pool_type: 'user', pool_id: 'ia:4', mode: 'round_robin' };
const TODAS = [
  { id: 7, name: 'Ana Souza' },
  { id: 'ia:4', name: 'Marta', ia: true, parado: true },
  { id: 'ia:2', name: 'Lia', ia: true, parado: false },
];

describe('agente parado na prévia', () => {
  it('Marta parada: não recebe, e a regra que vale é a da equipe', () => {
    // Arrange / Act
    const parado = agenteQueNaoRecebe(REGRA, TODAS);

    // Assert
    expect(parado).toEqual({ nome: 'Marta' });
    expect(regraQueVale(REGRA, TODAS)).toMatchObject({
      pool_type: 'inbox',
      pool_id: null,
    });
  });

  it('Lia atendendo: recebe, e a regra fica como está', () => {
    // Arrange
    const regra = { ...REGRA, pool_id: 'ia:2' };

    // Act / Assert
    expect(agenteQueNaoRecebe(regra, TODAS)).toBeNull();
    expect(regraQueVale(regra, TODAS)).toBe(regra);
  });

  it('agente que não aparece mais (sem a Fase 2): indisponível, vai para a equipe', () => {
    // Arrange / Act / Assert
    expect(agenteQueNaoRecebe({ ...REGRA, pool_id: 'ia:9' }, TODAS)).toEqual({
      nome: '',
    });
  });

  it('pessoa em "A mesma pessoa" não é afetada', () => {
    // Arrange / Act / Assert
    expect(agenteQueNaoRecebe({ ...REGRA, pool_id: 7 }, TODAS)).toBeNull();
  });

  // Pega: a prévia dizia "Vai para Marta, a qualquer hora" enquanto o aviso dizia que vai para a equipe.
  it('a fila diz que a Marta está parada e vai para alguém da equipe', () => {
    // Arrange / Act
    const wrapper = mount(PreviaFila, {
      props: { regra: REGRA, pessoa: 'Bruno', parado: { nome: 'Marta' } },
    });

    // Assert
    expect(wrapper.find('[data-previa-ia-parado]').text()).toBe(
      'CRM_KANBAN.PASSAGEM.PREVIA.FILA_IA_PARADO {"nome":"Marta"}'
    );
    expect(wrapper.find('[data-previa-ia]').exists()).toBe(false);
  });
});

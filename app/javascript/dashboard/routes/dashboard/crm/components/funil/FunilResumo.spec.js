import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import FunilResumo from './FunilResumo.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #2075 — quem vê os valores de venda (o padrão das telas sem função personalizada).
vi.mock('../../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canSeeSalesValues: { value: true } }),
}));

// #1589 — o resumo do funil de Atender diz o tempo escolhido de cada lembrete.
const montar = lembretesAtender =>
  mount(FunilResumo, {
    props: {
      etapas: [{ name: 'Novo' }, { name: 'Resolvido' }],
      venda: false,
      dinheiro: valor => String(valor),
      juntar: nomes => nomes.join(', '),
      comRetorno: true,
      retorno: { enabled: false },
      sucesso: 'Resolvido',
      lembretesAtender,
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { en, pt_BR },
        }),
      ],
      stubs: { Button: true },
    },
  });

const resumo = wrapper => wrapper.get('[data-setting="returns"]').text();

describe('FunilResumo — lembretes de Atender', () => {
  it('mostra o tempo de cada lembrete ligado', () => {
    const wrapper = montar({
      progress: true,
      resolved_check: true,
      progress_after_hours: 4,
      resolved_check_after_hours: 168,
    });
    expect(resumo(wrapper)).toContain(
      'Avisamos o andamento com 4 horas na mesma etapa e perguntamos se resolveu 1 semana depois de Resolvido.'
    );
  });

  it('sem tempo salvo, ou com valor fora das opções, usa 1 dia', () => {
    const wrapper = montar({
      progress: true,
      resolved_check: false,
      progress_after_hours: 5,
    });
    expect(resumo(wrapper)).toContain(
      'Avisamos o andamento com 1 dia na mesma etapa.'
    );
  });
});

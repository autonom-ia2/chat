import { nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import en from 'dashboard/i18n/locale/en/prospectingAchar.json';
import { useNomeDaLista } from '../composables/useNomeDaLista';

// Achado na gravação da F6 (#2775): num 9 de novembro, o nome sugerido saía
// "salão de beleza · Pinheiros · 11/09". O i18n começa em inglês e troca para a
// língua da conta depois; o nome era montado ao carregar a busca e guardado
// pronto. Agora ele é lido na hora, na língua de agora.
const NOVE_DE_NOVEMBRO = new Date(2026, 10, 9, 10, 0, 0);

const montar = busca => {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en, pt_BR: ptBR },
  });
  let nome;
  mount(
    {
      setup() {
        nome = useNomeDaLista({ busca, hoje: () => NOVE_DE_NOVEMBRO });
        return () => null;
      },
    },
    { global: { plugins: [i18n] } }
  );
  return { nome, i18n };
};

describe('useNomeDaLista', () => {
  it('a busca chega antes da língua da conta: o nome segue a língua que vale agora', async () => {
    const busca = ref({
      id: 1,
      oQue: 'salão de beleza',
      lugar: 'Pinheiros, São Paulo, SP',
    });
    const { nome, i18n } = montar(busca);
    expect(nome.value).toContain('11/09');

    i18n.global.locale.value = 'pt_BR';
    await nextTick();

    expect(nome.value).toBe('salão de beleza · Pinheiros · 09/11');
  });

  it('o nome digitado vale no lugar do sugerido, até trocar de busca', async () => {
    const busca = ref({ id: 1, oQue: 'padarias', lugar: 'Centro, Campinas' });
    const { nome, i18n } = montar(busca);
    i18n.global.locale.value = 'pt_BR';

    nome.value = 'Minha lista';
    expect(nome.value).toBe('Minha lista');

    busca.value = { id: 2, oQue: 'oficinas', lugar: 'Barão Geraldo, Campinas' };
    await nextTick();
    expect(nome.value).toBe('oficinas · Barão Geraldo · 09/11');
  });
});

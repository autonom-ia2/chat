import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { estadoDasGratis, faixaDePreco, marcasDasGratis } from './premium';

// #2858 F7 — o que o cartão e o "Quanto custa" mostram de um card Premium, a partir do `premium` do servidor
// ({ gratis, restantes, precos }): o estado das grátis do mês, as marcas da barrinha e o preço em texto de gente.
const NS = 'AGENTS.VITRINE.PREMIUM';

// Cor do número e da barrinha por estado. Resta uma: âmbar, um aviso calmo. Acabaram: neutro, não é erro (a consulta
// continua funcionando, só passa a ter preço).
const TONS = {
  RESTAM: { texto: 'text-n-iris-11', marca: 'bg-n-iris-9' },
  RESTA_UMA: { texto: 'text-n-amber-11', marca: 'bg-n-amber-9' },
  ACABARAM: { texto: 'text-n-slate-12', marca: 'bg-n-slate-6' },
};

export const usePremium = premium => {
  const { t, locale } = useI18n();

  const gratis = computed(() => Number(premium.value.gratis) || 0);
  const restantes = computed(() =>
    Math.max(Number(premium.value.restantes) || 0, 0)
  );
  const estado = computed(() => estadoDasGratis(restantes.value));
  const tom = computed(() => TONS[estado.value]);
  const marcas = computed(() => marcasDasGratis(gratis.value, restantes.value));
  const faixa = computed(() =>
    faixaDePreco(premium.value.precos, locale.value)
  );
  const preco = computed(() => {
    if (!faixa.value) return '';
    return (
      faixa.value.unico ||
      t(`${NS}.FAIXA`, { min: faixa.value.min, max: faixa.value.max })
    );
  });

  return { gratis, restantes, estado, tom, marcas, faixa, preco };
};

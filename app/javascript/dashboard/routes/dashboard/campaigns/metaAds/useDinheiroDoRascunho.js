import { computed } from 'vue';
import {
  META_DAY_FACTOR,
  ROLLING_DAYS,
  WEEK_DAYS,
  daysBetween,
  longDate,
  money,
  parseAmount,
  withWords,
} from './dinheiroDoAnuncio';

// Anúncios da Meta (#2198), criar: o dinheiro do rascunho, para o passo do orçamento e a conferência. O valor por
// dia digitado, o erro (vazio, abaixo do mínimo, acima do máximo) e as frases por extenso: por dia, o total (até a
// data de fim, ou a cada 30 dias sem ela) e o limite da Meta por dia e por semana.
export const useDinheiroDoRascunho = ({ draft, options, locale, t }) => {
  const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';
  const currency = computed(() => options.value?.currency);
  const fmt = value => money(value, currency.value, locale.value);
  const spelled = value => withWords(value, currency.value, locale.value);

  const dailyAmount = computed(() => parseAmount(draft.value.daily_amount));

  const amountError = computed(() => {
    const value = dailyAmount.value;
    if (!options.value) return '';
    if (value == null) return t(`${KEY}.BUDGET.ERRORS.AMOUNT`);
    if (value < options.value.min_daily) {
      return t(`${KEY}.BUDGET.ERRORS.MIN`, {
        value: fmt(options.value.min_daily),
      });
    }
    if (value > options.value.max_daily) {
      return t(`${KEY}.BUDGET.ERRORS.MAX`, {
        value: fmt(options.value.max_daily),
      });
    }
    return '';
  });

  const perDayLine = computed(() =>
    dailyAmount.value == null
      ? ''
      : t(`${KEY}.REVIEW.PER_DAY`, {
          value: spelled(dailyAmount.value),
        })
  );

  // Com data para terminar: o total até lá. Sem data: o que gasta a cada 30 dias, deixando claro que continua.
  const totalLine = computed(() => {
    const value = dailyAmount.value;
    if (value == null) return '';
    if (!draft.value.end_date) {
      return t(`${KEY}.REVIEW.TOTAL_NO_END`, {
        value: spelled(value * ROLLING_DAYS),
      });
    }
    const days = daysBetween(draft.value.start_date, draft.value.end_date);
    return t(`${KEY}.REVIEW.TOTAL_DAYS`, {
      end: longDate(draft.value.end_date, locale.value),
      days,
      value: spelled(value * days),
    });
  });

  // A regra da Meta para orçamento por dia: até 75% a mais num dia, nunca mais que 7 vezes na semana.
  const dayLimitsLine = computed(() =>
    dailyAmount.value == null
      ? ''
      : t(`${KEY}.BUDGET.DAY_LIMITS`, {
          day: spelled(dailyAmount.value * META_DAY_FACTOR),
          week: spelled(dailyAmount.value * WEEK_DAYS),
        })
  );

  return {
    dailyAmount,
    amountError,
    perDayLine,
    totalLine,
    dayLimitsLine,
  };
};

// #3101: o horário de envio da conta em palavras ("de segunda a sexta, das 8h às 20h"), para o melhor horário da
// campanha e da automação dizerem que a mensagem sempre sai dentro dele. Lê o mesmo GET da tela "Limite de mensagens".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RitmoDeEnvioAPI from 'dashboard/api/ritmoDeEnvio';
import { diasDoResumo } from './ritmoDeEnvio';

const NS = 'CAMPAIGN_JOURNEY.RITMO.HORARIO';

/** Como o resumo diz os dias: "todos os dias", "de segunda a sexta" ou a lista ("segunda, quarta e sexta"). */
export const diasEmTexto = (dias, t, locale) => {
  const { tipo, dias: lista } = diasDoResumo(dias);
  if (tipo !== 'LISTA') return t(`${NS}.DIAS_RESUMO.${tipo}`);
  const nomes = lista.map(dia => t(`${NS}.DIAS_LONGOS.${dia}`));
  return new Intl.ListFormat(locale.replace('_', '-'), {
    type: 'conjunction',
  }).format(nomes);
};

/** O horário guardado em palavras; '' quando a conta deixa mandar a qualquer hora. */
export const horarioEmTexto = (horario, t, locale) => {
  if (!horario) return '';
  const hora = valor => t(`${NS}.HORA`, { hora: valor });
  return t('REENVIO_HORARIO.MELHOR_HORARIO.HORARIO_PERMITIDO', {
    dias: diasEmTexto(horario.dias_da_semana, t, locale),
    inicio: hora(horario.inicio),
    fim: hora(horario.fim),
  });
};

/**
 * O texto do horário da conta: null enquanto não chegou (ou se a leitura falhou), para a tela não afirmar
 * "a qualquer hora" sem saber.
 */
export const useHorarioPermitido = () => {
  const { t, locale } = useI18n();
  const horario = ref(undefined);
  const carregar = async () => {
    try {
      const { data } = await RitmoDeEnvioAPI.buscar();
      horario.value = data.payload?.horario || null;
    } catch {
      // Sem a leitura, fica "não se sabe" (null): a opção some em vez de dizer "a qualquer hora".
      horario.value = undefined;
    }
  };
  carregar();
  return computed(() =>
    horario.value === undefined
      ? null
      : horarioEmTexto(horario.value, t, locale.value)
  );
};

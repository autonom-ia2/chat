// #2138 — a data falada com os nomes do catálogo e o fuso da conta.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';
import { diaFalado, horaFalada } from './dataFalada';

export function useDataFalada() {
  const { t, locale } = useI18n();
  const contaId = useMapGetter('getCurrentAccountId');
  const contas = useMapGetter('accounts/getAccount');
  const fuso = computed(
    () => fusoDaConta(contas.value(contaId.value) || {}) || 'UTC'
  );

  // Chaves literais: o projeto não monta chave de i18n em tempo de execução.
  const nomes = () => ({
    hoje: t('PAINEL_DO_CONTATO.DATA.HOJE'),
    amanha: t('PAINEL_DO_CONTATO.DATA.AMANHA'),
    ontem: t('PAINEL_DO_CONTATO.DATA.ONTEM'),
    semana: [
      t('PAINEL_DO_CONTATO.DATA.SEMANA.DOMINGO'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.SEGUNDA'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.TERCA'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.QUARTA'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.QUINTA'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.SEXTA'),
      t('PAINEL_DO_CONTATO.DATA.SEMANA.SABADO'),
    ],
  });

  const dia = (quando, agora = new Date()) =>
    diaFalado({
      quando,
      agora,
      fuso: fuso.value,
      nomes: nomes(),
      idioma: idiomaDoPainel(locale.value),
    });

  const quandoFalado = (quando, agora = new Date()) =>
    t('PAINEL_DO_CONTATO.DATA.QUANDO', {
      dia: dia(quando, agora),
      hora: horaFalada(quando, fuso.value),
    });

  return { dia, quandoFalado };
}

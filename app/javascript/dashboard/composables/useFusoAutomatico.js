import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStore } from 'dashboard/composables/store';

// O nome que o navegador dá para o fuso, se for um fuso de verdade.
export const fusoDoNavegador = () => {
  try {
    const fuso = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (!fuso) return null;
    Intl.DateTimeFormat('pt-BR', { timeZone: fuso });
    return fuso;
  } catch {
    return null;
  }
};

// O nome do fuso vem sem acento ("America/Cuiaba"); no Brasil, a cidade como se escreve.
const CIDADES_DO_BRASIL = {
  'America/Sao_Paulo': 'São Paulo',
  'America/Cuiaba': 'Cuiabá',
  'America/Belem': 'Belém',
  'America/Maceio': 'Maceió',
  'America/Araguaina': 'Araguaína',
  'America/Santarem': 'Santarém',
  'America/Eirunepe': 'Eirunepé',
  'America/Noronha': 'Fernando de Noronha',
};

// "America/Porto_Velho" -> "Porto Velho". O nome da cidade, que qualquer pessoa reconhece.
export const cidadeDoFuso = fuso =>
  CIDADES_DO_BRASIL[fuso] || fuso.split('/').pop().split('_').join(' ');

// #954: a conta sem fuso ganha o do navegador do administrador, sem perguntar.
// O Brasil tem quatro fusos; gravar São Paulo às cegas deixa Cuiabá uma hora
// errada. Um aviso discreto conta o que foi feito e leva para trocar.
// Quem escolheu na tela de Primeiros passos já tem fuso: vale o que escolheu.
export function useFusoAutomatico() {
  const { t } = useI18n();
  const store = useStore();
  const { currentAccount, accountScopedRoute } = useAccount();
  const { isAdmin } = useAdmin();
  let tentou = false;

  const ajustar = async conta => {
    const escolhido = conta.custom_attributes?.timezone;
    const doRelatorio = conta.settings?.reporting_timezone;
    if (escolhido && doRelatorio) return;

    const fuso = escolhido || fusoDoNavegador();
    if (!fuso) return;

    tentou = true;
    try {
      await store.dispatch('accounts/update', {
        timezone: fuso,
        options: { silent: true },
      });
      useAlert(t('FUSO_AUTOMATICO.AJUSTADO', { cidade: cidadeDoFuso(fuso) }), {
        type: 'link',
        to: accountScopedRoute('general_settings_index'),
        message: t('FUSO_AUTOMATICO.TROCAR'),
      });
    } catch {
      // Sem aviso: a conta segue como estava e a próxima visita tenta de novo.
    }
  };

  watch(
    () => [currentAccount.value?.id, isAdmin.value],
    ([id, admin]) => {
      if (tentou || !id || !admin) return;
      if (currentAccount.value.custom_attributes?.onboarding_step) return;
      ajustar(currentAccount.value);
    },
    { immediate: true }
  );
}

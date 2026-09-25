import { computed, ref } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';

// #697 — descoberta do Guia da Plataforma, comum aos dois pontos de entrada: o botão
// no pé da barra lateral (computador) e a bolinha flutuante (celular, onde não há
// barra lateral fixa). O balão de apresentação aparece UMA vez por usuário ("Entendi"
// grava; "Depois" só adia nesta sessão) e o ponto fica até a primeira abertura. As
// marcas vivem no ui_settings do usuário, que vale em qualquer computador.
const ADIADO_NA_SESSAO = 'autonomia_guide_intro_later';

// sessionStorage pode faltar (aba privada, bloqueio): sem ele, "Depois" vale até
// recarregar a página.
const lerAdiado = () => {
  try {
    return window.sessionStorage.getItem(ADIADO_NA_SESSAO) === '1';
  } catch {
    return false;
  }
};

export function useGuiaDescoberta() {
  const { uiSettings, updateUISettings } = useUISettings();
  const currentAccount = useMapGetter('accounts/getAccount');
  const accountId = useMapGetter('getCurrentAccountId');

  // Gate = `autonomia_guide_available`: a elegibilidade EXATA do backend (ENV mestre +
  // flag da conta + credencial de IA), então a entrada nunca aparece sem Guia de verdade.
  const guiaDisponivel = computed(
    () =>
      currentAccount.value(accountId.value)?.autonomia_guide_available === true
  );
  const painelAberto = computed(
    () => uiSettings.value.is_autonomia_guide_panel_open === true
  );

  const adiado = ref(lerAdiado());
  const jaViuIntro = computed(
    () => uiSettings.value.autonomia_guide_intro_seen === true
  );
  const jaAbriu = computed(
    () => uiSettings.value.autonomia_guide_opened === true
  );

  const mostrarIntro = computed(
    () =>
      guiaDisponivel.value &&
      !painelAberto.value &&
      !jaViuIntro.value &&
      !jaAbriu.value &&
      !adiado.value
  );
  const mostrarPonto = computed(() => guiaDisponivel.value && !jaAbriu.value);

  const entendi = () => updateUISettings({ autonomia_guide_intro_seen: true });

  const depois = () => {
    adiado.value = true;
    try {
      window.sessionStorage.setItem(ADIADO_NA_SESSAO, '1');
    } catch {
      // sem sessionStorage, o adiamento fica só nesta página
    }
  };

  const alternarGuia = () => {
    const abrindo = !painelAberto.value;
    updateUISettings({
      is_autonomia_guide_panel_open: abrindo,
      is_autonomia_copilot_panel_open: false,
      is_contact_sidebar_open: false,
      ...(abrindo
        ? { autonomia_guide_intro_seen: true, autonomia_guide_opened: true }
        : {}),
    });
  };

  return {
    guiaDisponivel,
    painelAberto,
    mostrarIntro,
    mostrarPonto,
    entendi,
    depois,
    alternarGuia,
  };
}

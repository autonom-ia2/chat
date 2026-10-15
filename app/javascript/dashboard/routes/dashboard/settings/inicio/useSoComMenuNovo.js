import { computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { menuNovoLigado } from './inicio.routes';

// A página de cartões só existe com o menu novo (#1617). Pelo endereço, com a flag desligada, ela ficaria presa
// no carregamento (quem entrega os itens é o menu novo): espera a conta carregar e manda para `settings_home`,
// que leva às Configurações de sempre.
export function useSoComMenuNovo() {
  const store = useStore();
  const route = useRoute();
  const router = useRouter();

  const contaCarregada = computed(() =>
    Boolean(
      store.getters['accounts/getAccount'](Number(route.params.accountId))?.id
    )
  );
  const ligada = computed(() => menuNovoLigado(store, route.params.accountId));

  watch(
    [contaCarregada, ligada],
    ([carregada, comMenuNovo]) => {
      if (carregada && !comMenuNovo) {
        router.replace({ name: 'settings_home', params: route.params });
      }
    },
    { immediate: true }
  );

  return { ligada };
}

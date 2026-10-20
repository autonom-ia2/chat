<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmDashboardPage from './CrmDashboardPage.vue';
import CrmNumerosSoEu from '../components/numeros/v2/CrmNumerosSoEu.vue';
import NumerosEspera from '../components/numeros/v2/NumerosEspera.vue';
import { useQuemVeNumeros } from '../components/numeros/useQuemVeNumeros';
import { P } from '../components/numeros/v2/numerosTextos';

// CRM › Números (#1897, F3 do #1871). Sem a flag `crm_numeros_lentes`: o painel de
// hoje. Com ela: "Só eu" para quem trabalha no CRM e "Equipe" (até a F5, o painel
// de hoje) para quem vê a equipe; quem vê as duas troca no seletor, e abre em
// "Equipe" (?visao=eu|equipe). Quem vê a equipe recebe o aviso da Decisão 2.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const { pronto, ligado, veEquipe, veSoEu, abreNumeros } = useQuemVeNumeros();

const visoes = computed(() =>
  [veSoEu.value && 'eu', veEquipe.value && 'equipe'].filter(Boolean)
);
const visao = computed(() =>
  visoes.value.includes(route.query.visao)
    ? route.query.visao
    : visoes.value.at(-1)
);
const opcoesDeVisao = computed(() =>
  visoes.value.map(v => ({
    value: v,
    label: t(`${P}.VISAO.${v === 'eu' ? 'EU' : 'EQUIPE'}`),
  }))
);
const trocarVisao = valor =>
  router.replace({ query: { ...route.query, visao: valor, mes: undefined } });

// O aviso some quando a pessoa diz "Entendi" (só neste navegador).
const chaveDoAviso = computed(
  () => `crm-numeros-aviso-equipe-${accountId.value}`
);
const avisoFechado = ref(false);
const lerAviso = () => {
  try {
    avisoFechado.value =
      window.localStorage.getItem(chaveDoAviso.value) === '1';
  } catch {
    avisoFechado.value = false;
  }
};
const fecharAviso = () => {
  avisoFechado.value = true;
  try {
    window.localStorage.setItem(chaveDoAviso.value, '1');
  } catch {
    // Sem armazenamento no navegador: o aviso volta na próxima visita.
  }
};
// O aviso é para quem vê a equipe (administrador e função com "Visualizar
// relatórios do CRM"), como o próprio texto diz.
const mostrarAviso = computed(
  () => ligado.value && veEquipe.value && !avisoFechado.value
);

// Sem a conta (flags e permissões), nenhuma visão abre: busca de novo e, se não vier,
// mostra o erro com "Tentar de novo" em vez de deixar a página em branco.
const store = useStore();
const contaFalhou = ref(false);
const buscarConta = async () => {
  contaFalhou.value = false;
  await store.dispatch('accounts/get', {
    accountId: accountId.value,
    silent: true,
  });
  contaFalhou.value = !pronto.value;
};

onMounted(() => {
  lerAviso();
  if (!pronto.value) buscarConta();
});

// Quem não abre Números vai para o Kanban, mas só depois que as flags da conta chegam.
watch(
  pronto,
  carregou => {
    if (carregou && !abreNumeros.value)
      router.replace({ name: 'crm_kanban_index', params: route.params });
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="!pronto"
    class="flex h-full w-full flex-col overflow-auto bg-n-background"
  >
    <main
      class="mx-auto flex w-full max-w-3xl flex-col gap-5 px-4 py-5 sm:px-6"
    >
      <NumerosEspera :falhou="contaFalhou" @tentar="buscarConta" />
    </main>
  </div>
  <CrmNumerosSoEu
    v-else-if="ligado && visao === 'eu'"
    :visoes="visoes"
    @visao="trocarVisao"
  >
    <template #aviso>
      <Banner
        v-if="mostrarAviso"
        color="slate"
        :action-label="t(`${P}.AVISO_ADMIN.ENTENDI`)"
        data-numeros-aviso-admin
        @action="fecharAviso"
      >
        {{ t(`${P}.AVISO_ADMIN.TEXTO`) }}
      </Banner>
    </template>
  </CrmNumerosSoEu>
  <CrmDashboardPage v-else-if="abreNumeros">
    <template v-if="ligado" #topo>
      <div class="flex flex-col gap-3 px-6 pt-4">
        <ResultsToggle
          v-if="opcoesDeVisao.length > 1"
          model-value="equipe"
          :options="opcoesDeVisao"
          :label="t(`${P}.VISAO.ROTULO`)"
          data-numeros-visao
          @update:model-value="trocarVisao"
        />
        <Banner
          v-if="mostrarAviso"
          color="slate"
          :action-label="t(`${P}.AVISO_ADMIN.ENTENDI`)"
          data-numeros-aviso-admin
          @action="fecharAviso"
        >
          {{ t(`${P}.AVISO_ADMIN.TEXTO`) }}
        </Banner>
      </div>
    </template>
  </CrmDashboardPage>
</template>

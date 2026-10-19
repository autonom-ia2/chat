<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmDashboardPage from './CrmDashboardPage.vue';
import CrmNumerosSoEu from '../components/numeros/v2/CrmNumerosSoEu.vue';
import { useQuemVeNumeros } from '../components/numeros/useQuemVeNumeros';
import { P } from '../components/numeros/v2/numerosTextos';

// CRM › Números (#1897, F3 do #1871). Sem a flag `crm_numeros_lentes`: o painel de
// hoje. Com ela: "Só eu" para quem trabalha no CRM e "Equipe" (até a F5, o painel
// de hoje) para quem vê a equipe; quem vê as duas troca no seletor, e abre em
// "Equipe" (?visao=eu|equipe). Os administradores recebem o aviso da Decisão 2.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const { ligado, administrador, veEquipe, veSoEu, abreNumeros } =
  useQuemVeNumeros();

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
const mostrarAviso = computed(
  () => ligado.value && administrador.value && !avisoFechado.value
);

onMounted(() => {
  lerAviso();
  if (!abreNumeros.value)
    router.replace({ name: 'crm_kanban_index', params: route.params });
});
</script>

<template>
  <CrmNumerosSoEu
    v-if="ligado && visao === 'eu'"
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
  <CrmDashboardPage v-else>
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

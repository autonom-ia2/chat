<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useGuiaPedido } from 'dashboard/composables/useGuiaPedido';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BuscaDaCentral from '../components/BuscaDaCentral.vue';
import CentralMaisProcurados from '../components/CentralMaisProcurados.vue';
import CentralContinue from '../components/CentralContinue.vue';
import CentralSintomas from '../components/CentralSintomas.vue';
import CentralAssuntos from '../components/CentralAssuntos.vue';

const { t } = useI18n();
const store = useStore();
const { pedirAoGuia } = useGuiaPedido();
const contaAtual = useMapGetter('accounts/getAccount');

const capitulos = ref([]);
const preparando = ref(false);
const carregando = ref(true);
const erro = ref(false);
const buscando = ref(false);

const accountId = computed(() => store.getters.getCurrentAccountId);
const guiaDisponivel = computed(
  () => contaAtual.value(accountId.value)?.autonomia_guide_available === true
);
// Atalhos e assuntos dependem da lista que a API devolveu para a conta.
const pronta = computed(
  () => !carregando.value && !erro.value && !preparando.value
);

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    const { data } = await CentralDeAjudaAPI.get();
    capitulos.value = data.capitulos || [];
    preparando.value = data.preparando || capitulos.value.length === 0;
  } catch {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};

onMounted(carregar);
</script>

<template>
  <section class="h-full w-full overflow-y-auto">
    <div class="mx-auto flex max-w-6xl flex-col gap-8 px-4 py-10">
      <header class="flex flex-col gap-3">
        <h1 class="mb-0 text-3xl font-semibold text-n-slate-12">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.TITULO') }}
        </h1>
        <p class="mb-0 max-w-2xl text-lg text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.SUBTITULO') }}
        </p>
      </header>

      <div class="flex flex-col gap-4 rounded-2xl bg-n-alpha-1 p-4 sm:p-6">
        <BuscaDaCentral
          v-model:ativa="buscando"
          :guia-disponivel="guiaDisponivel"
        />
        <CentralMaisProcurados
          v-if="pronta && !buscando"
          :capitulos="capitulos"
        />
      </div>

      <div v-if="carregando" class="flex justify-center py-12">
        <Spinner />
      </div>

      <div
        v-else-if="erro"
        class="flex flex-col items-center gap-4 py-12 text-center"
      >
        <p class="mb-0 text-lg text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TEXTO') }}
        </p>
        <Button
          size="lg"
          color="slate"
          variant="outline"
          class="min-h-11"
          :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TENTAR')"
          @click="carregar"
        />
      </div>

      <div
        v-else-if="preparando"
        class="flex flex-col items-center gap-3 rounded-2xl bg-n-alpha-1 px-6 py-12 text-center"
      >
        <span class="i-lucide-hourglass size-10 text-n-slate-10" />
        <h2 class="mb-0 text-xl font-medium text-n-slate-12">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.PREPARANDO.TITULO') }}
        </h2>
        <p class="mb-0 text-base text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.PREPARANDO.TEXTO') }}
        </p>
        <Button
          v-if="guiaDisponivel"
          size="lg"
          color="blue"
          variant="faded"
          icon="i-lucide-life-buoy"
          class="mt-2 min-h-11"
          :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PERGUNTE')"
          @click="pedirAoGuia()"
        />
      </div>

      <!-- v-show, não v-if: digitar na busca não recarrega a trilha a cada vez. -->
      <div v-else v-show="!buscando" class="flex flex-col gap-8">
        <!-- Sem o "Continue" (trilha completa ou sem dado), os sintomas ocupam a linha inteira. -->
        <div class="flex flex-col gap-6 lg:flex-row lg:items-start">
          <CentralContinue :capitulos="capitulos" />
          <CentralSintomas :capitulos="capitulos" />
        </div>
        <CentralAssuntos :capitulos="capitulos" />
      </div>
    </div>
  </section>
</template>

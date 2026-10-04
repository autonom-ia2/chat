<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useGuiaPedido } from 'dashboard/composables/useGuiaPedido';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TopoDoAssunto from '../components/TopoDoAssunto.vue';
import ListaDoAssunto from '../components/ListaDoAssunto.vue';
import { useArtigosVistos } from '../composables/useArtigosVistos';
import { CAPITULO_DA_TRILHA, capituloPorId } from '../helpers/assunto';

// Página de um assunto da Central (#977). Usa a mesma leitura da tela inicial e fica só com o
// capítulo da rota: o servidor já tirou o que não vale para a conta.
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { pedirAoGuia } = useGuiaPedido();
const { foiVisto } = useArtigosVistos();
const contaAtual = useMapGetter('accounts/getAccount');

const capitulos = ref([]);
const preparando = ref(false);
const carregando = ref(true);
const erro = ref(false);

const accountId = computed(() => store.getters.getCurrentAccountId);
const guiaDisponivel = computed(
  () => contaAtual.value(accountId.value)?.autonomia_guide_available === true
);
const capitulo = computed(() =>
  capituloPorId(capitulos.value, route.params.capitulo)
);
const numerado = computed(() => capitulo.value?.id !== CAPITULO_DA_TRILHA);

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    const { data } = await CentralDeAjudaAPI.get();
    capitulos.value = data.capitulos || [];
    // Central ainda publicando (logo depois do deploy): não é assunto inexistente, é esperar.
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
    <div class="mx-auto flex max-w-3xl flex-col gap-8 px-4 py-8">
      <div v-if="carregando" class="flex justify-center py-16">
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
        <span
          class="i-lucide-hourglass size-10 text-n-slate-10"
          aria-hidden="true"
        />
        <h2 class="mb-0 text-xl font-medium text-n-slate-12">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.PREPARANDO.TITULO') }}
        </h2>
        <p class="mb-0 text-base text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.PREPARANDO.TEXTO') }}
        </p>
        <Button
          size="lg"
          color="slate"
          variant="outline"
          class="mt-2 min-h-11"
          :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ERRO.TENTAR')"
          @click="carregar"
        />
      </div>

      <!-- Assunto que não existe, ou sem nenhum artigo que valha para a conta. -->
      <div
        v-else-if="!capitulo"
        class="flex flex-col items-center gap-4 rounded-2xl bg-n-alpha-1 px-6 py-12 text-center"
      >
        <span
          class="i-lucide-search-x size-10 text-n-slate-10"
          aria-hidden="true"
        />
        <p class="mb-0 text-lg text-n-slate-11">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VAZIO') }}
        </p>
        <router-link
          :to="{ name: 'central_de_ajuda' }"
          class="inline-flex min-h-11 items-center gap-2 rounded-xl px-3 font-medium text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          <span
            class="i-lucide-arrow-left size-5 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VOLTAR') }}
        </router-link>
      </div>

      <template v-else>
        <TopoDoAssunto :capitulo="capitulo" :foi-visto="foiVisto" />
        <ListaDoAssunto
          :artigos="capitulo.artigos"
          :foi-visto="foiVisto"
          :numerado="numerado"
        />

        <aside
          v-if="guiaDisponivel"
          class="flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-n-alpha-1 px-6 py-5"
        >
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-lg font-medium text-n-slate-12">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.AJUDA_TITULO') }}
            </p>
            <p class="mb-0 text-base text-n-slate-11">
              {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.AJUDA_TEXTO') }}
            </p>
          </div>
          <Button
            size="lg"
            color="blue"
            variant="faded"
            icon="i-lucide-life-buoy"
            class="min-h-11"
            :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.PERGUNTAR')"
            @click="pedirAoGuia()"
          />
        </aside>
      </template>
    </div>
  </section>
</template>

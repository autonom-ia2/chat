<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BuscaDaCentral from '../components/BuscaDaCentral.vue';
import { iconeDoCapitulo, CAPITULO_INICIAL } from '../helpers/icones';

const { t } = useI18n();
const store = useStore();
const { updateUISettings } = useUISettings();
const contaAtual = useMapGetter('accounts/getAccount');

const capitulos = ref([]);
const preparando = ref(false);
const carregando = ref(true);
const erro = ref(false);
const abertos = ref(new Set());
const buscando = ref(false);

const accountId = computed(() => store.getters.getCurrentAccountId);
const guiaDisponivel = computed(
  () => contaAtual.value(accountId.value)?.autonomia_guide_available === true
);

const inicial = computed(() =>
  capitulos.value.find(capitulo => capitulo.id === CAPITULO_INICIAL)
);
const assuntos = computed(() =>
  capitulos.value.filter(capitulo => capitulo.id !== CAPITULO_INICIAL)
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

const alternar = id => {
  const novos = new Set(abertos.value);
  if (novos.has(id)) novos.delete(id);
  else novos.add(id);
  abertos.value = novos;
};

const perguntarAoGuia = () =>
  updateUISettings({
    is_autonomia_guide_panel_open: true,
    is_autonomia_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });

const rotaDoArtigo = artigo => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: artigo.ref },
});

onMounted(carregar);
</script>

<template>
  <section class="h-full w-full overflow-y-auto">
    <div class="max-w-4xl mx-auto px-4 py-10 flex flex-col gap-10">
      <header class="flex flex-col gap-3">
        <h1 class="mb-0 text-3xl font-semibold text-n-slate-12">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.TITULO') }}
        </h1>
        <p class="mb-0 text-lg text-n-slate-11 max-w-2xl">
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.SUBTITULO') }}
        </p>
      </header>

      <BuscaDaCentral
        v-model:ativa="buscando"
        :guia-disponivel="guiaDisponivel"
        @perguntar="perguntarAoGuia"
      />

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
      </div>

      <template v-else-if="!buscando">
        <section
          v-if="inicial"
          class="rounded-2xl border border-n-brand bg-n-solid-1 px-6 py-6 flex flex-col gap-4"
          aria-labelledby="comece-por-aqui"
        >
          <div class="flex items-start gap-4">
            <span
              class="i-lucide-flag size-8 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
            <div>
              <h2
                id="comece-por-aqui"
                class="mb-1 text-2xl font-semibold text-n-slate-12"
              >
                {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.COMECE.TITULO') }}
              </h2>
              <p class="mb-0 text-base text-n-slate-11">
                {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.COMECE.SUBTITULO') }}
              </p>
            </div>
          </div>
          <ol class="m-0 p-0 list-none grid gap-2 sm:grid-cols-2">
            <li v-for="artigo in inicial.artigos" :key="artigo.ref">
              <router-link
                :to="rotaDoArtigo(artigo)"
                class="flex items-center justify-between gap-3 h-full min-h-14 rounded-xl px-4 py-3 bg-n-alpha-1 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              >
                <span class="text-base font-medium text-n-slate-12">
                  {{ artigo.titulo }}
                </span>
                <span
                  class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                  aria-hidden="true"
                />
              </router-link>
            </li>
          </ol>
        </section>

        <section
          class="flex flex-col gap-4"
          aria-labelledby="todos-os-assuntos"
        >
          <h2
            id="todos-os-assuntos"
            class="mb-0 text-2xl font-semibold text-n-slate-12"
          >
            {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTOS') }}
          </h2>
          <ul class="m-0 p-0 list-none flex flex-col gap-3">
            <li
              v-for="capitulo in assuntos"
              :key="capitulo.id"
              class="rounded-2xl border border-n-weak bg-n-solid-1 overflow-hidden"
            >
              <button
                type="button"
                class="w-full flex items-center gap-4 px-5 py-4 min-h-16 text-left hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
                :aria-expanded="abertos.has(capitulo.id)"
                :aria-controls="`capitulo-${capitulo.id}`"
                @click="alternar(capitulo.id)"
              >
                <span
                  class="size-7 shrink-0 text-n-blue-11"
                  :class="iconeDoCapitulo(capitulo.id)"
                  aria-hidden="true"
                />
                <span class="flex-1 min-w-0 flex flex-col">
                  <span class="text-lg font-medium text-n-slate-12">
                    {{ capitulo.titulo }}
                  </span>
                  <span class="text-sm text-n-slate-11">
                    {{
                      t(
                        'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGOS_NO_CAPITULO',
                        capitulo.artigos.length
                      )
                    }}
                  </span>
                </span>
                <span
                  class="size-6 shrink-0 text-n-slate-10 transition-transform"
                  :class="
                    abertos.has(capitulo.id)
                      ? 'i-lucide-chevron-up'
                      : 'i-lucide-chevron-down'
                  "
                  aria-hidden="true"
                />
              </button>
              <ul
                v-if="abertos.has(capitulo.id)"
                :id="`capitulo-${capitulo.id}`"
                class="m-0 p-0 list-none border-t border-n-weak"
              >
                <li
                  v-for="artigo in capitulo.artigos"
                  :key="artigo.ref"
                  class="border-b border-n-weak last:border-b-0"
                >
                  <router-link
                    :to="rotaDoArtigo(artigo)"
                    class="flex flex-col gap-1 px-5 py-4 ltr:pl-16 rtl:pr-16 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
                  >
                    <span class="text-base font-medium text-n-slate-12">
                      {{ artigo.titulo }}
                    </span>
                    <span class="text-sm text-n-slate-11">
                      {{ artigo.descricao }}
                    </span>
                  </router-link>
                </li>
              </ul>
            </li>
          </ul>
        </section>
      </template>
    </div>
  </section>
</template>

<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { iconeDoCapitulo } from '../helpers/icones';
import { agruparPorFamilia } from '../helpers/assuntos';

// "Por assunto": os capítulos agrupados pelo que a pessoa quer fazer. Clicar no assunto abre a lista
// de artigos dele logo abaixo.
const props = defineProps({
  capitulos: { type: Array, required: true },
});

const { t } = useI18n();

const familias = computed(() => agruparPorFamilia(props.capitulos));
const abertos = ref(new Set());

const alternar = id => {
  const novos = new Set(abertos.value);
  if (novos.has(id)) novos.delete(id);
  else novos.add(id);
  abertos.value = novos;
};

// Assunto de capítulo novo, ainda sem nome curto, usa o título que veio da API.
const nomeDo = assunto =>
  assunto.nome
    ? t(`HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.${assunto.nome}`)
    : assunto.titulo;

const rotaDoArtigo = artigo => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: artigo.ref },
});
</script>

<template>
  <section class="flex flex-col gap-4" aria-labelledby="central-por-assunto">
    <h2
      id="central-por-assunto"
      class="mb-0 text-2xl font-semibold text-n-slate-12"
    >
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.TITULO') }}
    </h2>
    <div class="grid items-start gap-4 md:grid-cols-2 lg:grid-cols-4">
      <section
        v-for="familia in familias"
        :key="familia.id"
        class="flex min-w-0 flex-col gap-2"
        :aria-labelledby="`familia-${familia.id}`"
      >
        <h3
          :id="`familia-${familia.id}`"
          class="mb-0 px-1 text-sm font-semibold text-n-slate-11"
        >
          {{
            t(`HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.FAMILIAS.${familia.id}`)
          }}
        </h3>
        <ul class="m-0 flex list-none flex-col gap-2 p-0">
          <li v-for="assunto in familia.assuntos" :key="assunto.id">
            <button
              type="button"
              class="flex w-full min-h-11 items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-start hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-expanded="abertos.has(assunto.id)"
              :aria-controls="`assunto-${assunto.id}`"
              @click="alternar(assunto.id)"
            >
              <span
                class="grid size-9 shrink-0 place-items-center rounded-lg bg-n-brand/10 text-n-blue-11"
                aria-hidden="true"
              >
                <span class="size-5" :class="iconeDoCapitulo(assunto.id)" />
              </span>
              <span class="flex min-w-0 flex-1 flex-col">
                <span class="text-base font-medium text-n-slate-12">
                  {{ nomeDo(assunto) }}
                </span>
                <span class="flex flex-wrap gap-x-3 text-sm text-n-slate-11">
                  <span class="whitespace-nowrap">
                    {{
                      t(
                        'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGOS_NO_CAPITULO',
                        assunto.artigos.length
                      )
                    }}
                  </span>
                  <span
                    v-if="assunto.videos"
                    class="inline-flex items-center gap-1 whitespace-nowrap"
                  >
                    <span
                      class="i-lucide-circle-play size-3.5"
                      aria-hidden="true"
                    />
                    {{
                      t(
                        'HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.VIDEOS',
                        assunto.videos
                      )
                    }}
                  </span>
                </span>
              </span>
              <span
                class="size-5 shrink-0 text-n-slate-10"
                :class="
                  abertos.has(assunto.id)
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
                aria-hidden="true"
              />
            </button>
            <ul
              v-show="abertos.has(assunto.id)"
              :id="`assunto-${assunto.id}`"
              class="m-0 mt-1 flex list-none flex-col gap-1 p-0 ltr:pl-12 rtl:pr-12"
            >
              <li v-for="artigo in assunto.artigos" :key="artigo.ref">
                <router-link
                  :to="rotaDoArtigo(artigo)"
                  class="flex min-h-11 items-center gap-2 rounded-lg px-2 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                >
                  <span
                    v-if="artigo.video"
                    class="i-lucide-circle-play size-4 shrink-0 text-n-blue-11"
                    aria-hidden="true"
                  />
                  {{ artigo.titulo }}
                </router-link>
              </li>
            </ul>
          </li>
        </ul>
      </section>
    </div>
  </section>
</template>

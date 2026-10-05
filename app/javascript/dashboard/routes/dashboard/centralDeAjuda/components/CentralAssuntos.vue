<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { iconeDoCapitulo } from '../helpers/icones';
import { agruparPorFamilia } from '../helpers/assuntos';

// "Por assunto": os capítulos agrupados pelo que a pessoa quer fazer. Cada assunto leva à página
// dele, com a lista de artigos e o que a pessoa já viu.
const props = defineProps({
  capitulos: { type: Array, required: true },
});

const { t } = useI18n();

const familias = computed(() => agruparPorFamilia(props.capitulos));

// Assunto de capítulo novo, ainda sem nome curto, usa o título que veio da API.
const nomeDo = assunto =>
  assunto.nome
    ? t(`HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.${assunto.nome}`)
    : assunto.titulo;

const rotaDoAssunto = assunto => ({
  name: 'central_de_ajuda_assunto',
  params: { capitulo: assunto.id },
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
            <router-link
              :to="rotaDoAssunto(assunto)"
              class="flex w-full min-h-11 items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-start hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
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
                class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                aria-hidden="true"
              />
            </router-link>
          </li>
        </ul>
      </section>
    </div>
  </section>
</template>

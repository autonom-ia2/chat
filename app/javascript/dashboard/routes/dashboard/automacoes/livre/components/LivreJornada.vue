<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { JORNADAS, etapaAtual } from '../prototipo/jornadas';

// #2414 F0 — o mapa da jornada do protótipo: um painel pequeno e recolhível,
// num canto, que leva a cada etapa e diz o que muda em relação a hoje. Só
// existe no protótipo.
const route = useRoute();
const aberto = ref(false);

const atual = computed(() => etapaAtual(route));

const destino = item => ({
  name: item.name,
  params: { accountId: route.params.accountId, ...item.params },
  query: item.query,
});

const ehAtual = (jornada, item) =>
  atual.value?.jornada === jornada.chave && atual.value?.chave === item.chave;
</script>

<template>
  <aside
    data-jornada
    class="fixed z-[60] flex flex-col gap-2 bottom-4 end-4 w-[min(22rem,calc(100vw-2rem))]"
    :aria-label="$t('AUTOMACAO_LIVRE.JORNADA.TITULO')"
  >
    <div
      v-if="aberto"
      id="livre-jornada-lista"
      class="flex flex-col gap-4 p-4 overflow-y-auto border shadow-xl max-h-[70vh] rounded-2xl border-n-weak bg-n-solid-1"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.JORNADA.EXPLICA') }}
      </p>
      <section
        v-for="jornada in JORNADAS"
        :key="jornada.chave"
        class="flex flex-col gap-1"
      >
        <h3 class="mb-1 text-sm font-semibold text-n-slate-12">
          {{ $t(`AUTOMACAO_LIVRE.JORNADA.${jornada.chave}.TITULO`) }}
        </h3>
        <ol class="flex flex-col gap-0.5 p-0 m-0 list-none">
          <li v-for="(item, indice) in jornada.etapas" :key="item.chave">
            <router-link
              :to="destino(item)"
              :data-etapa-jornada="`${jornada.chave}.${item.chave}`"
              :aria-current="ehAtual(jornada, item) ? 'page' : undefined"
              class="flex items-center gap-2 px-2 text-sm rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="
                ehAtual(jornada, item)
                  ? 'bg-n-blue-3 text-n-blue-11 font-semibold'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
            >
              <span
                class="grid text-xs font-bold rounded-full place-items-center size-6 shrink-0 bg-n-slate-3"
              >
                {{ indice + 1 }}
              </span>
              {{
                $t(
                  `AUTOMACAO_LIVRE.JORNADA.${jornada.chave}.${item.chave}.NOME`
                )
              }}
            </router-link>
          </li>
        </ol>
      </section>
    </div>

    <div
      v-if="atual"
      data-nota-jornada
      class="p-3 text-sm border shadow-lg rounded-2xl border-n-amber-6 bg-n-amber-2 text-n-slate-12"
      :class="aberto ? '' : 'hidden md:block'"
    >
      <p class="mb-0.5 font-semibold text-n-amber-11">
        {{ $t('AUTOMACAO_LIVRE.JORNADA.O_QUE_MUDA') }}
      </p>
      <p class="mb-0">
        {{ $t(`AUTOMACAO_LIVRE.JORNADA.${atual.jornada}.${atual.chave}.NOTA`) }}
      </p>
    </div>

    <button
      type="button"
      data-abrir-jornada
      class="inline-flex items-center self-end gap-2 px-4 text-sm font-semibold text-white rounded-full shadow-lg min-h-11 bg-n-heroi dark:bg-n-heroi-escuro focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      :aria-expanded="aberto"
      aria-controls="livre-jornada-lista"
      @click="aberto = !aberto"
    >
      <span class="i-lucide-map size-4" aria-hidden="true" />
      {{ $t('AUTOMACAO_LIVRE.JORNADA.TITULO') }}
      <span
        class="size-4"
        :class="aberto ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
        aria-hidden="true"
      />
    </button>
  </aside>
</template>

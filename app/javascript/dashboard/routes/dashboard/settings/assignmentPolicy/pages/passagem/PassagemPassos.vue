<script setup>
import { computed } from 'vue';

// #1385 — onde a pessoa está na regra própria de uma etapa: Quando → Quem recebe → Como entregar. Mesmo desenho dos
// passos do funil (#1384): passo feito ganha o visto e volta com um toque; o de agora tem o número cheio. No celular,
// os nomes não cabem lado a lado: uma linha em cima diz "Passo 1 de 3: Quando".
const props = defineProps({
  atual: { type: Number, required: true },
  nomes: { type: Array, required: true },
  rotulo: { type: String, required: true },
});

defineEmits(['ir']);

const passos = computed(() =>
  props.nomes.map((nome, indice) => {
    const numero = indice + 1;
    return {
      nome,
      numero,
      agora: numero === props.atual,
      feito: numero < props.atual,
    };
  })
);
</script>

<template>
  <div class="flex flex-col gap-1">
    <p
      class="mb-0 text-sm font-medium text-n-slate-11 sm:hidden"
      aria-hidden="true"
    >
      {{
        $t('CRM_KANBAN.PASSAGEM.ETAPA.PASSO_DE', {
          n: atual,
          total: nomes.length,
          nome: nomes[atual - 1],
        })
      }}
    </p>
    <ol
      data-passagem-passos
      :aria-label="rotulo"
      class="m-0 flex list-none flex-wrap items-center gap-1 p-0 sm:gap-2"
    >
      <template v-for="(passo, indice) in passos" :key="passo.nome">
        <li
          v-if="indice > 0"
          aria-hidden="true"
          class="h-0.5 w-4 rounded-full sm:w-8"
          :class="passo.agora || passo.feito ? 'bg-n-blue-8' : 'bg-n-slate-6'"
        />
        <li>
          <component
            :is="passo.feito ? 'button' : 'span'"
            :type="passo.feito ? 'button' : undefined"
            :aria-current="passo.agora ? 'step' : undefined"
            class="flex min-h-11 items-center gap-1.5 rounded-xl px-1 text-[0.9375rem] font-semibold sm:gap-2 sm:px-2"
            :class="{
              'text-n-slate-12': passo.agora,
              'text-n-teal-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand':
                passo.feito,
              'text-n-slate-11': !passo.agora && !passo.feito,
            }"
            @click="passo.feito && $emit('ir', passo.numero)"
          >
            <span
              class="grid size-8 place-items-center rounded-full text-sm font-bold"
              :class="{
                'bg-n-blue-9 text-white': passo.agora,
                'bg-n-teal-3 text-n-teal-11': passo.feito,
                'bg-n-slate-3 text-n-slate-11': !passo.agora && !passo.feito,
              }"
            >
              <span
                v-if="passo.feito"
                class="i-lucide-check size-4"
                aria-hidden="true"
              />
              <template v-else>{{ passo.numero }}</template>
            </span>
            <span class="sr-only sm:not-sr-only">{{ passo.nome }}</span>
          </component>
        </li>
      </template>
    </ol>
  </div>
</template>

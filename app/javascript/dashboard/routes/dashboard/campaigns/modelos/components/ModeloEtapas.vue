<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Onde a pessoa está na criação. Etapa já feita ganha o visto e pode ser
// aberta de novo com um clique. No celular vira uma linha só: "Etapa 2 de 5"
// com o nome e uma barra de progresso.
const props = defineProps({
  etapas: { type: Array, required: true },
  atual: { type: String, required: true },
  // Nome próprio de uma etapa (ex.: "extras" vira "Cartões" no carrossel).
  rotulos: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['ir']);
const { t } = useI18n();

const rotulo = chave =>
  props.rotulos[chave] || t(`MODELOS_WHATSAPP.ETAPAS.${chave}`);

const lista = computed(() => {
  const indiceAtual = props.etapas.indexOf(props.atual);
  return props.etapas.map((chave, indice) => ({
    chave,
    numero: indice + 1,
    feita: indice < indiceAtual,
    agora: indice === indiceAtual,
  }));
});

const numeroAtual = computed(() => props.etapas.indexOf(props.atual) + 1);
</script>

<template>
  <div data-etapas>
    <div class="flex flex-col gap-2 sm:hidden" data-etapas-celular>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{
          $t('MODELOS_WHATSAPP.ETAPAS.DE', {
            n: numeroAtual,
            total: etapas.length,
          })
        }}
        <strong class="font-semibold text-n-blue-11">{{
          rotulo(atual)
        }}</strong>
      </p>
      <span
        class="flex gap-1"
        role="progressbar"
        :aria-valuenow="numeroAtual"
        aria-valuemin="1"
        :aria-valuemax="etapas.length"
        :aria-label="$t('MODELOS_WHATSAPP.ETAPAS.ROTULO')"
      >
        <span
          v-for="etapa in lista"
          :key="etapa.chave"
          class="flex-1 h-1.5 rounded-full"
          :class="etapa.feita || etapa.agora ? 'bg-n-blue-9' : 'bg-n-slate-4'"
        />
      </span>
    </div>
    <ol
      :aria-label="$t('MODELOS_WHATSAPP.ETAPAS.ROTULO')"
      class="hidden sm:flex flex-wrap items-center gap-x-3 gap-y-2 p-0 m-0 list-none"
    >
      <template v-for="(etapa, indice) in lista" :key="etapa.chave">
        <li
          v-if="indice > 0"
          aria-hidden="true"
          class="w-6 h-0.5 rounded-full"
          :class="etapa.feita || etapa.agora ? 'bg-n-blue-7' : 'bg-n-slate-6'"
        />
        <li :data-etapa="etapa.chave">
          <button
            type="button"
            :disabled="!etapa.feita && !etapa.agora"
            :aria-current="etapa.agora ? 'step' : undefined"
            class="flex items-center gap-2 text-[0.9375rem] font-semibold rounded-lg min-h-11 disabled:cursor-default focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="{
              'text-n-teal-11 hover:underline': etapa.feita,
              'text-n-blue-11': etapa.agora,
              'text-n-slate-10': !etapa.feita && !etapa.agora,
            }"
            @click="etapa.feita && emit('ir', etapa.chave)"
          >
            <span
              class="grid text-sm font-bold rounded-full place-items-center size-8"
              :class="{
                'bg-n-teal-3': etapa.feita,
                'bg-n-blue-3': etapa.agora,
                'bg-n-slate-3': !etapa.feita && !etapa.agora,
              }"
            >
              <span
                v-if="etapa.feita"
                class="i-lucide-check size-4"
                aria-hidden="true"
              />
              <template v-else>{{ etapa.numero }}</template>
            </span>
            {{ rotulo(etapa.chave) }}
          </button>
        </li>
      </template>
    </ol>
  </div>
</template>

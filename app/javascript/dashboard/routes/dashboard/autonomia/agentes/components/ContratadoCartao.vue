<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { TOM_DO_RAMO } from '../constants/modelosDeRamo';
import { MODELO_UNIVERSAL } from '../constants/contratados';

// #3211 — um agente pronto para contratar, na seção "Vendem sozinhos" (mockup aprovado, estado 01). Como o
// RamoCartao: o cartão inteiro abre a página do modelo, porque o "Ver como funciona" se estica sobre ele
// (after:absolute) e continua um botão só. Quem só vê lê o cartão, sem o botão. Os textos de cada modelo vêm do
// i18n por chave fixa; quem usa só monta modelos de MODELOS_CONTRATADOS.
const props = defineProps({
  modelo: { type: String, required: true },
  podeUsar: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const { t } = useI18n();

const TEXTOS = {
  [MODELO_UNIVERSAL]: () => ({
    titulo: t('AGENTS.CONTRATADOS.CARTAO.TITULO'),
    texto: t('AGENTS.CONTRATADOS.CARTAO.TEXTO'),
    precisa: t('AGENTS.CONTRATADOS.CARTAO.PRECISA'),
    icone: 'i-lucide-plane',
  }),
};

const textos = computed(() => TEXTOS[props.modelo]());
</script>

<template>
  <li
    data-contratado
    class="relative flex flex-col gap-4 p-5 transition shadow-sm md:flex-row md:items-center rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    :class="podeUsar ? 'hover:ring-n-blue-11 hover:shadow-md' : ''"
  >
    <div class="flex items-start gap-3 grow">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-12 shrink-0"
        :class="TOM_DO_RAMO.azul"
      >
        <span class="size-6" :class="textos.icone" />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <h3 class="m-0 text-lg font-semibold leading-snug text-n-slate-12">
          {{ textos.titulo }}
        </h3>
        <p class="m-0 text-sm leading-relaxed text-n-slate-11">
          {{ textos.texto }}
        </p>
        <p class="flex items-center gap-1.5 m-0 text-sm text-n-slate-12">
          <span
            class="i-lucide-key-round size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ textos.precisa }}
        </p>
      </div>
    </div>
    <button
      v-if="podeUsar"
      data-ver-contratado
      type="button"
      :aria-label="
        t('AGENTS.CONTRATADOS.CARTAO.VER_ARIA', { nome: textos.titulo })
      "
      class="inline-flex items-center justify-between w-full gap-3 px-4 text-base font-semibold transition md:w-auto shrink-0 min-h-12 rounded-xl bg-n-blue-2 text-n-blue-11 after:absolute after:inset-0 after:rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      @click="emit('abrir', modelo)"
    >
      {{ t('AGENTS.CONTRATADOS.CARTAO.VER') }}
      <span
        class="i-lucide-arrow-right size-5 shrink-0 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
  </li>
</template>

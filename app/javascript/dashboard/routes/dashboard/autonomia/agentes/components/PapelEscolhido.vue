<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { papelPelaChave } from '../constants/papeis';

// #3219 — a faixa "Você escolheu: <papel> · Trocar" do passo 2 e do "Escrever eu mesmo" com papel. "Trocar" volta ao
// passo 1 (quem usa decide como). `claro`: sobre fundo branco (Escrever); sem ele, sobre o herói navy. `papel` é uma
// chave de constants/papeis que quem usa já conferiu (papelDoPasso).
const props = defineProps({
  papel: { type: String, required: true },
  claro: { type: Boolean, default: false },
  desligado: { type: Boolean, default: false },
});

const emit = defineEmits(['trocar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS';
const escolhido = computed(() => papelPelaChave(props.papel));
</script>

<template>
  <div
    data-papel-escolhido
    class="flex items-center w-full gap-3 py-2 rounded-2xl ps-3 pe-2 md:w-fit"
    :class="claro ? 'bg-n-alpha-2 text-n-slate-12' : 'bg-white/10 text-white'"
  >
    <span
      aria-hidden="true"
      class="grid rounded-xl place-items-center size-9 shrink-0"
      :class="claro ? 'bg-n-blue-3 text-n-blue-11' : 'bg-white/10'"
    >
      <span class="size-5" :class="escolhido.icone" />
    </span>
    <p class="flex flex-col min-w-0 m-0 grow">
      <span
        class="text-sm"
        :class="claro ? 'text-n-slate-11' : 'text-white/80'"
      >
        {{ t(`${NS}.COMO.ESCOLHIDO`) }}
      </span>
      <span class="text-sm font-semibold">
        {{ t(`${NS}.PAPEIS.${escolhido.i18n}.TITULO`) }}
      </span>
    </p>
    <button
      type="button"
      data-trocar-papel
      :disabled="desligado"
      :aria-label="t(`${NS}.COMO.TROCAR_ARIA`)"
      class="px-3 text-sm font-semibold underline shrink-0 rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 disabled:opacity-50 disabled:cursor-not-allowed"
      :class="
        claro
          ? 'text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline-n-blue-11'
          : 'text-white hover:bg-white/10 focus-visible:outline-white'
      "
      @click="emit('trocar')"
    >
      {{ t(`${NS}.COMO.TROCAR`) }}
    </button>
  </div>
</template>

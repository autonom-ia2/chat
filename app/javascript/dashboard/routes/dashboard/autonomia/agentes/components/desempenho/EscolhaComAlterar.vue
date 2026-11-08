<script setup>
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2226 (ESPEC 2.3) — "Últimos 30 dias · Alterar": a escolha atual escrita por extenso e o botão
// "Alterar", que vira a escolha (ChoiceSelect, nunca <select>) já aberta, como o BlocoQuemCuida
// (#2138). Fechou sem escolher, volta o texto. `tom` escuro é o do herói navy.
const props = defineProps({
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
  // Texto antes da escolha ("Ver" em "Ver por campanha · Alterar"); vazio, só a escolha.
  prefixo: { type: String, default: '' },
  // Texto fixo no lugar da escolha atual (ex.: "Sugerido" num assunto ainda não confirmado).
  textoFixo: { type: String, default: '' },
  tom: {
    type: String,
    default: 'claro',
    validator: v => ['claro', 'escuro'].includes(v),
  },
});

const escolha = defineModel({
  type: [String, Number, Boolean],
  required: true,
});

const { t } = useI18n();
const escolhendo = ref(false);
const lista = useTemplateRef('lista');
const caixa = useTemplateRef('caixa');

const texto = computed(
  () =>
    props.textoFixo ||
    props.opcoes.find(opcao => opcao.value === escolha.value)?.label ||
    ''
);
const escuro = computed(() => props.tom === 'escuro');

const abrir = async () => {
  escolhendo.value = true;
  await nextTick();
  lista.value?.abrir();
};

const saiu = evento => {
  if (!caixa.value?.contains(evento.relatedTarget)) escolhendo.value = false;
};

defineExpose({ abrir });
</script>

<template>
  <div
    ref="caixa"
    data-escolha
    class="flex flex-wrap items-center gap-x-2 gap-y-1"
    @focusout="saiu"
  >
    <ChoiceSelect
      v-if="escolhendo"
      ref="lista"
      v-model="escolha"
      :options="opcoes"
      :aria-label="rotulo"
      compact
      class="min-w-48"
      @change="escolhendo = false"
    />
    <template v-else>
      <span
        data-texto
        class="text-sm font-semibold"
        :class="escuro ? 'text-white' : 'text-n-slate-12'"
      >
        {{ prefixo ? `${prefixo} ${texto}` : texto }}
      </span>
      <span
        class="i-lucide-dot size-4"
        aria-hidden="true"
        :class="escuro ? 'text-white/60' : 'text-n-slate-10'"
      />
      <button
        type="button"
        data-alterar
        :aria-label="`${t('AGENTS.DESEMPENHO.ALTERAR')}: ${rotulo}`"
        class="inline-flex items-center px-1 text-sm font-semibold underline rounded-lg min-h-11 underline-offset-4 focus-visible:outline focus-visible:outline-2"
        :class="
          escuro
            ? 'text-white hover:text-white/80 focus-visible:outline-white'
            : 'text-n-blue-11 hover:text-n-blue-10 focus-visible:outline-n-blue-11'
        "
        @click="abrir"
      >
        {{ t('AGENTS.DESEMPENHO.ALTERAR') }}
      </button>
    </template>
  </div>
</template>

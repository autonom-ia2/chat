<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';
import LivreTexto from './LivreTexto.vue';

// G3 (#2629) — a mensagem ao cliente na hora do retorno (o envio automático do
// Followup). Desligada, o passo fica só com o lembrete para a equipe: o campo
// sai da receita.
defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const R = 'AUTOMACAO_LIVRE.RETORNO';
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="envio_do_retorno">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <label
      class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
    >
      <span class="text-[0.9375rem] text-n-slate-12">
        {{ $t(`${R}.MANDAR`) }}
      </span>
      <Switch
        data-mandar
        class="mx-1.5 scale-[1.4]"
        :model-value="Boolean(modelValue)"
        :aria-label="$t(`${R}.MANDAR`)"
        @update:model-value="
          ligado => emit('update:modelValue', ligado ? { mensagem: [] } : null)
        "
      />
    </label>
    <template v-if="modelValue">
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${R}.MANDAR_DICA`) }}</p>
      <LivreTexto
        data-mensagem
        :rotulo="$t(`${R}.MENSAGEM`)"
        :model-value="modelValue.mensagem"
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="
          mensagem => emit('update:modelValue', { mensagem })
        "
      />
    </template>
    <p v-else class="mb-0 text-sm text-n-slate-11">
      {{ $t(`${R}.SO_LEMBRETE`) }}
    </p>
  </fieldset>
</template>

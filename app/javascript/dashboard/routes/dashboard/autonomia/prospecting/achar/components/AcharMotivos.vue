<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — os 4 motivos grandes de "Não serve" (2×2), na gaveta e na fila. As
// ids são os do descarte de hoje (rótulos próprios, rodada 3): tocar já
// marca, sem botão de confirmar. Rodada 2: cartões com borda visível e o link
// "Outro motivo" (v4), que abre um campo para escrever.
defineProps({
  titulo: { type: String, required: true },
});

const emit = defineEmits(['escolher']);

const MOTIVOS = [
  { id: 'no_interest', chave: 'NO_INTEREST', icone: 'i-lucide-thumbs-down' },
  {
    id: 'already_customer',
    chave: 'ALREADY_CUSTOMER',
    icone: 'i-lucide-handshake',
  },
  { id: 'closed', chave: 'CLOSED', icone: 'i-lucide-store' },
  { id: 'wrong_data', chave: 'WRONG_DATA', icone: 'i-lucide-file-x' },
];

const escrevendo = ref(false);
const outro = ref('');
</script>

<template>
  <section class="flex flex-col gap-4" data-motivos>
    <h3 class="m-0 text-lg font-semibold text-n-slate-12">{{ titulo }}</h3>
    <div class="grid grid-cols-2 gap-3">
      <button
        v-for="motivo in MOTIVOS"
        :key="motivo.id"
        type="button"
        class="flex flex-col items-start gap-3 p-4 transition border-2 border-solid text-start min-h-24 rounded-2xl border-n-slate-6 bg-n-solid-1 hover:border-n-slate-8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :data-motivo="motivo.id"
        @click="emit('escolher', motivo.id)"
      >
        <span
          class="grid rounded-xl size-10 place-items-center bg-n-slate-3 text-n-slate-11"
          aria-hidden="true"
        >
          <span class="size-5" :class="motivo.icone" />
        </span>
        <span class="text-base font-semibold text-n-slate-12">
          {{ $t(`PROSPECTING_ACHAR.MOTIVOS.${motivo.chave}`) }}
        </span>
      </button>
    </div>
    <button
      v-if="!escrevendo"
      type="button"
      class="self-start px-1 text-sm font-medium min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      data-outro-motivo
      @click="escrevendo = true"
    >
      {{ $t('PROSPECTING_ACHAR.MOTIVOS.OUTRO') }}
    </button>
    <div v-else class="flex flex-col gap-2">
      <label
        for="achar-outro-motivo"
        class="text-sm font-semibold text-n-slate-11"
      >
        {{ $t('PROSPECTING_ACHAR.MOTIVOS.ESCREVA') }}
      </label>
      <textarea
        id="achar-outro-motivo"
        v-model="outro"
        rows="2"
        maxlength="255"
        class="w-full px-3 py-2 text-base border outline-none !mb-0 rounded-xl border-n-slate-6 bg-n-solid-1 text-n-slate-12 focus:border-n-blue-9"
      />
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.CONFIRMAR')"
        :disabled="!outro.trim()"
        class="self-start !min-h-12 !rounded-xl !px-6 !text-base"
        @click="emit('escolher', 'other', outro.trim())"
      />
    </div>
  </section>
</template>

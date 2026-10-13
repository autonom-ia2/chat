<script setup>
import { computed } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { VALIDADE_MAXIMA, VALIDADE_MINIMA } from '../../constants';

// Código de verificação: o texto é fixo do WhatsApp. A pessoa escolhe o botão
// (copiar ou preencher sozinho), a validade e o aviso de segurança. Sem link,
// foto ou emoji.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const codigo = computed(() => rascunho.value.conteudo.codigo);
const BOTOES = [
  { chave: 'copiar', icone: 'i-lucide-copy' },
  { chave: 'preencher', icone: 'i-lucide-text-cursor-input' },
];

const mudar = (campo, valor) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...rascunho.value.conteudo,
      codigo: { ...codigo.value, [campo]: valor },
    },
  };
};

const validadeErrada = computed(
  () =>
    !(codigo.value.validade >= VALIDADE_MINIMA && codigo.value.validade <= VALIDADE_MAXIMA)
);
</script>

<template>
  <div data-etapa-codigo class="flex flex-col gap-6">
    <section class="flex flex-col gap-3">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.CODIGO.BOTAO') }}
      </h2>
      <div role="radiogroup" :aria-label="$t('MODELOS_WHATSAPP.CODIGO.BOTAO')" class="grid gap-3 sm:grid-cols-2">
        <button
          v-for="botao in BOTOES"
          :key="botao.chave"
          type="button"
          role="radio"
          :data-botao-codigo="botao.chave"
          :aria-checked="codigo.botao === botao.chave"
          class="flex items-start gap-3 p-4 text-start rounded-xl ring-1 ring-inset min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            codigo.botao === botao.chave
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-blue-6'
          "
          @click="mudar('botao', botao.chave)"
        >
          <span class="grid place-items-center size-10 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11">
            <span class="size-5" :class="botao.icone" aria-hidden="true" />
          </span>
          <span class="flex flex-col gap-0.5">
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ $t(`MODELOS_WHATSAPP.FORMATOS.codigo.BOTOES.${botao.chave}`) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ $t(`MODELOS_WHATSAPP.CODIGO.BOTOES_PARA.${botao.chave}`) }}
            </span>
          </span>
        </button>
      </div>
    </section>

    <Input
      :model-value="codigo.validade"
      data-validade
      type="number"
      :min="String(VALIDADE_MINIMA)"
      :max="String(VALIDADE_MAXIMA)"
      :label="$t('MODELOS_WHATSAPP.CODIGO.VALIDADE')"
      :message="$t('MODELOS_WHATSAPP.CODIGO.VALIDADE_AJUDA', { min: VALIDADE_MINIMA, max: VALIDADE_MAXIMA })"
      :message-type="validadeErrada ? 'error' : 'info'"
      @update:model-value="valor => mudar('validade', valor)"
    />

    <button
      type="button"
      role="checkbox"
      data-aviso-seguranca
      :aria-checked="codigo.avisoDeSeguranca"
      class="flex items-start gap-3 p-4 text-start rounded-xl ring-1 ring-inset ring-n-weak bg-n-solid-1 min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="mudar('avisoDeSeguranca', !codigo.avisoDeSeguranca)"
    >
      <span
        class="grid mt-0.5 rounded-md place-items-center size-6 shrink-0 ring-1 ring-inset"
        :class="codigo.avisoDeSeguranca ? 'bg-n-brand ring-n-brand text-white' : 'ring-n-slate-7'"
        aria-hidden="true"
      >
        <span v-if="codigo.avisoDeSeguranca" class="i-lucide-check size-4" />
      </span>
      <span class="flex flex-col gap-0.5">
        <span class="text-[0.9375rem] font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.CODIGO.AVISO') }}
        </span>
        <span class="text-sm text-n-slate-11">{{ $t('MODELOS_WHATSAPP.FORMATOS.codigo.AVISO_FIXO') }}</span>
      </span>
    </button>

    <p class="flex gap-2 mb-0 text-sm text-n-slate-11">
      <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{ $t('MODELOS_WHATSAPP.CODIGO.SEM_EXTRAS') }}
    </p>
  </div>
</template>

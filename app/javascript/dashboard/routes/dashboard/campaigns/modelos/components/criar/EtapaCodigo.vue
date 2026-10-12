<script setup>
import { computed } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { VALIDADE_MAXIMA, VALIDADE_MINIMA } from '../../constants';

// Código de verificação: o texto é fixo do WhatsApp. A pessoa escolhe a
// validade e o aviso de segurança. Sem link, foto ou emoji.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const codigo = computed(() => rascunho.value.conteudo.codigo);
// O botão é sempre "Copiar código": "Preencher automaticamente" (ONE_TAP) pede o
// pacote e a assinatura do aplicativo Android da empresa, que o Chat2You ainda
// não guarda. Com uma opção só, a tela diz qual é em vez de pedir para escolher.

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
    !(
      codigo.value.validade >= VALIDADE_MINIMA &&
      codigo.value.validade <= VALIDADE_MAXIMA
    )
);
</script>

<template>
  <div data-etapa-codigo class="flex flex-col gap-6">
    <section class="flex flex-col gap-3">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.CODIGO.BOTAO') }}
      </h2>
      <p
        data-botao-codigo="copiar"
        class="flex items-start gap-3 p-4 mb-0 rounded-xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-10 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-copy size-5" aria-hidden="true" />
        </span>
        <span class="flex flex-col gap-0.5">
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.FORMATOS.codigo.BOTOES.copiar') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t('MODELOS_WHATSAPP.CODIGO.BOTOES_PARA.copiar') }}
          </span>
        </span>
      </p>
    </section>

    <Input
      wrap-message
      :model-value="codigo.validade"
      data-validade
      type="number"
      :min="String(VALIDADE_MINIMA)"
      :max="String(VALIDADE_MAXIMA)"
      :label="$t('MODELOS_WHATSAPP.CODIGO.VALIDADE')"
      :message="
        $t('MODELOS_WHATSAPP.CODIGO.VALIDADE_AJUDA', {
          min: VALIDADE_MINIMA,
          max: VALIDADE_MAXIMA,
        })
      "
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
        :class="
          codigo.avisoDeSeguranca
            ? 'bg-n-brand ring-n-brand text-white'
            : 'ring-n-slate-7'
        "
        aria-hidden="true"
      >
        <span v-if="codigo.avisoDeSeguranca" class="i-lucide-check size-4" />
      </span>
      <span class="flex flex-col gap-0.5">
        <span class="text-[0.9375rem] font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.CODIGO.AVISO') }}
        </span>
        <span class="text-sm text-n-slate-11">{{
          $t('MODELOS_WHATSAPP.FORMATOS.codigo.AVISO_FIXO')
        }}</span>
      </span>
    </button>

    <p class="flex gap-2 mb-0 text-sm text-n-slate-11">
      <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{ $t('MODELOS_WHATSAPP.CODIGO.SEM_EXTRAS') }}
    </p>
  </div>
</template>

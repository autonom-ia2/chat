<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDaFonte from './SeloDaFonte.vue';

// #2472: a chave da OpenAI da conta. A chave nunca volta para a tela: só os
// quatro últimos caracteres, para o dono reconhecer qual é.
const props = defineProps({
  fonte: { type: Object, default: null },
  // Com o ChatGPT funcionando, a chave fica de reserva: "Esperando a vez".
  esperandoAVez: { type: Boolean, default: false },
});

const emit = defineEmits(['colar', 'conferir', 'remover']);

const CREDITO_NA_OPENAI = 'https://platform.openai.com/settings/organization/billing';

const semCredito = computed(() => props.fonte?.status === 'sem_credito');
const status = computed(() =>
  props.fonte?.status === 'funcionando' && props.esperandoAVez
    ? 'reserva'
    : props.fonte?.status
);
</script>

<template>
  <article
    data-cartao-chave
    class="flex flex-col gap-5 p-6 rounded-3xl bg-n-solid-1 ring-1 ring-inset ring-n-weak md:p-8"
  >
    <div class="flex items-start gap-4">
      <span
        class="grid rounded-2xl place-items-center size-12 shrink-0 bg-n-blue-3 text-n-blue-11"
      >
        <span class="i-lucide-key-round size-6" aria-hidden="true" />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ $t('IA_DA_CONTA.CHAVE.TITULO') }}
        </h2>
        <p class="mb-0 text-base text-n-slate-11">
          {{ $t('IA_DA_CONTA.CHAVE.TEXTO') }}
        </p>
      </div>
    </div>

    <template v-if="fonte">
      <div class="flex flex-wrap items-center gap-3">
        <SeloDaFonte :status="status" />
        <span class="text-sm text-n-slate-11">
          {{ $t('IA_DA_CONTA.CHAVE.FINAL', { fim: fonte.fim }) }}
        </span>
      </div>
      <div class="flex flex-wrap gap-3 mt-auto">
        <template v-if="semCredito">
          <a
            data-por-credito
            :href="CREDITO_NA_OPENAI"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-2 px-4 text-sm font-medium text-white rounded-xl min-h-11 bg-n-brand hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          >
            {{ $t('IA_DA_CONTA.CHAVE.POR_CREDITO') }}
            <span class="i-lucide-external-link size-4" aria-hidden="true" />
          </a>
          <Button
            data-ja-coloquei
            :label="$t('IA_DA_CONTA.CHAVE.JA_COLOQUEI')"
            variant="outline"
            color="slate"
            size="lg"
            @click="emit('conferir')"
          />
        </template>
        <Button
          v-else
          data-trocar-chave
          :label="$t('IA_DA_CONTA.CHAVE.TROCAR')"
          variant="outline"
          color="slate"
          size="lg"
          @click="emit('colar')"
        />
        <Button
          data-remover-chave
          :label="$t('IA_DA_CONTA.CHAVE.REMOVER')"
          variant="ghost"
          color="slate"
          size="lg"
          @click="emit('remover')"
        />
      </div>
    </template>

    <Button
      v-else
      data-colar-chave
      class="mt-auto"
      :label="$t('IA_DA_CONTA.CHAVE.BOTAO')"
      icon="i-lucide-clipboard-paste"
      size="lg"
      @click="emit('colar')"
    />
  </article>
</template>

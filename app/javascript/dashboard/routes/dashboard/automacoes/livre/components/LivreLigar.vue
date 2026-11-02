<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { falta as faltaNaReceita } from '../receita';

// #2414 F5 — a ação principal da tela: ligar. Desligada, um botão grande; ligada,
// a confirmação e "Desligar" (sempre funciona). Sem gatilho ou sem passo, o botão
// diz o que falta. A nova ainda pode ser guardada sem ligar.
const props = defineProps({
  ativa: { type: Boolean, default: false },
  receita: { type: Object, required: true },
  nova: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});

const emit = defineEmits(['ligar', 'desligar', 'guardar']);

const { t } = useI18n();

const falta = computed(() => {
  const chave = faltaNaReceita(props.receita);
  return chave ? t(`AUTOMACAO_LIVRE.LIGAR.FALTA_${chave}`) : '';
});
</script>

<template>
  <div
    v-if="!podeMudar"
    data-so-leitura
    class="p-4 text-[0.9375rem] rounded-2xl bg-n-alpha-1 text-n-slate-11"
  >
    {{ $t('AUTOMACAO_LIVRE.LIGAR.SO_LEITURA') }}
  </div>

  <div v-else-if="!ativa" data-desligada class="flex flex-col gap-2.5">
    <Button
      data-ligar
      :label="$t('AUTOMACAO_LIVRE.LIGAR.BOTAO')"
      icon="i-lucide-power"
      teal
      size="lg"
      justify="center"
      class="w-full !min-h-14 !text-lg !font-bold !rounded-2xl shadow-lg"
      :disabled="Boolean(falta) || ocupado"
      @click="emit('ligar')"
    />
    <p class="mb-0 text-sm text-center text-n-slate-11">
      {{ falta || $t('AUTOMACAO_LIVRE.LIGAR.DESLIGADA') }}
    </p>
    <Button
      v-if="nova"
      data-guardar
      :label="$t('AUTOMACAO_LIVRE.LIGAR.GUARDAR')"
      link
      slate
      class="self-center min-h-11"
      :disabled="Boolean(falta) || ocupado"
      @click="emit('guardar')"
    />
  </div>

  <div
    v-else
    data-ligada
    role="status"
    class="flex flex-col gap-3 p-5 rounded-2xl bg-n-teal-3"
  >
    <div class="flex items-center gap-4">
      <span
        class="grid text-white rounded-full place-items-center size-10 shrink-0 bg-n-teal-10"
      >
        <span class="i-lucide-check size-5" aria-hidden="true" />
      </span>
      <div class="flex-1 min-w-0">
        <p class="mb-0 text-base font-semibold text-n-teal-12">
          {{ $t('AUTOMACAO_LIVRE.LIGADA') }}
        </p>
        <p class="mb-0 text-[0.9375rem] text-n-teal-11">
          {{ $t('AUTOMACAO_LIVRE.LIGAR.LIGADA_AVISO') }}
        </p>
      </div>
    </div>
    <Button
      data-desligar
      :label="$t('AUTOMACAO_LIVRE.LIGAR.DESLIGAR')"
      teal
      link
      class="self-start min-h-11 !font-semibold"
      :disabled="ocupado"
      @click="emit('desligar')"
    />
  </div>
</template>

<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2896, Fatia 2 — a moldura de todo cartão aberto de "Precisam de você": a
// frase do problema, a linha da planilha, o conserto (o que cada cartão põe no
// meio), a frase de erro como alerta e as ações. "Salvar" só existe no cartão
// que tem campo (`comSalvar`); "Deixar de fora" existe em todos.
defineProps({
  linha: { type: Number, required: true },
  // { texto, apoio, naPlanilha }: o problema, a linha da planilha e, quando há,
  // o valor como está nela.
  frases: { type: Object, required: true },
  erro: { type: String, default: '' },
  idDoErro: { type: String, required: true },
  comSalvar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar', 'deixarDeFora']);

const { t } = useI18n();
</script>

<template>
  <form class="flex flex-col gap-4" novalidate @submit.prevent="emit('salvar')">
    <div class="flex flex-col gap-1">
      <p class="m-0 text-lg font-semibold text-n-slate-12">
        {{ frases.texto }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">{{ frases.apoio }}</p>
      <p v-if="frases.naPlanilha" class="m-0 text-sm text-n-slate-11">
        {{ frases.naPlanilha }}
      </p>
    </div>
    <slot />
    <p
      v-if="erro"
      :id="idDoErro"
      data-relacionamentos="erro-do-campo"
      role="alert"
      class="m-0 text-sm font-medium text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        v-if="comSalvar"
        type="submit"
        size="lg"
        :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.GUARDAR')"
        :disabled="ocupado"
      />
      <Button
        slate
        faded
        type="button"
        size="lg"
        data-relacionamentos="deixar-de-fora"
        :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.DEIXAR_DE_FORA')"
        :disabled="ocupado"
        @click="emit('deixarDeFora', linha)"
      />
    </div>
  </form>
</template>

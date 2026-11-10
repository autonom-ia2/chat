<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreDuracao from './LivreDuracao.vue';
import { HORA_DA_CONFERENCIA, SEM_PRAZO } from '../receita';

// #2750 — o prazo do "Esperar até": até um prazo (quanto tempo) ou sem prazo,
// quando a espera só termina pela condição. A escolha é explícita: o passo
// nasce com prazo, e "Sem prazo" é uma opção da lista, nunca um número alto.
//
// G64 (#2839): sem prazo, a hora da conferência diária (`conferir_as`, no fuso
// da conta). Escolher "Sem prazo" já marca 8h (decisão 12 do Rodrigo, 09/11);
// "Assim que mudar" tira a hora e volta a conferir a cada mudança, como antes.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: [Object, String], default: null },
  conferirAs: { type: Number, default: null },
  unidades: { type: Array, required: true },
  // O passo já tem passos em "Se o prazo acabar": sem prazo, eles nunca
  // rodariam, e o "Salvar" espera a pessoa tirá-los.
  temSeVencer: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'update:conferirAs']);

const { t } = useI18n();

const COM = 'com_prazo';
const AO_MUDAR = 'ao_mudar';
const HORAS = Array.from({ length: 24 }, (_, hora) => hora);
const semPrazo = computed(() => props.modelValue === SEM_PRAZO);
// Volta para o último prazo escrito quando a pessoa desfaz o "Sem prazo".
const ultimo = ref(
  semPrazo.value ? { valor: 1, unidade: 'dias' } : props.modelValue
);

const opcoes = computed(() => [
  { value: COM, label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.COM_PRAZO') },
  { value: SEM_PRAZO, label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO') },
]);

const opcoesDaConferencia = computed(() => [
  {
    value: AO_MUDAR,
    label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR_AO_MUDAR'),
  },
  ...HORAS.map(hora => ({
    value: hora,
    label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR_AS_HORA', { hora }),
  })),
]);

const escolher = novo => {
  emit(
    'update:modelValue',
    novo === SEM_PRAZO
      ? SEM_PRAZO
      : ultimo.value || { valor: 1, unidade: 'dias' }
  );
  emit('update:conferirAs', novo === SEM_PRAZO ? HORA_DA_CONFERENCIA : null);
};

const escolherConferencia = novo =>
  emit('update:conferirAs', novo === AO_MUDAR ? null : novo);

const mudarDuracao = novo => {
  ultimo.value = novo;
  emit('update:modelValue', novo);
};
</script>

<template>
  <div class="flex flex-col gap-3" data-peca="prazo">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <ChoiceSelect
        :model-value="semPrazo ? SEM_PRAZO : COM"
        :aria-label="rotulo"
        :options="opcoes"
        @update:model-value="escolher"
      />
    </div>
    <LivreDuracao
      v-if="!semPrazo"
      :rotulo="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.QUANTO_TEMPO')"
      :model-value="modelValue"
      :unidades="unidades"
      @update:model-value="mudarDuracao"
    />
    <template v-else>
      <p class="mb-0 text-sm text-n-slate-11" data-sem-prazo-dica>
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO_DICA') }}
      </p>
      <div class="flex flex-col gap-1.5" data-conferir-as>
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR') }}
        </span>
        <ChoiceSelect
          :model-value="conferirAs ?? AO_MUDAR"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR')"
          :options="opcoesDaConferencia"
          @update:model-value="escolherConferencia"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            conferirAs === null
              ? $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR_AO_MUDAR_DICA')
              : $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONFERIR_AS_DICA', {
                  hora: conferirAs,
                })
          }}
        </p>
      </div>
      <p
        v-if="temSeVencer"
        class="mb-0 text-sm text-n-ruby-11"
        data-sem-prazo-se-vencer
      >
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO_TIRE_SE_VENCER') }}
      </p>
    </template>
  </div>
</template>

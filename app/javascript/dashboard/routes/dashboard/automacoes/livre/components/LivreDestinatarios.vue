<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';
import LivreMarcar from './LivreMarcar.vue';

// #2486 — quem o "avisar" chama: quem cuida da conversa, times e pessoas. O
// motor confere, na hora, quem enxerga a conversa; aqui só se escolhe.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: () => ({}) },
  opcoes: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);

// Lista vazia sai da receita: o esquema pede só o que foi escolhido.
const mudar = (chave, valor) => {
  const { [chave]: _antes, ...resto } = props.modelValue || {};
  const vazio = valor === false || (Array.isArray(valor) && !valor.length);
  emit('update:modelValue', vazio ? resto : { ...resto, [chave]: valor });
};

// #2552 — a reserva da caixa só vale junto do responsável: desligar o
// responsável tira a reserva também.
const mudarResponsavel = valor => {
  if (valor) {
    mudar('responsavel', true);
    return;
  }
  const {
    responsavel: _r,
    se_nao_houver: _s,
    ...resto
  } = props.modelValue || {};
  emit('update:modelValue', resto);
};
const mudarReserva = valor => mudar('se_nao_houver', valor ? 'caixa' : false);
</script>

<template>
  <fieldset class="flex flex-col gap-4" data-peca="destinatarios">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <label
      class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
    >
      <span class="text-[0.9375rem] text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.RESPONSAVEL') }}
      </span>
      <Switch
        data-responsavel
        class="mx-1.5 scale-[1.4]"
        :model-value="Boolean(modelValue?.responsavel)"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.RESPONSAVEL')"
        @update:model-value="mudarResponsavel"
      />
    </label>
    <label
      v-if="modelValue?.responsavel"
      class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
    >
      <span class="text-[0.9375rem] text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.RESERVA_CAIXA') }}
      </span>
      <Switch
        data-reserva-caixa
        class="mx-1.5 scale-[1.4]"
        :model-value="modelValue?.se_nao_houver === 'caixa'"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.RESERVA_CAIXA')"
        @update:model-value="mudarReserva"
      />
    </label>
    <LivreMarcar
      data-times
      :rotulo="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIMES')"
      :opcoes="opcoes.time"
      :model-value="modelValue?.times || []"
      @update:model-value="valor => mudar('times', valor)"
    />
    <LivreMarcar
      data-pessoas
      :rotulo="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.PESSOAS')"
      :opcoes="opcoes.pessoa"
      :model-value="modelValue?.pessoas || []"
      @update:model-value="valor => mudar('pessoas', valor)"
    />
    <p class="mb-0 text-sm text-n-slate-11">
      {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SO_A_EQUIPE') }}
    </p>
  </fieldset>
</template>

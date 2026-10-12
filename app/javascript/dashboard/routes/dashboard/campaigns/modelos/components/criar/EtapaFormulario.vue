<script setup>
import { computed } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  formularios: { type: Array, required: true },
});

// Botão de formulário: a pessoa escolhe um formulário que já existe na conta
// do WhatsApp. Criar formulário é de outra tela (outro épico); sem nenhum, uma
// frase.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const formulario = computed(() => rascunho.value.conteudo.formulario);
const opcoes = computed(() =>
  props.formularios.map(item => ({ value: item.id, label: item.nome }))
);

const mudar = (campo, valor) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...rascunho.value.conteudo,
      formulario: { ...formulario.value, [campo]: valor },
    },
  };
};

const escolhido = computed({
  get: () => formulario.value.id,
  set: valor => mudar('id', valor),
});
</script>

<template>
  <div data-etapa-formulario class="flex flex-col gap-6">
    <p
      v-if="!formularios.length"
      data-sem-formulario
      class="p-6 mb-0 text-base rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
    >
      {{ $t('MODELOS_WHATSAPP.FORMULARIO.SEM_FORMULARIO') }}
    </p>
    <template v-else>
      <p class="mb-0 text-base text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.FORMULARIO.INTRO') }}
      </p>
      <div class="flex flex-col gap-2">
        <label
          for="modelo-formulario"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ $t('MODELOS_WHATSAPP.FORMULARIO.QUAL') }}
        </label>
        <ChoiceSelect
          v-model="escolhido"
          data-escolher-formulario
          trigger-id="modelo-formulario"
          :options="opcoes"
          :placeholder="$t('MODELOS_WHATSAPP.FORMULARIO.ESCOLHA')"
          :aria-label="$t('MODELOS_WHATSAPP.FORMULARIO.QUAL')"
        />
      </div>
      <Input
        :model-value="formulario.botao"
        :label="$t('MODELOS_WHATSAPP.EXTRAS.TEXTO_DO_BOTAO')"
        @update:model-value="valor => mudar('botao', valor)"
      />
    </template>
  </div>
</template>

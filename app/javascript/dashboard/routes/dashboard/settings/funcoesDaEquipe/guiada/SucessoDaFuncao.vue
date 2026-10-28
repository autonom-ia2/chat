<script setup>
import BotaoGrande from './BotaoGrande.vue';

// Sucesso (#2308, especificação 5.B5): a função foi criada e a próxima pergunta é quem vai tê-la. Sem poder pôr
// pessoas, só o aviso: o voltar do alto ("Voltar para a lista") é o único caminho, sem dois botões iguais.
defineProps({
  nome: { type: String, required: true },
  podeEscolherPessoas: { type: Boolean, default: false },
});

const emit = defineEmits(['escolherPessoas']);
</script>

<template>
  <div data-sucesso class="flex flex-col gap-5">
    <p
      role="status"
      class="flex items-center gap-2 m-0 font-semibold text-n-teal-11"
    >
      <span class="i-lucide-circle-check size-5" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.SUCESSO.CRIADA', { nome }) }}
    </p>
    <template v-if="podeEscolherPessoas">
      <h1
        class="m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
      >
        {{ $t('FUNCOES_EQUIPE.SUCESSO.QUEM', { nome }) }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t('FUNCOES_EQUIPE.SUCESSO.DICA') }}
      </p>
      <BotaoGrande
        :label="$t('FUNCOES_EQUIPE.SUCESSO.ESCOLHER')"
        @click="emit('escolherPessoas')"
      />
    </template>
  </div>
</template>

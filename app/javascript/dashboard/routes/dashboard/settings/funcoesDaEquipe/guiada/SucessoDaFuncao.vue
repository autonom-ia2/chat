<script setup>
import { nextTick, onMounted, ref } from 'vue';
import BotaoGrande from './BotaoGrande.vue';

// Sucesso (#2308, especificação 5.B5): a função foi criada e a próxima pergunta é quem vai tê-la. Sem poder pôr
// pessoas, o título é a própria criação, o texto diz quem põe e o botão grande volta para a lista (o alto não repete
// esse caminho). Sempre há um h1: a página leva o foco para ele ao trocar de etapa.
defineProps({
  nome: { type: String, required: true },
  podeEscolherPessoas: { type: Boolean, default: false },
});

const emit = defineEmits(['escolherPessoas', 'voltar']);

// Um role=status que já nasce com o texto não é anunciado: o "criada" entra depois de montar, enquanto o foco vai
// para o h1 (revisão do #2308, rodada 4).
const anunciar = ref(false);
onMounted(async () => {
  await nextTick();
  anunciar.value = true;
});
</script>

<template>
  <div data-sucesso class="flex flex-col gap-5">
    <template v-if="podeEscolherPessoas">
      <p
        role="status"
        class="flex items-center gap-2 m-0 font-semibold min-h-6 text-n-teal-11"
      >
        <template v-if="anunciar">
          <span class="i-lucide-circle-check size-5" aria-hidden="true" />
          {{ $t('FUNCOES_EQUIPE.SUCESSO.CRIADA', { nome }) }}
        </template>
      </p>
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
    <template v-else>
      <h1
        class="flex items-center gap-3 m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
      >
        <span
          class="i-lucide-circle-check size-7 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        {{ $t('FUNCOES_EQUIPE.SUCESSO.CRIADA', { nome }) }}
      </h1>
      <p data-sem-pessoas class="m-0 text-base text-n-slate-11">
        {{ $t('FUNCOES_EQUIPE.SUCESSO.PECA_AO_ADMIN') }}
      </p>
      <BotaoGrande
        data-voltar-lista
        :label="$t('FUNCOES_EQUIPE.GUIADA.VOLTAR_LISTA')"
        @click="emit('voltar')"
      />
    </template>
  </div>
</template>

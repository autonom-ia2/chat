<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import { ERROS } from '../../trazer/useTrazerLista';
import SoltarArquivo from './SoltarArquivo.vue';

// #2894 — "Enviar": o título, a área de soltar a planilha, o link da planilha
// de exemplo (só em demonstração) e os estados de lendo e erro.
const props = defineProps({
  lendo: { type: Boolean, default: false },
  erro: { type: String, default: '' },
  mostrarExemplo: { type: Boolean, default: false },
  // #2897 — outra linha de apoio na área de soltar (conta de seguros).
  apoio: { type: String, default: '' },
});
const emit = defineEmits(['arquivo', 'exemplo', 'tentar']);

const { t } = useI18n();

// O que está errado com o arquivo (não com a leitura): a frase vai embaixo da
// área de soltar.
const ERROS_DO_ARQUIVO = {
  [ERROS.TIPO]: 'RELACIONAMENTOS_TRAZER.ENVIAR.ERRO_TIPO',
  [ERROS.VAZIA]: 'RELACIONAMENTOS_TRAZER.ENVIAR.ERRO_VAZIA',
  [ERROS.SEM_CONTATO]: 'RELACIONAMENTOS_TRAZER.ENVIAR.ERRO_SEM_CONTATO',
};
const erroDoArquivo = computed(() =>
  ERROS_DO_ARQUIVO[props.erro] ? t(ERROS_DO_ARQUIVO[props.erro]) : ''
);
</script>

<template>
  <section data-relacionamentos="enviar" class="flex flex-col gap-6">
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ t('RELACIONAMENTOS_TRAZER.TITULO') }}
    </h1>

    <div
      v-if="lendo"
      data-relacionamentos="carregando"
      role="status"
      aria-busy="true"
      class="flex flex-col gap-4 p-8 border rounded-3xl border-n-weak bg-n-solid-1"
    >
      <p
        data-relacionamentos="lendo-planilha"
        class="m-0 text-lg text-n-slate-12"
      >
        {{ t('RELACIONAMENTOS_TRAZER.ENVIAR.LENDO') }}
      </p>
      <div
        v-for="linha in 3"
        :key="linha"
        aria-hidden="true"
        class="h-12 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
    </div>

    <template v-else>
      <div v-if="erro === ERROS.LEITURA" data-relacionamentos="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ENVIAR.ERRO_LEITURA')"
          @tentar="emit('tentar')"
        />
      </div>
      <SoltarArquivo
        :erro="erroDoArquivo"
        :tipo-de-erro="erro"
        :apoio="apoio"
        @arquivo="emit('arquivo', $event)"
      />
      <button
        v-if="mostrarExemplo"
        type="button"
        data-relacionamentos="usar-exemplo"
        class="self-start p-0 text-sm bg-transparent border-0 underline min-h-11 rounded-lg text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('exemplo')"
      >
        {{ t('RELACIONAMENTOS_TRAZER.ENVIAR.USAR_EXEMPLO') }}
      </button>
    </template>
  </section>
</template>

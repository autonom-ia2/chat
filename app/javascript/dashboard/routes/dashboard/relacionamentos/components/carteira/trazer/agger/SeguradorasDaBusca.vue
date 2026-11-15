<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';

// #2900 (E7.3) — os avisos de cada seguradora da busca no Agger, em palavras
// simples e com o que fazer. A seguradora que respondeu (ou ainda está
// respondendo) não ganha aviso. A que pediu login de novo e a que não tem o
// login guardado no Agger dizem o que a pessoa faz lá; a que não respondeu
// agora tem "Tentar de novo". Seguradora sem nome é "uma seguradora" (a frase
// sem nome é outra, para a frase continuar certa).
const props = defineProps({
  // [{ nome, situacao }]
  seguradoras: { type: Array, default: () => [] },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['tentar']);

const { t } = useI18n();
const id = useId();
// As frases de cada situação que tem aviso, com as chaves escritas por inteiro.
const TEXTOS = {
  pede_login: {
    frase: nome =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.PEDE_LOGIN.FRASE', { nome }),
    semNome: () =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.PEDE_LOGIN.FRASE_SEM_NOME'),
    fazer: () =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.PEDE_LOGIN.FAZER'),
  },
  sem_login: {
    frase: nome =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.SEM_LOGIN.FRASE', { nome }),
    semNome: () =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.SEM_LOGIN.FRASE_SEM_NOME'),
    fazer: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.SEM_LOGIN.FAZER'),
  },
  falhou: {
    frase: nome =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.FALHOU.FRASE', { nome }),
    semNome: () =>
      t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.FALHOU.FRASE_SEM_NOME'),
    fazer: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.FALHOU.FAZER'),
  },
};

const avisos = computed(() =>
  props.seguradoras
    .filter(seguradora => TEXTOS[seguradora.situacao])
    .map((seguradora, indice) => ({
      chave: `${id}-${indice}`,
      situacao: seguradora.situacao,
      frase: seguradora.nome
        ? TEXTOS[seguradora.situacao].frase(seguradora.nome)
        : TEXTOS[seguradora.situacao].semNome(),
      fazer: TEXTOS[seguradora.situacao].fazer(),
    }))
);
</script>

<template>
  <ul
    data-carteira="seguradoras-da-busca"
    class="flex flex-col gap-3 p-0 m-0 list-none"
    :class="{ hidden: !avisos.length }"
  >
    <li
      v-for="aviso in avisos"
      :key="aviso.chave"
      :data-situacao="aviso.situacao"
      class="flex flex-col gap-2 p-4 border rounded-2xl border-n-amber-6 bg-n-amber-2"
    >
      <span :id="aviso.chave" class="text-base font-medium text-n-slate-12">
        {{ aviso.frase }}
      </span>
      <span class="text-sm text-n-slate-11">{{ aviso.fazer }}</span>
      <button
        v-if="aviso.situacao === 'falhou'"
        type="button"
        data-carteira="tentar-seguradora"
        class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-describedby="aviso.chave"
        :aria-busy="ocupado"
        @click="emit('tentar')"
      >
        {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORA.TENTAR') }}
      </button>
    </li>
  </ul>
</template>

<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  SITUACOES_COM_AVISO,
  comAviso,
} from '../../../../carteira/avisosDasSeguradoras';

// #2900 (E7.3, E7.5) — o que houve com as seguradoras na busca no Agger, numa
// linha calma: "O Agger não buscou seguros novos em 13 seguradoras agora. Os
// que já estavam no Agger vieram." O detalhe fica atrás de "Ver quais", em
// grupos por situação, cada grupo com os nomes e uma frase do que fazer; o
// grupo das que não responderam tem "Tentar de novo". Seguradora sem nome
// entra como "uma seguradora" (ou "mais uma", depois das que têm nome). Tudo
// bem com todas: nada aparece.
//
// `nadaVeio`: a busca não trouxe nenhum seguro e todas as seguradoras ficaram
// com aviso. A linha vira a frase do que fazer, sem culpar ninguém.
const props = defineProps({
  // [{ nome, situacao }]
  seguradoras: { type: Array, default: () => [] },
  nadaVeio: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['tentar']);

const { t, locale } = useI18n();
const id = useId();
const aberto = ref(false);
// A frase de cada grupo, com as chaves escritas por inteiro.
const FAZER = {
  pede_login: quantas =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.PEDE_LOGIN',
      { count: quantas },
      quantas
    ),
  sem_login: quantas =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.SEM_LOGIN',
      { count: quantas },
      quantas
    ),
  falhou: quantas =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.FALHOU',
      { count: quantas },
      quantas
    ),
};

const avisos = computed(() => comAviso(props.seguradoras));

// "A, B e mais uma seguradora", no jeito de juntar nomes da língua da tela.
const juntar = nomes =>
  new Intl.ListFormat(locale.value.replace('_', '-'), {
    style: 'long',
    type: 'conjunction',
  }).format(nomes);

const nomesDoGrupo = seguradoras => {
  const nomes = seguradoras
    .map(seguradora => seguradora.nome)
    .filter(nome => nome);
  const semNome = seguradoras.length - nomes.length;
  if (!semNome) return juntar(nomes);
  const semNomes = nomes.length
    ? t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.MAIS',
        { count: semNome },
        semNome
      )
    : t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.UMA',
        { count: semNome },
        semNome
      );
  return juntar([...nomes, semNomes]);
};

const grupos = computed(() =>
  SITUACOES_COM_AVISO.map(situacao => {
    const doGrupo = avisos.value.filter(
      seguradora => seguradora.situacao === situacao
    );
    return {
      situacao,
      chave: `${id}-${situacao}`,
      quantas: doGrupo.length,
      nomes: doGrupo.length ? nomesDoGrupo(doGrupo) : '',
      fazer: doGrupo.length ? FAZER[situacao](doGrupo.length) : '',
    };
  }).filter(grupo => grupo.quantas)
);

const frase = computed(() =>
  props.nadaVeio
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.NADA_VEIO')
    : t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.LINHA',
        { count: avisos.value.length },
        avisos.value.length
      )
);
</script>

<template>
  <section
    v-if="avisos.length"
    data-carteira="seguradoras-da-busca"
    :aria-labelledby="`${id}-frase`"
    class="flex flex-col gap-3 px-4 py-3 rounded-2xl bg-n-alpha-1"
  >
    <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
      <p
        :id="`${id}-frase`"
        data-carteira="frase-das-seguradoras"
        class="flex-1 m-0 text-base text-n-slate-11 text-pretty"
      >
        {{ frase }}
      </p>
      <button
        type="button"
        data-carteira="ver-quais"
        class="self-start px-4 text-sm font-medium border rounded-xl sm:self-center shrink-0 min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="aberto ? 'true' : 'false'"
        :aria-controls="`${id}-grupos`"
        @click="aberto = !aberto"
      >
        {{
          aberto
            ? t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.ESCONDER')
            : t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.VER_QUAIS')
        }}
      </button>
    </div>
    <ul
      v-show="aberto"
      :id="`${id}-grupos`"
      data-carteira="grupos-das-seguradoras"
      class="flex flex-col gap-4 p-0 pt-3 m-0 list-none border-t border-n-weak"
    >
      <li
        v-for="grupo in grupos"
        :key="grupo.chave"
        :data-situacao="grupo.situacao"
        class="flex flex-col gap-1"
      >
        <span
          data-carteira="nomes-do-grupo"
          class="text-base font-medium text-n-slate-12 text-pretty"
        >
          {{ grupo.nomes }}
        </span>
        <span :id="grupo.chave" class="text-sm text-n-slate-11 text-pretty">
          {{ grupo.fazer }}
        </span>
        <button
          v-if="grupo.situacao === 'falhou'"
          type="button"
          data-carteira="tentar-seguradora"
          class="self-start px-4 mt-1 text-sm font-medium border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-describedby="grupo.chave"
          :aria-busy="ocupado ? 'true' : 'false'"
          @click="emit('tentar')"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.SEGURADORAS.TENTAR') }}
        </button>
      </li>
    </ul>
  </section>
</template>

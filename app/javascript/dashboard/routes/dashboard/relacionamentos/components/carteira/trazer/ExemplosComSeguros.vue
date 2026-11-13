<script setup>
import { useI18n } from 'vue-i18n';
import { doCampoDeData } from '../../../carteira/formatosDoSeguro';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import FichaDeExemplo from '../../trazer/FichaDeExemplo.vue';

// #2897 — as fichas de exemplo do Conferir da planilha com seguros: a pessoa,
// como na tela das listas, e embaixo os seguros que entram com ela. O tipo de
// cada seguro já vem decidido; o que não coube em nenhum tipo aparece como
// "Outro", com o nome que estava na planilha.
defineProps({
  exemplos: { type: Array, required: true },
});

const { t } = useI18n();
const textos = useTextosDoSeguro();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR';
const TIPO_OUTRO = 'outro';

const titulo = seguro =>
  t(`${BASE}.SEGURO`, {
    tipo: textos.tipo(seguro),
    seguradora: seguro.seguradora,
  });

const termina = seguro => {
  const segundos = doCampoDeData(seguro.termina);
  return segundos === null
    ? ''
    : t(`${BASE}.TERMINA_EM`, { data: textos.dataInteira(segundos) });
};

const temValor = seguro => seguro.valor !== null && seguro.valor !== undefined;

// O que cada seguro mostra abaixo do título. Só entra o que ele tem.
const detalhesDo = seguro =>
  [
    textos.numero(seguro),
    termina(seguro),
    temValor(seguro) ? textos.valor(seguro.valor) : '',
    seguro.bem ?? '',
    seguro.tipo === TIPO_OUTRO && seguro.ramoOriginal
      ? t(`${BASE}.RAMO`, { ramo: seguro.ramoOriginal })
      : '',
  ].filter(Boolean);
</script>

<template>
  <section data-carteira="exemplos-com-seguros" class="flex flex-col gap-4">
    <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
      {{ t(`${BASE}.EXEMPLOS`) }}
    </h2>
    <div class="grid gap-3 md:grid-cols-3">
      <FichaDeExemplo
        v-for="(pessoa, posicao) in exemplos"
        :key="posicao"
        :pessoa="pessoa"
      >
        <ul
          v-if="pessoa.seguros?.length"
          data-carteira="seguros-do-exemplo"
          :aria-label="t(`${BASE}.SEGUROS_DE`, { nome: pessoa.nome })"
          class="flex flex-col gap-3 p-0 pt-4 m-0 list-none border-t border-n-weak"
        >
          <li
            v-for="(seguro, indice) in pessoa.seguros"
            :key="indice"
            class="flex flex-col min-w-0 gap-1"
          >
            <span class="text-sm font-semibold break-words text-n-slate-12">
              {{ titulo(seguro) }}
            </span>
            <span
              v-for="detalhe in detalhesDo(seguro)"
              :key="detalhe"
              class="text-sm break-words text-n-slate-11 tabular-nums"
            >
              {{ detalhe }}
            </span>
          </li>
        </ul>
      </FichaDeExemplo>
    </div>
  </section>
</template>

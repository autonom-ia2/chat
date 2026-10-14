<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PreviaColunas from './PreviaColunas.vue';
import {
  ETAPA_DESLIGADA,
  ETAPA_IGUAL,
  ETAPA_PROPRIA,
  MAX_PROPRIAS_UMA_A_UMA,
  juntarNomes,
  textoDoJeito,
} from '../passagem';

// #1385 — na tela de etapas, a prévia mostra o quadro em miniatura (PreviaColunas, que rola para o lado com mais de
// cinco etapas, como o quadro do funil) e o que acontece se a Ana pedir uma pessoa.
const props = defineProps({
  nome: { type: String, default: '' },
  etapas: { type: Array, required: true },
  regra: { type: Object, required: true },
  pessoas: { type: Array, default: () => [] },
});

const { t, locale } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';

const COR = {
  PASSA: 'i-lucide-users text-n-teal-11',
  PROPRIA: 'i-lucide-sparkles text-n-blue-11',
  NAO: 'i-lucide-bot text-n-slate-11',
};

const nomes = lista =>
  juntarNomes(
    lista.map(etapa => etapa.nome),
    locale.value
  );

// Cada etapa do seu jeito numa linha; com muitas, uma linha só com os nomes (o jeito de cada uma fica na lista).
const linhasDasProprias = proprias => {
  if (proprias.length > MAX_PROPRIAS_UMA_A_UMA) {
    return [
      {
        chave: 'proprias',
        tom: 'PROPRIA',
        texto: t(`${P}.PERCURSO_PROPRIAS`, { etapas: nomes(proprias) }),
      },
    ];
  }
  return proprias.map(etapa => ({
    chave: `p-${etapa.id}`,
    tom: 'PROPRIA',
    texto: t(`${P}.PERCURSO_PROPRIA`, {
      etapa: etapa.nome,
      jeito: textoDoJeito(t, etapa.regra, props.pessoas, 'FRASE'),
    }),
  }));
};

// Os fatos, agrupados: as etapas do seu jeito, as que não chamam juntas, e as demais numa linha só.
const percurso = computed(() => {
  const proprias = props.etapas.filter(etapa => etapa.modo === ETAPA_PROPRIA);
  const iguais = props.etapas.filter(etapa => etapa.modo === ETAPA_IGUAL);
  const caladas = props.etapas.filter(
    etapa =>
      etapa.modo === ETAPA_DESLIGADA ||
      (etapa.modo === ETAPA_IGUAL && !props.regra.enabled)
  );
  const linhas = linhasDasProprias(proprias);
  if (props.regra.enabled && iguais.length) {
    const todas = iguais.length === props.etapas.length;
    linhas.push({
      chave: 'outras',
      tom: 'PASSA',
      texto: t(`${P}.${todas ? 'PERCURSO_TODAS' : 'PERCURSO_OUTRAS'}`, {
        jeito: textoDoJeito(t, props.regra, props.pessoas, 'FRASE'),
      }),
    });
  }
  if (caladas.length) {
    linhas.push({
      chave: 'caladas',
      tom: 'NAO',
      texto: t(`${P}.PERCURSO_NAO`, { etapas: nomes(caladas) }),
    });
  }
  return linhas;
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <PreviaColunas
      :nome="nome"
      :etapas="etapas"
      :regra="regra"
      :pessoas="pessoas"
    />

    <section
      data-previa-percurso
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${P}.PERCURSO_TITULO`) }}
      </h3>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="linha in percurso"
          :key="linha.chave"
          class="flex items-start gap-2 rounded-xl bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
        >
          <span
            class="mt-0.5 size-4 shrink-0"
            :class="COR[linha.tom]"
            aria-hidden="true"
          />
          {{ linha.texto }}
        </li>
      </ul>
    </section>
  </div>
</template>

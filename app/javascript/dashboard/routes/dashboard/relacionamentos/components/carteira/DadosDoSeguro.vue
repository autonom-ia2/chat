<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import BotaoCopiar from '../ficha/BotaoCopiar.vue';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2897 — "Dados do seguro": a lista "nome: valor" da gaveta. O número da
// apólice fica à vista, com copiar. O que falta mostra "Não informado"; a linha
// "Na planilha estava como" (o tipo como veio escrito) só aparece quando há o
// que mostrar. De quem é o seguro fica no topo da gaveta (FraseDoSeguro.vue).
// "Como chegou" diz só de onde e quando: o nome do arquivo da planilha não
// aparece, porque costuma trazer nome de cliente ou CPF.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();
const textos = useTextosDoSeguro();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.DADOS.${chave}`, valores);
const idDoTitulo = useId();

const PLANILHA = 'planilha';

const origem = computed(() => {
  const { tipo, em } = props.seguro.origem;
  const data = textos.diaMes(em, props.agora);
  return td(tipo === PLANILHA ? 'POR_PLANILHA' : 'CHEGOU_EM', { data });
});

const dataOuNada = segundos =>
  segundos === null ? '' : textos.dataInteira(segundos);

const linhas = computed(() => {
  const { seguro } = props;
  return [
    { chave: 'tipo', valor: textos.tipo(seguro) },
    { chave: 'ramo', valor: seguro.ramoOriginal, soComValor: true },
    { chave: 'seguradora', valor: seguro.seguradora },
    { chave: 'numero', valor: seguro.numero, copiar: true, inteiro: true },
    { chave: 'comeca', valor: dataOuNada(seguro.comeca) },
    { chave: 'termina', valor: dataOuNada(seguro.termina) },
    {
      chave: 'valor',
      valor: seguro.valor === null ? '' : textos.valor(seguro.valor),
    },
    { chave: 'bem', valor: seguro.bem },
    { chave: 'origem', valor: origem.value },
  ]
    .filter(linha => linha.valor || !linha.soComValor)
    .map(linha => ({
      ...linha,
      valor: linha.valor ?? '',
      rotulo: td(linha.chave.toUpperCase()),
    }));
});
</script>

<template>
  <section
    data-carteira="dados-do-seguro"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-4"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ td('TITULO') }}
    </h3>
    <dl class="grid gap-4 m-0">
      <div
        v-for="linha in linhas"
        :key="linha.chave"
        :data-dado="linha.chave"
        class="flex items-center justify-between min-w-0 gap-3"
      >
        <div class="min-w-0">
          <dt class="text-sm text-n-slate-11">{{ linha.rotulo }}</dt>
          <dd
            class="flex flex-wrap items-center m-0 text-base break-words gap-x-2 gap-y-1 tabular-nums"
            :class="linha.valor ? 'text-n-slate-12' : 'text-n-slate-10'"
          >
            <span
              v-if="linha.inteiro && linha.valor"
              data-carteira="numero-da-apolice"
              class="whitespace-nowrap"
            >
              {{ linha.valor }}
            </span>
            <template v-else>
              {{ linha.valor || td('NAO_INFORMADO') }}
            </template>
          </dd>
        </div>
        <BotaoCopiar
          v-if="linha.copiar && linha.valor"
          :valor="linha.valor"
          :item="linha.rotulo"
        />
      </div>
    </dl>
  </section>
</template>

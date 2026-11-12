<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import BotaoCopiar from '../ficha/BotaoCopiar.vue';
import { formatarCnpj, formatarCpf } from '../../ficha/formatos';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2897 — "Dados do seguro": a lista "nome: valor" da gaveta. Número da apólice
// e documento ficam à vista, com copiar. O que chegou com dúvida mostra "Pode
// ter mudado" ao lado; o que falta mostra "Não informado". O nome do segurado
// leva à ficha.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrirSegurado']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.DADOS.${chave}`, valores);
const idDoTitulo = useId();

const origem = computed(() => {
  const { tipo, arquivo, em } = props.seguro.origem;
  const data = textos.diaMes(em, props.agora);
  return tipo === 'planilha'
    ? td('VEIO_DA_PLANILHA', { arquivo, data })
    : td('VEIO_DO_AGGER', { data });
});

const linhas = computed(() => {
  const { seguro } = props;
  const daEmpresa = seguro.segurado.tipo === 'empresa';
  const documento = (daEmpresa ? formatarCnpj : formatarCpf)(
    seguro.segurado.documento
  );
  return [
    { chave: 'tipo', valor: textos.tipo(seguro) },
    { chave: 'seguradora', valor: seguro.seguradora },
    { chave: 'numero', valor: seguro.numero, copiar: true, inteiro: true },
    { chave: 'comeca', valor: textos.dataInteira(seguro.comeca) },
    { chave: 'termina', valor: textos.dataInteira(seguro.termina) },
    {
      chave: 'valor',
      valor: seguro.valor
        ? td('VALOR_POR_PERIODO', {
            valor: textos.valor(seguro.valor),
            periodo: textos.periodo(seguro),
          })
        : '',
    },
    { chave: 'segurado', valor: seguro.segurado.nome, ficha: true },
    {
      chave: 'documento',
      rotulo: td(daEmpresa ? 'CNPJ' : 'CPF'),
      valor: documento,
      copiar: true,
    },
    { chave: 'bem', valor: seguro.bem },
    { chave: 'origem', valor: origem.value },
  ].map(linha => ({
    ...linha,
    rotulo: linha.rotulo ?? td(linha.chave.toUpperCase()),
    confira: seguro.duvidas?.includes(linha.chave) ?? false,
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
            <button
              v-if="linha.ficha"
              type="button"
              data-carteira="abrir-segurado"
              :aria-label="td('ABRIR_FICHA_DE', { nome: linha.valor })"
              class="p-0 text-base font-medium underline bg-transparent border-0 rounded-md min-h-11 text-start text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="emit('abrirSegurado', seguro.segurado)"
            >
              {{ linha.valor }}
            </button>
            <span
              v-else-if="linha.inteiro && linha.valor"
              data-carteira="numero-da-apolice"
              class="whitespace-nowrap"
            >
              {{ linha.valor }}
            </span>
            <template v-else>
              {{ linha.valor || td('NAO_INFORMADO') }}
            </template>
            <span
              v-if="linha.confira"
              data-carteira="confira"
              class="px-1.5 text-xs font-medium leading-5 rounded-md bg-n-amber-3 text-n-amber-11"
            >
              {{ td('PODE_TER_MUDADO') }}
            </span>
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

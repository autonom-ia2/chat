<script setup>
import { useI18n } from 'vue-i18n';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2897 — "O que mudou": só o que é diferente, em duas colunas (Antes e No
// PDF). A linha que alguém corrigiu à mão avisa que fica o valor da pessoa e
// oferece, só nela, "Usar o do PDF". `escolhidos` são os campos em que a pessoa
// já pediu o do PDF. A história usa a mesma tabela para mostrar um endosso.
//   linhas: [{ campo, antes, noPdf, corrigidoAMao? }]
defineProps({
  linhas: { type: Array, required: true },
  escolhidos: { type: Array, default: () => [] },
  // A marca do robô de print (a história usa outra, para não haver duas iguais).
  marca: { type: String, default: 'o-que-mudou' },
});
const emit = defineEmits(['usarDoPdf']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.PDF.${chave}`);
</script>

<template>
  <table
    :data-carteira="marca"
    class="w-full text-sm border-collapse table-fixed text-start"
  >
    <caption class="sr-only">
      {{
        tp('LEGENDA')
      }}
    </caption>
    <thead>
      <tr class="border-b border-n-weak text-n-slate-11">
        <th scope="col" class="py-2 font-medium text-start pe-2">
          <span class="sr-only">{{ tp('INFORMACAO') }}</span>
        </th>
        <th scope="col" class="py-2 font-medium text-start pe-2">
          {{ tp('ANTES') }}
        </th>
        <th scope="col" class="py-2 font-medium text-start">
          {{ tp('NO_PDF') }}
        </th>
      </tr>
    </thead>
    <tbody>
      <template v-for="linha in linhas" :key="linha.campo">
        <tr :data-mudanca="linha.campo" class="align-top text-n-slate-12">
          <th scope="row" class="py-2 font-medium break-words text-start pe-2">
            {{ tp(`CAMPOS.${linha.campo.toUpperCase()}`) }}
          </th>
          <td class="py-2 break-words tabular-nums pe-2">
            {{ textos.doCampo(linha.campo, linha.antes) }}
          </td>
          <td class="py-2 font-semibold break-words tabular-nums">
            {{ textos.doCampo(linha.campo, linha.noPdf) }}
          </td>
        </tr>
        <tr v-if="linha.corrigidoAMao" class="border-b border-n-weak/60">
          <td colspan="3" class="pb-3 text-n-slate-11">
            <span v-if="escolhidos.includes(linha.campo)">
              {{ tp('VAI_USAR_O_DO_PDF') }}
            </span>
            <span v-else class="flex flex-wrap items-center gap-x-3">
              {{ tp('CORRIGIU_A_MAO') }}
              <button
                type="button"
                data-carteira="usar-o-do-pdf"
                class="p-0 text-sm font-medium underline bg-transparent border-0 rounded-md min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                @click="emit('usarDoPdf', linha.campo)"
              >
                {{ tp('USAR_O_DO_PDF') }}
              </button>
            </span>
          </td>
        </tr>
      </template>
    </tbody>
  </table>
</template>

<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2899 (E6.2) — "O que mudou": só o que o PDF diz de diferente do seguro
// guardado, em duas colunas (Guardado e No PDF). Cada linha tem "Usar o do
// PDF", que liga e desliga. A linha achada sem certeza avisa "Confira" e a
// corrigida à mão avisa que continua protegida; nenhuma das duas vem
// escolhida. Quando o PDF pode ser de outra apólice, o aviso vem antes e nada
// vem escolhido. Cada interruptor tem nome próprio para leitor de tela: o nome
// do campo e o "Usar o do PDF" (aria-labelledby).
//   mudancas: [{ campo, antes, noPdf, corrigidoAMao, confira }]
defineProps({
  mudancas: { type: Array, required: true },
  escolhidos: { type: Array, required: true },
  outraApolice: { type: Boolean, default: false },
});
const emit = defineEmits(['trocar']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const uid = useId();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.PDF.MUDOU.${chave}`);
const nomeDoCampo = campo =>
  t(`RELACIONAMENTOS_CARTEIRA.CAMPOS.${campo.toUpperCase()}`);
const escrito = (campo, valor) =>
  valor === null || valor === undefined ? '—' : textos.doCampo(campo, valor);
</script>

<template>
  <div data-carteira="o-que-mudou" class="flex flex-col gap-4">
    <p
      v-if="outraApolice"
      role="alert"
      data-carteira="outra-apolice"
      class="p-4 m-0 text-base rounded-2xl bg-n-amber-2 text-n-amber-12"
    >
      {{ tp('OUTRA_APOLICE') }}
    </p>
    <p class="m-0 text-base text-n-slate-11">{{ tp('APOIO') }}</p>
    <table class="w-full text-sm border-collapse table-fixed text-start">
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
        <template v-for="linha in mudancas" :key="linha.campo">
          <tr :data-mudanca="linha.campo" class="align-top text-n-slate-12">
            <th
              :id="`${uid}-${linha.campo}-nome`"
              scope="row"
              class="py-2 font-medium break-words text-start pe-2"
            >
              {{ nomeDoCampo(linha.campo) }}
            </th>
            <td class="py-2 break-words tabular-nums pe-2">
              {{ escrito(linha.campo, linha.antes) }}
            </td>
            <td class="py-2 font-semibold break-words tabular-nums">
              {{ escrito(linha.campo, linha.noPdf) }}
            </td>
          </tr>
          <tr class="border-b border-n-weak/60">
            <td colspan="3" class="pb-3">
              <p
                v-if="linha.confira"
                data-carteira="confira"
                class="m-0 mb-1 text-sm text-n-amber-11"
              >
                {{ tp('CONFIRA') }}
              </p>
              <p
                v-if="linha.corrigidoAMao"
                class="m-0 mb-1 text-sm text-n-slate-11"
              >
                {{ tp('CORRIGIDO_A_MAO') }}
              </p>
              <button
                type="button"
                role="switch"
                data-carteira="usar-o-do-pdf"
                :aria-checked="escolhidos.includes(linha.campo)"
                :aria-labelledby="`${uid}-${linha.campo}-nome ${uid}-${linha.campo}-usar`"
                class="inline-flex items-center gap-2 px-3 text-sm font-medium border rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :class="
                  escolhidos.includes(linha.campo)
                    ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-12'
                    : 'border-n-weak bg-n-solid-1 text-n-slate-12'
                "
                @click="emit('trocar', linha.campo)"
              >
                <span
                  aria-hidden="true"
                  class="size-4"
                  :class="
                    escolhidos.includes(linha.campo)
                      ? 'i-lucide-check-square'
                      : 'i-lucide-square'
                  "
                />
                <span :id="`${uid}-${linha.campo}-usar`">{{ tp('USAR') }}</span>
              </button>
            </td>
          </tr>
        </template>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { numero } from '../../helpers/datas';

// Revisão da campanha com conversa aberta (#1335): quem recebe a mensagem
// escrita, quem recebe o modelo, quanto custa cada parte e o total, contra o
// total se todos recebessem o modelo.
const props = defineProps({
  janela: { type: Object, required: true },
  nomeDoModelo: { type: String, default: '' },
  temTexto: { type: Boolean, default: false },
});

const NS = 'MODELOS_WHATSAPP.JANELA.REVISAO';
const { t, locale } = useI18n();
const n = valor => numero(valor, locale.value);

const dentro = computed(() =>
  props.temTexto ? props.janela.contagem.value?.dentro || 0 : 0
);
const fora = computed(() => {
  const contagem = props.janela.contagem.value;
  if (!contagem) return 0;
  return props.temTexto ? contagem.fora : contagem.dentro + contagem.fora;
});
const precoModelo = computed(() => props.janela.precoModelo.value);

const custoTexto = computed(() => props.janela.custoEscrita(dentro.value));
const resumo = computed(() => {
  const dados = props.janela.resumoDaEscrita(dentro.value);
  return {
    ...dados,
    sobram: n(dados.sobram ?? 0),
    limite: n(dados.limite ?? 0),
    pagas: n(dados.pagas),
    gratis: n(dados.gratis),
  };
});
const custoModelo = computed(() => props.janela.custoModelo(fora.value));
const total = computed(() => custoTexto.value + custoModelo.value);
const semTexto = computed(() =>
  props.janela.custoModelo(dentro.value + fora.value)
);
</script>

<template>
  <!-- Sem contagem ou sem preço, o embrulho não ocupa lugar (display: contents). -->
  <div class="contents">
    <section
      v-if="janela.contagem.value && precoModelo"
      data-revisao-conversa-aberta
      class="flex flex-col gap-3 py-4 border-b border-n-weak"
    >
      <p class="m-0 text-xs font-semibold text-n-slate-11">
        {{ t(`${NS}.TITULO`) }}
      </p>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-if="dentro"
          data-linha="texto"
          class="grid grid-cols-[minmax(0,1fr)_auto] gap-3 text-sm"
        >
          <span class="text-n-slate-12">
            {{ t(`${NS}.TEXTO`, { n: n(dentro) }, dentro) }}
          </span>
          <span
            class="font-medium text-end"
            :class="custoTexto ? 'text-n-slate-12' : 'text-n-teal-11'"
          >
            {{ custoTexto ? janela.dinheiro(custoTexto) : t(`${NS}.GRATIS`) }}
          </span>
          <span
            data-franquia-da-escrita
            class="col-span-2 text-xs text-n-slate-11"
          >
            {{
              t(`MODELOS_WHATSAPP.JANELA.CUSTO_ESCRITA.${resumo.tipo}`, resumo)
            }}
          </span>
        </li>
        <li
          data-linha="modelo"
          class="grid grid-cols-[minmax(0,1fr)_auto] gap-3 text-sm"
        >
          <span class="text-n-slate-12">
            {{
              t(
                `${NS}.MODELO`,
                {
                  n: n(fora),
                  nome: nomeDoModelo,
                  preco: janela.dinheiro(precoModelo.valor, 4),
                },
                fora
              )
            }}
          </span>
          <span class="font-medium text-end text-n-slate-12">
            {{ janela.dinheiro(custoModelo) }}
          </span>
        </li>
        <li
          data-linha="total"
          class="grid grid-cols-[minmax(0,1fr)_auto] gap-3 pt-2 text-sm border-t border-n-weak"
        >
          <span class="font-semibold text-n-slate-12">
            {{ t(`${NS}.TOTAL`) }}
          </span>
          <span class="font-semibold text-end text-n-slate-12">
            {{ janela.dinheiro(total) }}
          </span>
        </li>
      </ul>
      <p
        v-if="temTexto && semTexto > total"
        data-economizou
        class="m-0 text-sm text-n-teal-11"
      >
        {{
          t(`${NS}.ECONOMIZOU`, { valor: janela.dinheiro(semTexto - total) })
        }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.ESTIMATIVA`) }}
      </p>
    </section>
  </div>
</template>

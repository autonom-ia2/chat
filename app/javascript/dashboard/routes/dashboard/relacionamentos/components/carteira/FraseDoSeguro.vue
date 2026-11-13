<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import { estaValendo } from '../../fonte/selosDoSeguro';
import { quandoDoSeguro } from '../../carteira/quandoDoSeguro';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SeloDoSeguro from './SeloDoSeguro.vue';

// #2897 — o topo da gaveta do seguro: de quem é o seguro ("Seguro de Fulano",
// e o nome leva à ficha da pessoa ou da empresa), o selo e UMA frase que diz
// como o seguro está agora (quando vence, há quanto venceu ou quando foi
// cancelado). A regra do tempo é a mesma da lista e da ficha
// (`quandoDoSeguro`). O seguro que vale e ainda não tem o PDF guardado diz isso
// em seguida. O próximo passo (o botão) fica no rodapé da gaveta.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrirSegurado']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.FRASE.${chave}`, valores);

// O nome e "Abrir a ficha" são um botão só; o nome dele junta os dois com
// espaço, que o leitor de tela não poria entre os dois pedaços.
const abrirFicha = computed(() =>
  t('RELACIONAMENTOS_CARTEIRA.GAVETA.ABRIR_FICHA')
);
const nomeDoBotao = computed(() =>
  [props.seguro.segurado.nome, abrirFicha.value].join(' ')
);

const frases = computed(() => {
  const { seguro, agora } = props;
  const { id, count, data } = quandoDoSeguro(seguro, agora);
  return [
    tf(id, { count, data: data ? textos.dataInteira(data) : '' }),
    estaValendo(seguro, agora) && !seguro.temPdf ? tf('SEM_PDF') : '',
  ].filter(Boolean);
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <I18nT
      keypath="RELACIONAMENTOS_CARTEIRA.GAVETA.DE_QUEM"
      tag="p"
      scope="global"
      data-carteira="de-quem"
      class="m-0 text-base break-words text-n-slate-11"
    >
      <template #nome>
        <button
          type="button"
          data-carteira="abrir-segurado"
          :aria-label="nomeDoBotao"
          class="inline-flex flex-wrap items-center p-0 text-base bg-transparent border-0 rounded-md gap-x-2 min-h-11 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('abrirSegurado', seguro.segurado)"
        >
          <span class="font-semibold break-words text-n-slate-12">
            {{ seguro.segurado.nome }}
          </span>
          <span class="font-medium underline text-n-blue-11">
            {{ abrirFicha }}
          </span>
        </button>
      </template>
    </I18nT>
    <div class="flex flex-wrap items-center gap-2">
      <SeloDoSeguro :seguro="seguro" :agora="agora" />
    </div>
    <p
      data-carteira="frase-do-seguro"
      class="m-0 text-xl font-semibold leading-snug text-balance text-n-slate-12"
    >
      {{ frases.join(' ') }}
    </p>
  </div>
</template>

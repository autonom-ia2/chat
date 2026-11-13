<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SegundaLinha from '../lista/SegundaLinha.vue';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SeloDoSeguro from './SeloDoSeguro.vue';

// #2897 — um seguro na lista: iniciais e nome de quem é o segurado (inteiro,
// quebra a linha em vez de cortar), o selo e, embaixo, "Auto · Seguradora ·
// vence em 18 dias (29/11)". Clicar no nome abre a gaveta do seguro: o botão do
// nome estica a área de clique pela linha toda.
const props = defineProps({
  seguro: { type: Object, required: true },
  // No grupo "Sem telefone", é isso que a linha diz no lugar do vencimento.
  dizSemTelefone: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores);

const tipo = computed(() => textos.tipo(props.seguro));
const nome = computed(() => props.seguro.segurado.nome);
const partes = computed(() => [
  tipo.value,
  props.seguro.seguradora,
  props.dizSemTelefone
    ? ca('SEM_TELEFONE')
    : textos.quando(props.seguro, props.agora),
]);
</script>

<template>
  <li
    data-carteira="linha"
    :data-apolice="seguro.id"
    class="relative flex items-center min-w-0 gap-3 px-3 py-3 transition-colors sm:px-5 hover:bg-n-alpha-1 focus-within:bg-n-alpha-1"
  >
    <Avatar
      :name="nome"
      :size="40"
      :rounded-full="seguro.segurado.tipo === 'pessoa'"
    />
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <button
          type="button"
          :aria-label="ca('ABRIR', { tipo, nome })"
          class="min-w-0 max-w-full p-0 text-base font-semibold break-words bg-transparent border-0 text-start text-n-slate-12 after:absolute after:inset-0 focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:-outline-offset-2 focus-visible:after:outline-n-brand focus-visible:after:rounded-2xl"
          @click="emit('abrir', seguro)"
        >
          {{ nome }}
        </button>
        <SeloDoSeguro :seguro="seguro" :agora="agora" />
      </div>
      <SegundaLinha :partes="partes" />
    </div>
  </li>
</template>

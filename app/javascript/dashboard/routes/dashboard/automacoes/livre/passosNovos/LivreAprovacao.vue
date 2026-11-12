<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreTexto from '../components/LivreTexto.vue';
import LivreDuracao from '../components/LivreDuracao.vue';
import LivreQuem from './LivreQuem.vue';
import LivrePedidoAprovacao from './LivrePedidoAprovacao.vue';
import { P } from './passosNovos';

// #2931 — Pedir aprovação: quem aprova, o que perguntar (com dados, como o
// valor do card, que só aparece para quem pode ver valores) e o prazo. O botão
// mostra o pedido como quem aprova vai ver.
const props = defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);
const pedido = ref(null);

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="pedir_aprovacao">
    <LivreQuem
      :rotulo="$t(`${P}.APROVACAO.QUEM`)"
      :model-value="modelValue.quem"
      :opcoes="opcoes"
      @update:model-value="quem => mudar({ quem })"
    />
    <LivreTexto
      :rotulo="$t(`${P}.APROVACAO.PERGUNTA`)"
      :model-value="modelValue.pergunta"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="pergunta => mudar({ pergunta })"
    />
    <LivreDuracao
      :rotulo="$t(`${P}.APROVACAO.PRAZO`)"
      :model-value="modelValue.prazo"
      :unidades="catalogo.unidades"
      @update:model-value="prazo => mudar({ prazo })"
    />
    <p class="mb-0 text-sm text-n-slate-11">
      {{ $t(`${P}.APROVACAO.QUEM_PODE`) }}
    </p>
    <Button
      data-ver-pedido
      :label="$t(`${P}.APROVACAO.VER_PEDIDO`)"
      icon="i-lucide-eye"
      slate
      faded
      class="self-start min-h-11"
      @click="pedido?.abrir()"
    />
    <LivrePedidoAprovacao
      ref="pedido"
      :passo="modelValue"
      :catalogo="catalogo"
    />
  </div>
</template>

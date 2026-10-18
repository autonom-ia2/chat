<script setup>
// Os espaços do texto da mensagem (#1716). O que o contato preenche sozinho
// (o nome do cliente, pelo perfil do modelo, como na campanha) já vem escrito;
// o atendente pode mudar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import { comEspacos, exemploDoCampo } from './modeloNaConversa';

const props = defineProps({
  // o componente BODY do modelo
  corpo: { type: Object, default: null },
  campos: { type: Array, required: true },
  valores: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA';
const texto = computed(() =>
  comEspacos(props.corpo?.text, {}, n => t(`${NS}.CARTAO.ESPACO`, { n }))
);
const mudar = (nome, valor) =>
  emit('update', { ...props.valores, [nome]: valor });
</script>

<template>
  <section class="flex flex-col gap-3" data-campos-da-mensagem>
    <h4 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.CONFIRA.TEXTO`) }}
    </h4>
    <p
      class="px-3 py-2 m-0 text-sm break-words rounded-xl bg-n-alpha-1 text-n-slate-12"
    >
      {{ texto }}
    </p>
    <Input
      v-for="nome in campos"
      :key="nome"
      :model-value="valores[nome] || ''"
      :label="t(`${NS}.CARTAO.CAMPO`, { n: nome })"
      :placeholder="
        t(`${NS}.CARTAO.EXEMPLO`, { exemplo: exemploDoCampo(corpo, nome) })
      "
      custom-input-class="!h-11"
      :data-campo-da-mensagem="nome"
      @update:model-value="valor => mudar(nome, valor)"
    />
  </section>
</template>

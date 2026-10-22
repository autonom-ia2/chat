<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import FicarComAConversa from 'dashboard/components-next/conversa-canal/atribuir/FicarComAConversa.vue';

// #1459 — rodapé fixo da gaveta, com no máximo um botão azul:
// - `enviar`: "Cancelar" e "Enviar mensagem" (desligado enquanto falta algo,
//   com o texto ao lado dizendo o quê);
// - `enviada`: "Fechar" e "Abrir a conversa";
// - `fechar`: só "Fechar" (ainda sem contato, ou contato sem canal — nesses
//   casos a ação da tela está no corpo).
// #2067: na conversa que já existe, o ícone "ficar com a conversa ao enviar" fica ao lado
// do "Enviar mensagem", como na caixa de resposta (`ficar`, de useFicarComAConversa).
defineProps({
  modo: { type: String, default: 'enviar' },
  falta: { type: String, default: '' },
  enviando: { type: Boolean, default: false },
  ficar: { type: Object, default: null },
});

defineEmits(['cancelar', 'enviar', 'abrir', 'fechar']);

const R = 'NOVA_CONVERSA.RODAPE';
</script>

<template>
  <footer
    class="flex flex-wrap items-center justify-end gap-2 border-t border-n-weak bg-n-solid-1 px-5 py-4 sm:px-8"
  >
    <template v-if="modo === 'enviar'">
      <p
        id="nova-conversa-falta"
        aria-live="polite"
        class="mb-0 min-w-0 flex-1 text-sm text-n-slate-11"
      >
        {{ falta ? $t(`${R}.FALTA.${falta}`) : '' }}
      </p>
      <Button
        :label="$t(`${R}.CANCELAR`)"
        slate
        ghost
        class="!min-h-11"
        @click="$emit('cancelar')"
      />
      <FicarComAConversa v-if="ficar" :ficar="ficar" />
      <Button
        data-nova-conversa-principal
        :label="$t(`${R}.ENVIAR`)"
        icon="i-lucide-send"
        class="!min-h-11 min-w-32"
        aria-describedby="nova-conversa-falta"
        :is-loading="enviando"
        :disabled="Boolean(falta) || enviando"
        @click="$emit('enviar')"
      />
    </template>
    <template v-else>
      <Button
        data-nova-conversa-fechar-rodape
        :label="$t('NOVA_CONVERSA.FECHAR')"
        slate
        ghost
        class="!min-h-11"
        @click="$emit('fechar')"
      />
      <Button
        v-if="modo === 'enviada'"
        data-nova-conversa-principal
        :label="$t('NOVA_CONVERSA.ENVIADA.ABRIR')"
        icon="i-lucide-arrow-right"
        trailing-icon
        class="!min-h-11 min-w-32"
        @click="$emit('abrir')"
      />
    </template>
  </footer>
</template>

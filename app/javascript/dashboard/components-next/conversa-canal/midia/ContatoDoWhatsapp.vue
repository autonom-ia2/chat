<script setup>
// #1702: cartão de contato como no WhatsApp: foto redonda, nome, telefone e, embaixo
// de uma linha fina, as ações em verde. Recebido do cliente: "Conversar" (slot, abre a
// Nova conversa) e "Salvar contato". Enviado por nós: sem ação, o contato já é nosso.
defineProps({
  nome: { type: String, default: '' },
  telefone: { type: String, default: '' },
  acao: { type: Object, default: null },
});
</script>

<template>
  <div class="w-[280px] max-w-full">
    <div class="flex items-center gap-3 px-2 pt-2 pb-3">
      <span
        class="grid place-content-center size-12 shrink-0 rounded-full bg-[#DFE5E7] dark:bg-[#6A7175]"
      >
        <span
          class="i-ph-user-fill size-7 text-white dark:text-[#C9CCCC]"
          aria-hidden="true"
        />
      </span>
      <span class="min-w-0">
        <span
          class="block text-[15px] font-medium truncate text-[#0A0A0A] dark:text-[#FAFAFA]"
        >
          {{ nome || telefone }}
        </span>
        <span
          v-if="nome && telefone"
          class="block text-[13px] truncate text-[#666666] dark:text-[#A7A8A8]"
        >
          {{ telefone }}
        </span>
      </span>
    </div>
    <!-- Embaixo de uma linha fina, as ações lado a lado, como no app. -->
    <div
      v-if="acao || $slots.conversar"
      class="flex -mb-1 border-t border-[#000]/10 dark:border-white/10 divide-x divide-[#000]/10 dark:divide-white/10 [&>*]:flex-1"
    >
      <slot name="conversar" />
      <button
        v-if="acao"
        type="button"
        class="h-10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03]"
        @click="acao.onClick"
      >
        {{ acao.label }}
      </button>
    </div>
  </div>
</template>

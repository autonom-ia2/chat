<script setup>
// Carrossel na prévia: os cartões lado a lado, com rolagem lateral, como no
// WhatsApp do cliente.
defineProps({
  cartoes: { type: Array, required: true },
});
</script>

<template>
  <ul
    data-celular-cartoes
    class="flex gap-2 p-0 pb-2 m-0 overflow-x-auto list-none snap-x snap-mandatory"
    :aria-label="$t('MODELOS_WHATSAPP.CELULAR.CARTOES')"
  >
    <li
      v-for="(cartao, indice) in cartoes"
      :key="indice"
      class="flex flex-col shrink-0 w-[11.5rem] overflow-hidden shadow-sm snap-start rounded-xl bg-n-solid-1"
    >
      <span
        class="grid gap-1 h-24 place-items-center bg-n-slate-4 text-n-slate-11"
      >
        <span
          class="size-7"
          :class="cartao.midia === 'video' ? 'i-lucide-video' : 'i-lucide-image'"
          aria-hidden="true"
        />
        <span class="max-w-full px-2 text-[0.6875rem] truncate">
          {{ cartao.arquivo || $t(`MODELOS_WHATSAPP.TOPOS.${cartao.midia === 'video' ? 'video' : 'foto'}.ROTULO`) }}
        </span>
      </span>
      <p class="px-2.5 py-2 mb-0 text-xs leading-snug break-words text-n-slate-12">
        {{ cartao.texto || $t('MODELOS_WHATSAPP.CELULAR.VAZIO') }}
      </p>
      <span
        v-for="(botao, posicao) in cartao.botoes"
        :key="posicao"
        class="flex items-center justify-center gap-1 py-1.5 mt-auto text-xs font-medium border-t border-n-weak text-n-blue-11"
      >
        <span
          class="size-3.5"
          :class="botao.tipo === 'site' ? 'i-lucide-external-link' : 'i-lucide-reply'"
          aria-hidden="true"
        />
        {{ botao.texto || $t('MODELOS_WHATSAPP.CELULAR.BOTAO_SEM_TEXTO') }}
      </span>
    </li>
  </ul>
</template>

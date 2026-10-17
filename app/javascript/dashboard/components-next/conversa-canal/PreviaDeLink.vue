<script setup>
// Cartão da prévia de link dentro do balão (#1702), como no WhatsApp Web: imagem em
// cima, título, descrição em até duas linhas e o domínio, num fundo um pouco mais
// escuro que o balão, acima do texto. O toque abre o endereço em outra aba. Quem
// decide se aparece é o balão de texto (usePreviaDeLink: só com a pele do WhatsApp).
defineProps({
  previa: { type: Object, required: true },
});
</script>

<template>
  <a
    :href="previa.url"
    target="_blank"
    rel="noopener noreferrer"
    :aria-label="
      $t('CONVERSA_CANAL.PREVIA_DE_LINK.ABRIR', { site: previa.site })
    "
    class="flex flex-col w-full min-w-0 mb-1 overflow-hidden rounded-[7.5px] bg-[#000]/[0.05] dark:bg-[#000]/20 no-underline hover:bg-[#000]/[0.08] dark:hover:bg-[#000]/30"
    data-previa-de-link
  >
    <img
      v-if="previa.imagem"
      :src="previa.imagem"
      alt=""
      loading="lazy"
      referrerpolicy="no-referrer"
      class="w-full max-h-[220px] object-cover"
    />
    <span class="flex flex-col gap-0.5 px-2.5 py-2 min-w-0">
      <span
        class="text-[14px] leading-[19px] font-medium text-[#0A0A0A] dark:text-[#FAFAFA] line-clamp-2"
      >
        {{ previa.titulo }}
      </span>
      <span
        v-if="previa.descricao"
        class="text-[12.8px] leading-[17px] text-[#666666] dark:text-[#A7A8A8] line-clamp-2"
      >
        {{ previa.descricao }}
      </span>
      <span
        class="text-[12.8px] leading-[17px] text-[#666666] dark:text-[#A7A8A8] truncate"
      >
        {{ previa.dominio }}
      </span>
    </span>
  </a>
</template>

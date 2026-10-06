<script setup>
// Anúncios da Meta (#1068), passo 3: o desenho de cada caminho, para a pessoa reconhecer o próprio anúncio
// antes de escolher. WhatsApp: anúncio → conversa. Site: anúncio → página → conversa. Só ilustração; o texto
// que decide fica no cartão.
defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['whatsapp', 'site'].includes(value),
  },
});
</script>

<template>
  <div
    :data-destination-art="kind"
    aria-hidden="true"
    class="flex items-center justify-center w-full min-w-0 gap-1.5 px-2 py-4 overflow-hidden rounded-xl bg-n-alpha-1 sm:gap-3 sm:px-3"
  >
    <!-- O anúncio no celular -->
    <div
      class="flex flex-col flex-none gap-1 p-1.5 border-2 rounded-2xl w-[4.75rem] sm:w-24 border-n-slate-8 bg-n-solid-1"
    >
      <span class="text-[9px] leading-none text-n-slate-10">
        {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.SPONSORED') }}
      </span>
      <span
        class="grid h-12 rounded-md place-items-center bg-n-blue-9 text-white"
      >
        <span class="i-lucide-megaphone size-5" />
      </span>
      <span class="h-1.5 rounded-full bg-n-slate-5" />
      <span class="w-2/3 h-1.5 rounded-full bg-n-slate-5" />
      <span
        class="flex items-center justify-center gap-1 py-1 text-[9px] font-semibold leading-none text-white rounded-md"
        :class="kind === 'whatsapp' ? 'bg-n-teal-9' : 'bg-n-blue-9'"
      >
        <span
          class="size-2.5"
          :class="
            kind === 'whatsapp'
              ? 'i-lucide-message-circle'
              : 'i-lucide-external-link'
          "
        />
        {{
          kind === 'whatsapp'
            ? $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.SEND_MESSAGE')
            : $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.LEARN_MORE')
        }}
      </span>
    </div>

    <span
      class="flex-none i-lucide-arrow-right size-3.5 sm:size-4 text-n-slate-9"
    />

    <!-- A página do site, só no caminho do site -->
    <template v-if="kind === 'site'">
      <div
        class="flex flex-col flex-none gap-1.5 w-[4.75rem] sm:w-24 overflow-hidden border rounded-lg border-n-slate-7 bg-n-solid-1"
      >
        <span class="flex gap-0.5 px-1.5 py-1 bg-n-slate-3">
          <span class="rounded-full size-1.5 bg-n-slate-7" />
          <span class="rounded-full size-1.5 bg-n-slate-7" />
          <span class="rounded-full size-1.5 bg-n-slate-7" />
        </span>
        <span class="flex flex-col gap-1 px-1.5 pb-1.5">
          <span class="w-3/4 h-1.5 rounded-full bg-n-slate-6" />
          <span class="h-1.5 rounded-full bg-n-slate-5" />
          <span class="w-1/2 h-1.5 rounded-full bg-n-slate-5" />
          <span
            class="flex items-center justify-center gap-1 py-1 mt-0.5 text-[9px] font-semibold leading-none text-white rounded-md bg-n-teal-9"
          >
            <span class="i-lucide-message-circle size-2.5" />
            {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.SITE_BUTTON') }}
          </span>
        </span>
      </div>
      <span
        class="flex-none i-lucide-arrow-right size-3.5 sm:size-4 text-n-slate-9"
      />
    </template>

    <!-- A conversa no WhatsApp -->
    <div class="flex flex-col flex-none gap-1.5 w-[4.75rem] sm:w-24">
      <span
        class="self-end px-2 py-1 text-[10px] leading-tight rounded-lg rounded-br-none bg-n-teal-4 text-n-slate-12"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.CHAT_IN') }}
      </span>
      <span
        class="self-start px-2 py-1 text-[10px] leading-tight rounded-lg rounded-bl-none bg-n-solid-1 text-n-slate-12 border border-n-weak"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.ART.CHAT_OUT') }}
      </span>
    </div>
  </div>
</template>

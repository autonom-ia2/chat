<script setup>
// Quem aprova é o WhatsApp: quanto tempo leva e o que pode mudar no custo.
defineProps({
  tipo: { type: String, required: true },
  soDivulgacao: { type: Boolean, default: false },
});
</script>

<template>
  <section
    data-quem-aprova
    class="flex gap-4 p-5 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-5"
  >
    <span
      class="grid place-items-center size-11 shrink-0 rounded-xl bg-n-blue-3 text-n-blue-11"
    >
      <span class="i-lucide-badge-check size-6" aria-hidden="true" />
    </span>
    <div class="flex flex-col gap-2 min-w-0">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.QUEM_APROVA.TITULO') }}
      </h3>
      <ul class="flex flex-col gap-1.5 p-0 m-0 text-[0.9375rem] list-none text-n-slate-11">
        <li>{{ $t('MODELOS_WHATSAPP.QUEM_APROVA.TEMPO') }}</li>
        <li v-if="soDivulgacao">
          {{ $t('MODELOS_WHATSAPP.QUEM_APROVA.SO_DIVULGACAO') }}
        </li>
        <li v-else>
          {{
            $t('MODELOS_WHATSAPP.QUEM_APROVA.TIPO', {
              tipo: $t(`MODELOS_WHATSAPP.TIPOS.${tipo}.ROTULO`),
            })
          }}
        </li>
        <li>{{ $t('MODELOS_WHATSAPP.QUEM_APROVA.AVISO') }}</li>
      </ul>
    </div>
  </section>
</template>

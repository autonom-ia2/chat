<script setup>
// Catálogo: a mensagem leva o botão "Ver produtos", que abre o catálogo da
// conta no WhatsApp. Sem catálogo conectado: uma frase e um botão.
defineProps({
  catalogo: { type: Object, default: null },
});

// O catálogo se conecta no Gerenciador de Comércio da Meta.
const COMO_CONECTAR = 'https://business.facebook.com/commerce';
</script>

<template>
  <div data-etapa-catalogo class="flex flex-col gap-6">
    <div
      v-if="!catalogo"
      data-sem-catalogo
      class="flex flex-col items-start gap-4 p-6 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
    >
      <p class="mb-0 text-base text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.CATALOGO.SEM_CATALOGO') }}
      </p>
      <a
        :href="COMO_CONECTAR"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-2 px-4 text-[0.9375rem] font-semibold text-white rounded-xl min-h-11 bg-n-brand hover:brightness-110"
      >
        {{ $t('MODELOS_WHATSAPP.CATALOGO.COMO_CONECTAR') }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
      </a>
    </div>
    <template v-else>
      <div
        data-catalogo
        class="flex items-center gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-12 shrink-0 rounded-xl bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-shopping-bag size-6" aria-hidden="true" />
        </span>
        <span class="flex flex-col">
          <span class="text-base font-semibold text-n-slate-12">{{
            catalogo.nome
          }}</span>
          <span class="text-sm text-n-slate-11">
            {{
              $t(
                'MODELOS_WHATSAPP.CATALOGO.PRODUTOS',
                { n: catalogo.produtos },
                catalogo.produtos
              )
            }}
          </span>
        </span>
      </div>
      <p class="mb-0 text-base text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.CATALOGO.INTRO') }}
      </p>
    </template>
  </div>
</template>

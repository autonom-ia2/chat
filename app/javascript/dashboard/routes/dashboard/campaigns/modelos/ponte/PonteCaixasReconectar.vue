<script setup>
// Caixas do WhatsApp oficial que precisam reconectar: aparecem desativadas na
// escolha, e aqui o motivo e o caminho para resolver.
defineProps({
  caixas: { type: Array, required: true },
});
</script>

<template>
  <!-- Sem nada para mostrar, o embrulho não ocupa lugar (display: contents). -->
  <div class="contents">
    <ul
      v-if="caixas.length"
      data-ponte-reconectar
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <!-- Ícone na mesma linha do começo do texto, quebre ele onde quebrar (#1387). -->
      <li
        v-for="caixa in caixas"
        :key="caixa.id"
        class="flex items-start gap-2 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-plug-zap size-4 mt-0.5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        <span class="flex flex-col min-w-0">
          {{
            $t('MODELOS_WHATSAPP.PONTE.RECONECTAR_MOTIVO', {
              nome: caixa.nome,
            })
          }}
          <router-link
            :to="{ name: 'settings_inbox_show', params: { inboxId: caixa.id } }"
            class="inline-flex items-center self-start font-medium min-h-11 text-n-blue-11 hover:underline"
          >
            {{ $t('MODELOS_WHATSAPP.PONTE.RECONECTAR') }}
          </router-link>
        </span>
      </li>
    </ul>
  </div>
</template>

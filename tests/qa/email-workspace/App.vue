<script setup>
import { useRoute } from 'vue-router';
const route = useRoute();
const navigation = [
  ['i-lucide-inbox', 'Caixa de Entrada'],
  ['i-lucide-messages-square', 'Conversas'],
  ['i-lucide-phone', 'Chamadas'],
  ['i-lucide-bot', 'Agentes'],
  ['i-lucide-contact', 'Relacionamentos'],
  ['i-lucide-columns-3', 'CRM'],
  ['i-lucide-chart-no-axes-combined', 'Relatórios'],
  ['i-lucide-megaphone', 'Campanhas'],
];
</script>
<template>
  <div class="flex h-screen min-w-0 overflow-hidden bg-n-background">
    <aside
      class="hidden h-full w-60 shrink-0 flex-col bg-[#0D2344] p-4 text-white lg:flex"
    >
      <div class="mb-8 flex items-center gap-3 px-2 py-5">
        <span class="i-lucide-messages-square size-9 text-blue-300" /><span
          class="text-xl font-semibold"
          >Chat2You</span
        >
      </div>
      <p class="mb-5 px-2 text-xs text-blue-200">QA local · dados fictícios</p>
      <div
        v-for="[icon, label] in navigation"
        :key="label"
        class="mb-1 flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm text-blue-100"
        :class="label === 'Campanhas' ? 'bg-white/10 text-white' : ''"
      >
        <span :class="icon" class="size-5" />{{ label }}
      </div>
      <router-link
        :to="{ name: 'campaigns_email_index', params: { accountId: 800 } }"
        class="ms-7 rounded-lg bg-white/10 p-3 text-sm text-white"
        >Campanhas de e-mail</router-link
      >
      <div class="mt-auto border-t border-white/10 pt-4 text-xs text-blue-200">
        Ambiente isolado · sem envio
      </div>
    </aside>
    <main class="min-w-0 flex-1">
      <router-view v-slot="{ Component }"
        ><keep-alive><component :is="Component" :key="route.name" /></keep-alive
      ></router-view>
    </main>
  </div>
</template>

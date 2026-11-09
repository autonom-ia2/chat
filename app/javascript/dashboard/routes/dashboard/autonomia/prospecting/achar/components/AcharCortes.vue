<script setup>
// #2692 — os cortes da lista (v4, T1): "Só com WhatsApp" e, com muitas
// empresas, a procura pelo nome. Saiu de AcharConfiraPage.vue (trava de
// tamanho, #677). O botão tem `border-solid` porque o estilo base do painel
// tira a borda de todo <button>.
// Mapa (pedido do Rodrigo depois da r5): no celular, "Ver no mapa" fica ao
// lado de "Só com WhatsApp" e abre o mapa em tela cheia.
defineProps({
  comWhatsapp: { type: Boolean, default: true },
  comNome: { type: Boolean, default: false },
  comMapa: { type: Boolean, default: false },
});
const emit = defineEmits(['verMapa']);
const soWhatsapp = defineModel('soWhatsapp', { type: Boolean, default: false });
const procuraNome = defineModel('procuraNome', { type: String, default: '' });

const NS = 'PROSPECTING_ACHAR.CONFIRA';
</script>

<template>
  <div class="flex flex-col gap-3 md:flex-row md:items-center" data-cortes>
    <div class="flex flex-wrap gap-3 md:contents">
      <button
        v-if="comWhatsapp"
        type="button"
        :aria-pressed="soWhatsapp"
        class="flex items-center self-start gap-2 px-4 text-sm font-medium border-2 border-solid rounded-full shrink-0 min-h-11 md:self-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          soWhatsapp
            ? 'border-n-violet-9 bg-n-violet-3 text-n-violet-11'
            : 'border-n-slate-6 bg-n-solid-1 text-n-slate-12 hover:border-n-slate-8'
        "
        data-so-whatsapp
        @click="soWhatsapp = !soWhatsapp"
      >
        <span
          class="size-4"
          :class="soWhatsapp ? 'i-lucide-check' : 'i-lucide-message-circle'"
          aria-hidden="true"
        />
        {{ $t(`${NS}.SO_WHATSAPP`) }}
      </button>
      <button
        v-if="comMapa"
        type="button"
        class="flex items-center self-start gap-2 px-4 text-sm font-medium border-2 border-solid rounded-full shrink-0 min-h-11 md:self-auto border-n-slate-6 bg-n-solid-1 text-n-slate-12 hover:border-n-slate-8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-ver-mapa
        @click="emit('verMapa')"
      >
        <span class="i-lucide-map size-4" aria-hidden="true" />
        {{ $t(`${NS}.MAPA.VER`) }}
      </button>
    </div>
    <input
      v-if="comNome"
      v-model="procuraNome"
      type="search"
      :aria-label="$t(`${NS}.PROCURAR_NOME`)"
      :placeholder="$t(`${NS}.PROCURAR_NOME`)"
      class="w-full !h-11 px-4 text-sm border-2 outline-none !mb-0 rounded-full border-n-slate-6 bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-blue-9 md:flex-1 md:min-w-0"
      data-procurar-nome
    />
  </div>
</template>

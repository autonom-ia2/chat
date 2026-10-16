<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteAvatar from './AgenteAvatar.vue';
import AgenteBotao from './AgenteBotao.vue';

// #1648 (mockup-2) — campo Foto do agente de outro sistema, com a mesma bolinha dos nossos agentes:
// sem foto, a inicial do nome. "Escolher foto" abre o seletor de arquivo do aparelho.
// Emite `escolher` com { file, url } (url local, para a prévia).
defineProps({
  nome: { type: String, default: '' },
  src: { type: String, default: '' },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();
const seletor = ref(null);

const aoEscolher = evento => {
  const [file] = evento.target.files || [];
  evento.target.value = '';
  if (!file) return;
  emit('escolher', { file, url: URL.createObjectURL(file) });
};
</script>

<template>
  <div class="flex flex-col items-start gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('AGENTS.OUTRO_SISTEMA.FOTO') }}
    </span>
    <div class="flex items-center gap-4">
      <AgenteAvatar
        class="!size-16 !text-2xl"
        :nome="nome || '?'"
        :src="src"
        tom="atendendo"
      />
      <AgenteBotao
        data-escolher-foto
        variante="contorno"
        icone="i-lucide-image-up"
        @click="seletor?.click()"
      >
        {{ t('AGENTS.OUTRO_SISTEMA.ESCOLHER_FOTO') }}
      </AgenteBotao>
      <input
        ref="seletor"
        type="file"
        accept="image/*"
        class="hidden"
        @change="aoEscolher"
      />
    </div>
  </div>
</template>

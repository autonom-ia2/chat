<script setup>
import { computed } from 'vue';
import GuideVoz from './GuideVoz.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #895 — o balão de quem usa, no jeito do WhatsApp: à direita, com o texto, as
// fotos e os arquivos daquele envio e, numa mensagem de voz, o áudio com a
// transcrição logo abaixo.
const props = defineProps({
  // Registro do store: { texto, anexos, voz }.
  item: {
    type: Object,
    required: true,
  },
  // #982 — na tela de Automações, o balão de quem pede é azul, como no WhatsApp.
  destaque: { type: Boolean, default: false },
});

const emit = defineEmits(['tentarDeNovo']);

// #861 — numa conversa reaberta a foto volta sem miniatura (o arquivo é
// apagado em 1 dia): aparece na lista, pelo nome, com o ícone de imagem.
const comPrevia = anexo => anexo.tipo === 'imagem' && anexo.previa;
const fotos = computed(() => (props.item.anexos || []).filter(comPrevia));
const documentos = computed(() =>
  (props.item.anexos || []).filter(anexo => !comPrevia(anexo))
);
const voz = computed(() => props.item.voz);
</script>

<template>
  <div class="flex justify-end w-full">
    <div
      class="flex flex-col gap-2 max-w-[85%] min-w-0 rounded-2xl ltr:rounded-br-md rtl:rounded-bl-md"
      :class="
        destaque
          ? 'bg-n-brand px-4 py-3 text-base leading-relaxed text-white'
          : 'bg-n-alpha-2 px-3 py-2 text-n-slate-12'
      "
    >
      <span class="sr-only">{{ $t('CAPTAIN.COPILOT.YOU') }}</span>
      <ul
        v-if="fotos.length"
        class="flex flex-wrap justify-end gap-1 m-0 p-0 list-none"
      >
        <li v-for="foto in fotos" :key="foto.id">
          <img
            :src="foto.previa"
            :alt="foto.nome"
            class="block max-h-40 max-w-full rounded-lg object-cover"
          />
        </li>
      </ul>
      <ul
        v-if="documentos.length"
        class="flex flex-col gap-1 m-0 p-0 list-none"
      >
        <li
          v-for="documento in documentos"
          :key="documento.id"
          class="flex items-center gap-2 min-w-0 rounded-lg bg-n-alpha-1 px-2 py-2 text-sm"
        >
          <span
            class="size-5 shrink-0 text-n-slate-11"
            :class="
              documento.tipo === 'imagem'
                ? 'i-lucide-image'
                : 'i-lucide-file-text'
            "
            aria-hidden="true"
          />
          <span class="truncate min-w-0">{{ documento.nome }}</span>
        </li>
      </ul>
      <div v-if="voz" class="flex flex-col gap-1 w-64 max-w-full min-w-0">
        <span class="sr-only">{{ $t('AUTONOMIA_GUIDE.VOICE.NOTE') }}</span>
        <GuideVoz :src="voz.url" :duracao="voz.duracao" />
        <p
          v-if="voz.estado === 'transcrevendo'"
          class="flex items-center gap-1 mb-0 text-xs text-n-slate-11"
        >
          <span class="i-svg-spinner size-3 shrink-0" aria-hidden="true" />
          {{ $t('AUTONOMIA_GUIDE.VOICE.TRANSCRIBING') }}
        </p>
        <p
          v-else-if="voz.estado === 'pronta'"
          class="mb-0 text-xs leading-5 text-n-slate-11 break-words whitespace-pre-wrap"
        >
          {{ voz.texto }}
        </p>
        <div v-else-if="voz.estado === 'erro'" class="flex flex-col gap-1">
          <p class="mb-0 text-xs text-n-ruby-11 break-words">
            {{ voz.erro || $t('AUTONOMIA_GUIDE.VOICE.FAILED') }}
          </p>
          <Button
            :label="$t('AUTONOMIA_GUIDE.VOICE.RETRY')"
            icon="i-lucide-rotate-ccw"
            size="sm"
            slate
            faded
            class="self-start min-h-11"
            @click="emit('tentarDeNovo')"
          />
        </div>
      </div>
      <p v-if="item.texto" class="mb-0 break-words whitespace-pre-wrap">
        {{ item.texto }}
      </p>
    </div>
  </div>
</template>

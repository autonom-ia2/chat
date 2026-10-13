<script setup>
import { computed } from 'vue';

// Prévia de uma mensagem como o cliente a recebe no WhatsApp: um balão com o
// texto e a hora. Reutilizável e sem dependências: não conhece gaveta, store
// nem rota, e todo texto chega por prop ou slot (só "agora" é dela).
//
// Quatro estados:
// - com `texto`: o balão da empresa;
// - sem texto (ou com `vazio`): o balão fantasma, com o texto de `fantasma`;
// - com `aviso` (prop ou slot): caixa tracejada, para quando só se sabe que
//   sai uma mensagem pronta aprovada, e não o que ela diz;
// - slot `cabecalho`: uma linha acima dos balões ("Vai para Mariana").
const props = defineProps({
  texto: { type: String, default: '' },
  nomeDoRemetente: { type: String, default: '' },
  vazio: { type: Boolean, default: false },
  fantasma: { type: String, default: '' },
  aviso: { type: String, default: '' },
  hora: { type: String, default: '' },
});

const semTexto = computed(() => props.vazio || !props.texto.trim());
</script>

<template>
  <div
    data-previa-whatsapp
    class="flex flex-col gap-2 rounded-2xl bg-n-teal-2 p-3"
  >
    <span
      v-if="$slots.cabecalho"
      data-previa-cabecalho
      class="self-center rounded-lg bg-n-solid-1 px-2 py-0.5 text-sm text-n-slate-11"
    >
      <slot name="cabecalho" />
    </span>

    <p
      v-if="$slots.aviso || aviso"
      data-previa-aviso
      class="mb-0 flex items-start gap-2 rounded-xl border border-dashed border-n-slate-7 bg-n-solid-1 px-3 py-2 text-sm leading-relaxed text-n-slate-11"
    >
      <span
        class="i-lucide-message-square-text mt-0.5 size-4 shrink-0"
        aria-hidden="true"
      />
      <span class="min-w-0 break-words">
        <slot name="aviso">{{ aviso }}</slot>
      </span>
    </p>

    <p
      v-else-if="semTexto"
      data-previa-fantasma
      class="mb-0 max-w-[85%] self-start rounded-xl rounded-ss-sm border border-dashed border-n-slate-6 px-3 py-2 text-sm text-n-slate-10"
    >
      {{ fantasma }}
    </p>

    <div
      v-else
      data-previa-balao
      class="flex max-w-[85%] flex-col gap-1 self-start rounded-xl rounded-ss-sm bg-n-solid-1 px-3 py-2 shadow-sm"
    >
      <span
        v-if="nomeDoRemetente"
        data-previa-remetente
        class="truncate text-xs font-semibold text-n-teal-11"
      >
        {{ nomeDoRemetente }}
      </span>
      <p
        class="mb-0 whitespace-pre-wrap break-words text-sm leading-relaxed text-n-slate-12"
      >
        {{ texto }}
      </p>
      <span class="self-end text-xs text-n-slate-10">
        {{ hora || $t('NOVA_CONVERSA.PREVIA.AGORA') }}
      </span>
    </div>
  </div>
</template>

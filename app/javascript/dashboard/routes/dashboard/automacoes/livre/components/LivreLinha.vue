<script setup>
import { computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2414 F5 — uma automação na lista única, nova ou do jeito antigo: a frase
// (Quando → primeiro passo), o selo de origem e o interruptor.
const props = defineProps({
  nome: { type: String, required: true },
  quando: { type: String, required: true },
  primeiro: { type: String, default: '' },
  outros: { type: Number, default: 0 },
  // #2498 — "Rodou 12 vezes esta semana · 1 parou". A antiga não tem.
  fato: { type: String, default: '' },
  ativa: { type: Boolean, default: false },
  antiga: { type: Boolean, default: false },
  // #2499 — começa num card do funil, não numa conversa.
  doCard: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  mudando: { type: Boolean, default: false },
  // #2572: a frase do motivo com que o motor a pausou (quem ligou perdeu o
  // acesso). Ligar de novo é assumir: o botão diz isso no lugar do interruptor.
  pausa: { type: String, default: '' },
  // #2933: marcada "Usar como bloco" (sem gatilho próprio: não liga sozinha).
  bloco: { type: Boolean, default: false },
  // A conta tem os passos novos: a linha oferece marcar e desmarcar o bloco.
  podeSerBloco: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir', 'alternar', 'bloco']);

// O selo diz de onde a automação vem: do jeito antigo, de um card do funil ou
// de uma conversa.
const selo = computed(() => {
  if (props.bloco)
    return { icone: 'i-lucide-boxes', chave: 'AUTOMACAO_LIVRE.ORIGEM.BLOCO' };
  if (props.antiga)
    return {
      icone: 'i-lucide-history',
      chave: 'AUTOMACAO_LIVRE.ORIGEM.ANTIGO',
    };
  if (props.doCard)
    return { icone: 'i-lucide-kanban', chave: 'AUTOMACAO_LIVRE.ORIGEM.CARD' };
  return {
    icone: 'i-lucide-message-circle',
    chave: 'AUTOMACAO_LIVRE.ORIGEM.CONVERSA',
  };
});
</script>

<template>
  <li
    data-linha
    :data-antiga="antiga || undefined"
    class="flex flex-col gap-4 p-5 transition border shadow-sm sm:flex-row sm:flex-wrap sm:items-center rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6"
  >
    <button
      type="button"
      data-abrir
      class="flex flex-col flex-1 min-w-0 gap-2 rounded-lg text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('abrir')"
    >
      <span class="flex flex-wrap items-center gap-2">
        <span class="text-lg font-semibold break-words text-n-slate-12">
          {{ nome }}
        </span>
        <span
          data-origem
          class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full"
          :class="
            antiga
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-blue-3 text-n-blue-11'
          "
        >
          <span class="size-3" :class="selo.icone" aria-hidden="true" />
          {{ $t(selo.chave) }}
        </span>
      </span>
      <span
        data-frase
        class="flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-11"
      >
        <span
          class="px-2.5 py-1 font-medium break-words rounded-lg bg-n-blue-2 text-n-blue-11"
        >
          {{ quando }}
        </span>
        <span
          class="i-lucide-arrow-right size-4 text-n-slate-9 rtl:rotate-180"
          aria-hidden="true"
        />
        <span
          class="px-2.5 py-1 font-medium break-words rounded-lg bg-n-teal-2 text-n-teal-11"
        >
          {{ primeiro || $t('AUTOMACAO_LIVRE.LISTA.SEM_PASSO') }}
        </span>
        <span v-if="outros > 0" class="text-sm text-n-slate-10">
          {{ $t('AUTOMACAO_LIVRE.LISTA.MAIS_PASSOS', { n: outros }, outros) }}
        </span>
      </span>
      <span
        v-if="fato"
        data-fato
        class="flex items-center gap-1.5 text-sm text-n-slate-11"
      >
        <span class="i-lucide-activity size-4" aria-hidden="true" />
        {{ fato }}
      </span>
    </button>
    <Button
      data-alterar
      :label="$t('AUTOMACAO_LIVRE.LISTA.ABRIR')"
      :aria-label="$t('AUTOMACAO_LIVRE.LISTA.ABRIR_ROTULO', { nome })"
      icon="i-lucide-pencil"
      slate
      faded
      class="self-start min-h-11 sm:self-center shrink-0"
      @click="emit('abrir')"
    />
    <Button
      v-if="podeSerBloco && podeMudar"
      data-marcar-bloco
      :label="
        $t(
          bloco
            ? 'AUTOMACAO_LIVRE.LISTA.TIRAR_BLOCO'
            : 'AUTOMACAO_LIVRE.LISTA.USAR_COMO_BLOCO'
        )
      "
      icon="i-lucide-boxes"
      slate
      link
      class="self-start min-h-11 sm:self-center shrink-0"
      :disabled="mudando"
      @click="emit('bloco')"
    />
    <p
      v-if="bloco"
      data-bloco-aviso
      class="mb-0 text-sm text-n-slate-11 sm:order-last sm:basis-full"
    >
      {{ $t('AUTOMACAO_LIVRE.LISTA.BLOCO_AVISO') }}
    </p>
    <div
      v-else-if="pausa && !ativa"
      data-pausa
      role="status"
      class="flex flex-col gap-3 p-4 text-[0.9375rem] rounded-xl bg-n-amber-3 text-n-amber-12 sm:order-last sm:basis-full"
    >
      <p class="mb-0">
        <span class="block font-semibold">
          {{ $t('AUTOMACAO_LIVRE.LIGAR.PAUSADA') }}
        </span>
        {{ pausa }}
      </p>
      <template v-if="podeMudar">
        <p class="mb-0">{{ $t('AUTOMACAO_LIVRE.LIGAR.ASSUMIR_AVISO') }}</p>
        <Button
          data-assumir
          :label="$t('AUTOMACAO_LIVRE.LIGAR.ASSUMIR')"
          icon="i-lucide-power"
          teal
          class="self-start min-h-11"
          :disabled="mudando"
          @click="emit('alternar')"
        />
      </template>
    </div>
    <label
      v-if="!bloco && !(pausa && !ativa)"
      class="flex items-center self-start gap-3 px-3 select-none sm:self-center min-h-11 shrink-0"
      :class="
        podeMudar && !mudando
          ? 'cursor-pointer'
          : 'cursor-not-allowed opacity-60'
      "
    >
      <span
        class="text-sm font-semibold"
        :class="ativa ? 'text-n-teal-11' : 'text-n-slate-11'"
      >
        {{
          ativa ? $t('AUTOMACAO_LIVRE.LIGADA') : $t('AUTOMACAO_LIVRE.DESLIGADA')
        }}
      </span>
      <Switch
        data-interruptor
        class="mx-1.5 scale-[1.4]"
        :model-value="ativa"
        :disabled="!podeMudar || mudando"
        :aria-label="$t('AUTOMACAO_LIVRE.LISTA.INTERRUPTOR', { nome })"
        @update:model-value="emit('alternar')"
      />
    </label>
  </li>
</template>

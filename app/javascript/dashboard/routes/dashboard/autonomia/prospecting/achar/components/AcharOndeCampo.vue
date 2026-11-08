<script setup>
import { computed, ref, useId, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — o campo "Onde?" da porta (v4, T0, regra C4). Combobox editável: a
// pessoa escreve, as sugestões do Google aparecem logo abaixo (na própria
// linha, sem ficar presa no herói), e o teclado anda com as setas, Enter
// escolhe, Esc fecha. Escolhido, o campo vira o rótulo com um visto verde e o
// botão "Alterar". Quem decide uma sugestão só ser escolhida sozinha é a página.
const props = defineProps({
  lugar: { type: Object, default: null },
  sugestoes: { type: Array, default: () => [] },
  procurando: { type: Boolean, default: false },
  naoAchou: { type: Boolean, default: false },
  destacar: { type: Boolean, default: false },
  // Enquanto a IA lê o pedido em uma frase (#2696), o campo não muda.
  bloqueado: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher', 'alterar']);
const texto = defineModel('texto', { type: String, default: '' });
const id = useId();
const listaId = `${id}-lista`;
const campo = ref(null);
const ativo = ref(-1);
const aberta = computed(() => !props.lugar && props.sugestoes.length > 0);
const opcaoId = indice => `${id}-opcao-${indice}`;
// Várias sugestões e a pessoa ainda não tocou: a primeira já vem marcada
// (rodada 2), e Enter escolhe.
watch(
  () => props.destacar,
  destacar => {
    if (destacar) ativo.value = 0;
  },
  { immediate: true }
);

const escolher = sugestao => {
  ativo.value = -1;
  emit('escolher', sugestao);
};

const andar = passo => {
  if (!aberta.value) return;
  const total = props.sugestoes.length;
  ativo.value = (ativo.value + passo + total) % total;
};

const aoTeclar = evento => {
  if (evento.key === 'ArrowDown') {
    evento.preventDefault();
    andar(1);
  } else if (evento.key === 'ArrowUp') {
    evento.preventDefault();
    andar(-1);
  } else if (evento.key === 'Enter' && ativo.value >= 0 && aberta.value) {
    evento.preventDefault();
    escolher(props.sugestoes[ativo.value]);
  } else if (evento.key === 'Escape') {
    ativo.value = -1;
  }
};

// Enter ou "Achar" com várias sugestões abertas não busca: o foco vai para a
// primeira sugestão.
const focarPrimeira = () => {
  ativo.value = 0;
  campo.value?.focus();
};

defineExpose({ focarPrimeira });
</script>

<template>
  <div class="flex flex-col gap-1.5" data-onde>
    <label :for="id" class="text-sm font-semibold text-n-slate-11">
      {{ $t('PROSPECTING_ACHAR.PORTA.ONDE.ROTULO') }}
    </label>
    <div
      v-if="lugar"
      class="flex items-center gap-2 py-0.5 border min-h-12 rounded-xl border-n-teal-7 bg-n-teal-2 ps-3 pe-1"
      data-lugar-escolhido
    >
      <span
        class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
        :aria-label="$t('PROSPECTING_ACHAR.PORTA.ONDE.ESCOLHIDO')"
        role="img"
      />
      <span class="flex-1 min-w-0 text-base break-words text-n-slate-12">
        {{ lugar.rotulo }}
      </span>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.ALTERAR')"
        slate
        faded
        class="!min-h-11 !rounded-xl shrink-0"
        :disabled="bloqueado"
        data-alterar-lugar
        @click="emit('alterar')"
      />
    </div>
    <template v-else>
      <input
        :id="id"
        ref="campo"
        v-model="texto"
        type="text"
        role="combobox"
        autocomplete="off"
        aria-autocomplete="list"
        :aria-expanded="aberta"
        :aria-controls="listaId"
        :aria-activedescendant="ativo >= 0 ? opcaoId(ativo) : undefined"
        :placeholder="$t('PROSPECTING_ACHAR.PORTA.ONDE.PLACEHOLDER')"
        :disabled="bloqueado"
        class="w-full !h-12 px-3 text-base border outline-none !mb-0 rounded-xl border-n-slate-6 bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-blue-9"
        data-campo-onde
        @keydown="aoTeclar"
      />
      <p
        v-if="procurando"
        class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
        role="status"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin" />
        {{ $t('PROSPECTING_ACHAR.PORTA.ONDE.PROCURANDO') }}
      </p>
      <p
        v-else-if="naoAchou"
        class="m-0 text-sm text-n-ruby-11"
        role="status"
        data-nao-achou
      >
        {{ $t('PROSPECTING_ACHAR.PORTA.ONDE.NADA') }}
      </p>
      <ul
        v-if="aberta"
        :id="listaId"
        role="listbox"
        class="flex flex-col gap-0.5 p-1 m-0 list-none rounded-xl bg-n-solid-1"
        :class="destacar ? 'border-2 border-n-blue-9' : 'border border-n-weak'"
        data-sugestoes
      >
        <li
          v-for="(sugestao, indice) in sugestoes"
          :id="opcaoId(indice)"
          :key="sugestao.placeId"
          role="option"
          :aria-selected="indice === ativo"
          class="flex items-center gap-2 px-3 text-base rounded-lg cursor-pointer min-h-11 text-n-slate-12 hover:bg-n-slate-3"
          :class="indice === ativo ? 'bg-n-blue-3' : ''"
          data-sugestao
          @mousedown.prevent="escolher(sugestao)"
        >
          <span
            class="i-lucide-map-pin size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          {{ sugestao.rotulo }}
        </li>
      </ul>
    </template>
  </div>
</template>

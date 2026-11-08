<script setup>
// #1459 — o cabeçalho escuro da gaveta, com a mesma anatomia do herói do
// funil (#1384): anéis decorativos, migalha, rótulo com ícone, título e uma
// frase. A migalha só diz de onde a pessoa veio.
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';
import { nomeEhTelefone } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

const props = defineProps({
  tituloId: { type: String, required: true },
  migalha: { type: String, default: '' },
  // { chave, nome }: o nome entra por slot do <I18nT> (#2255).
  titulo: { type: Object, required: true },
  texto: { type: String, default: '' },
  // #1505 — "Enviar mensagem" quando a mensagem entra numa conversa que já existe.
  naExistente: { type: Boolean, default: false },
});

defineEmits(['fechar']);

// #2255: o telefone não quebra a linha no hífen; nome com espaços quebra normal.
const classeDoNome = computed(() =>
  nomeEhTelefone(props.titulo.nome) ? 'whitespace-nowrap' : ''
);
</script>

<template>
  <header
    data-nova-conversa-heroi
    class="relative shrink-0 overflow-hidden bg-[#0D2344] px-5 py-5 text-white sm:px-8"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-80 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -bottom-36 end-32 size-56 rounded-full border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex items-start gap-4">
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <span
          class="inline-flex min-h-11 items-center text-sm font-medium text-white/75"
        >
          {{ migalha }}
        </span>
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6"
        >
          <span
            class="size-4"
            :class="
              naExistente
                ? 'i-lucide-message-circle'
                : 'i-lucide-message-circle-plus'
            "
            aria-hidden="true"
          />
          {{
            naExistente
              ? $t('NOVA_CONVERSA.ROTULO_EXISTENTE')
              : $t('NOVA_CONVERSA.ROTULO')
          }}
        </span>
        <h2
          :id="tituloId"
          data-view-title
          tabindex="-1"
          class="mb-0 break-words text-2xl font-bold leading-tight tracking-tight text-white outline-none"
        >
          <I18nT v-if="titulo.nome" :keypath="titulo.chave" tag="span">
            <template #nome>
              <span :class="classeDoNome">{{ titulo.nome }}</span>
            </template>
          </I18nT>
          <template v-else>{{ $t(titulo.chave) }}</template>
        </h2>
        <p
          v-if="texto"
          class="mb-0 text-sm leading-relaxed text-white/75 sm:text-base"
        >
          {{ texto }}
        </p>
      </div>
      <button
        type="button"
        data-nova-conversa-fechar
        :aria-label="$t('NOVA_CONVERSA.FECHAR')"
        class="grid size-11 shrink-0 place-items-center rounded-xl text-white/80 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="$emit('fechar')"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>
  </header>
</template>

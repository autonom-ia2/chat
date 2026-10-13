<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaCartao from './NovaConversaCartao.vue';
import NovaConversaOpcao from './NovaConversaOpcao.vue';
import { chaveDoCanal, linhaDoCanal } from './novaConversa';
import { SINAIS } from './modeloPronto';

// #1459 — "Por onde": os canais em que o contato pode ser alcançado. Um só
// vira frase; vários viram opções lado a lado, com o primeiro já marcado.
// Contato sem canal nenhum tem tela própria (NovaConversaSemCanal).
defineProps({
  canais: { type: Array, default: () => [] },
  carregando: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
});

defineEmits(['tentar']);

const canalId = defineModel({ type: Number, default: null });

const { t } = useI18n();
const P = 'NOVA_CONVERSA.POR_ONDE';
const tipoDe = canal => t(`${P}.CANAL.${chaveDoCanal(canal)}`);
const nomeDe = canal => `${tipoDe(canal)} ${SINAIS.ponto} ${canal.name}`;
const entreParenteses = texto =>
  `${SINAIS.abreParenteses}${texto}${SINAIS.fechaParenteses}`;
</script>

<template>
  <p
    v-if="carregando"
    aria-live="polite"
    class="mb-0 flex min-h-11 items-center gap-2 text-[0.9375rem] text-n-slate-11"
  >
    <span
      class="i-lucide-loader-circle size-4 animate-spin"
      aria-hidden="true"
    />
    {{ $t(`${P}.CARREGANDO`) }}
  </p>

  <div
    v-else-if="erro"
    data-nova-conversa-erro-canais
    role="alert"
    class="flex flex-col items-start gap-3 rounded-2xl border border-dashed border-n-amber-8 bg-n-amber-2 p-4 sm:flex-row sm:items-center"
  >
    <span class="flex min-w-0 flex-1 items-start gap-3">
      <span
        class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span class="text-[0.9375rem] text-n-slate-12">
        {{ $t(`${P}.ERRO`) }}
      </span>
    </span>
    <Button
      :label="$t(`${P}.TENTAR`)"
      slate
      faded
      class="!min-h-11 shrink-0"
      @click="$emit('tentar')"
    />
  </div>

  <NovaConversaCartao
    v-else-if="canais.length === 1"
    :icone="canais[0].icon"
    tom="bg-n-teal-3 text-n-teal-11"
    :titulo="$t(`${P}.TITULO`)"
    sem-alterar
  >
    <strong class="font-semibold">{{ nomeDe(canais[0]) }}</strong>
    <template v-if="linhaDoCanal(canais[0])">
      {{ entreParenteses(linhaDoCanal(canais[0])) }}
    </template>
  </NovaConversaCartao>

  <fieldset
    v-else-if="canais.length"
    class="m-0 grid min-w-0 gap-3 border-0 p-0 sm:grid-cols-2"
  >
    <legend class="mb-3 p-0 text-base font-semibold text-n-slate-12">
      {{ $t(`${P}.TITULO`) }}
    </legend>
    <NovaConversaOpcao
      v-for="canal in canais"
      :key="canal.id"
      v-model="canalId"
      name="nova-conversa-canal"
      :value="canal.id"
      :icone="canal.icon"
      :titulo="nomeDe(canal)"
      :descricao="linhaDoCanal(canal)"
    />
  </fieldset>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaCartao from './NovaConversaCartao.vue';
import NovaConversaOpcao from './NovaConversaOpcao.vue';
import { DESTINOS, chaveDaSituacao } from './continuarConversa';
import { SINAIS } from './modeloPronto';

// #1505 — o contato já tem conversa nesta caixa. Com a regra "Reabrir a
// mesma conversa", uma frase diz onde a mensagem entra (sem número, se a
// pessoa não pode ver a conversa); com "Criar novas
// conversas", a pessoa escolhe entre continuar a conversa (já marcada) e
// começar outra. Enquanto confere o que a conversa aceita, avisa; se não
// conseguir, oferece tentar de novo.
const props = defineProps({
  conversa: { type: Object, required: true },
  carregando: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
});

defineEmits(['tentar']);

const destino = defineModel({ type: String, default: DESTINOS.CONTINUAR });

const { t, locale } = useI18n();
const P = 'NOVA_CONVERSA.ONDE_ENTRA';

const numero = computed(() => props.conversa.displayId);
const situacao = computed(() =>
  t(`${P}.SITUACAO.${chaveDaSituacao(props.conversa.status)}`)
);
const quando = computed(() =>
  props.conversa.lastActivityAt
    ? t(`${P}.ULTIMA_ATIVIDADE`, {
        quando: dynamicTime(props.conversa.lastActivityAt, locale?.value),
      })
    : ''
);
const resumo = computed(() =>
  [situacao.value, quando.value].filter(Boolean).join(` ${SINAIS.ponto} `)
);
</script>

<template>
  <section data-nova-conversa-onde-entra class="flex flex-col gap-3">
    <NovaConversaCartao
      v-if="conversa.locked"
      data-nova-conversa-entra-na
      icone="i-lucide-messages-square"
      tom="bg-n-teal-3 text-n-teal-11"
      :titulo="$t(`${P}.TITULO`)"
      sem-alterar
    >
      <template v-if="conversa.visible">
        <strong class="font-semibold">
          {{ $t(`${P}.ENTRA_NA`, { numero }) }}
        </strong>
        <span class="block text-sm text-n-slate-11">{{ resumo }}</span>
      </template>
      <!-- A pessoa não pode ver a conversa (acesso por funil): sem número nem
           situação, só o aviso de que não nasce outra. -->
      <strong
        v-else
        data-nova-conversa-entra-na-existente
        class="font-semibold"
      >
        {{ $t(`${P}.ENTRA_NA_EXISTENTE`) }}
      </strong>
    </NovaConversaCartao>

    <fieldset v-else class="m-0 grid min-w-0 gap-3 border-0 p-0 sm:grid-cols-2">
      <legend class="mb-3 p-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${P}.TITULO`) }}
      </legend>
      <NovaConversaOpcao
        v-model="destino"
        data-nova-conversa-continuar
        name="nova-conversa-destino"
        :value="DESTINOS.CONTINUAR"
        icone="i-lucide-messages-square"
        :titulo="$t(`${P}.CONTINUAR`, { numero })"
        :descricao="resumo"
      />
      <NovaConversaOpcao
        v-model="destino"
        data-nova-conversa-comecar
        name="nova-conversa-destino"
        :value="DESTINOS.NOVA"
        icone="i-lucide-message-square-plus"
        :titulo="$t(`${P}.NOVA`)"
        :descricao="$t(`${P}.NOVA_TEXTO`)"
      />
    </fieldset>

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
      data-nova-conversa-erro-conversa
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
  </section>
</template>

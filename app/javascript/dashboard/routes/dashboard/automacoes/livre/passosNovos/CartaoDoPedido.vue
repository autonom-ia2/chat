<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CrmKanbanCard from 'dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue';
import { P } from './passosNovos';

// #2931 — o pedido de aprovação como quem aprova vê: a pergunta, o prazo, dois
// botões grandes e o card ao lado. Recusar pede um motivo, que é opcional. A
// mesma peça serve à prévia do editor ("Ver como quem aprova") e à tela
// "Pedidos de aprovação"; quem usa decide o que a resposta faz.
const props = defineProps({
  pergunta: { type: String, default: '' },
  linhaDoPrazo: { type: String, default: '' },
  card: { type: Object, default: null },
  comValor: { type: Boolean, default: false },
  // null: aberto; 'aprovado' | 'recusado': respondido; 'encerrado': o prazo
  // acabou ou a automação parou antes da resposta.
  estado: { type: String, default: null },
  // Respondido: quem respondeu (vazio quando foi quem olha) e o motivo.
  porNome: { type: String, default: '' },
  motivoDito: { type: String, default: '' },
  enviando: { type: Boolean, default: false },
});

const emit = defineEmits(['aprovar', 'recusar']);
const recusando = ref(false);
const motivo = ref('');

const feito = computed(() =>
  ['aprovado', 'recusado'].includes(props.estado) ? props.estado : null
);
const chaveDoFeito = computed(() =>
  props.porNome ? `${feito.value.toUpperCase()}_POR` : feito.value.toUpperCase()
);

const recusar = () => emit('recusar', motivo.value.trim());
</script>

<template>
  <div
    data-pedido
    class="grid items-start gap-6 md:grid-cols-[minmax(0,1fr)_18rem]"
  >
    <div class="flex flex-col gap-5">
      <div class="flex flex-col gap-2 p-5 rounded-2xl bg-n-solid-1">
        <span class="text-sm text-n-slate-11">
          {{ $t(`${P}.PEDIDO.PERGUNTA_DE`) }}
        </span>
        <p
          data-pedido-pergunta
          class="mb-0 text-xl font-semibold leading-snug text-n-slate-12"
        >
          {{ pergunta || $t(`${P}.PEDIDO.SEM_PERGUNTA`) }}
        </p>
        <p v-if="linhaDoPrazo" class="mb-0 text-sm text-n-slate-11">
          {{ linhaDoPrazo }}
        </p>
      </div>

      <div
        v-if="feito"
        data-pedido-feito
        role="status"
        class="flex items-start gap-3 p-5 rounded-2xl"
        :class="
          feito === 'aprovado'
            ? 'bg-n-teal-3 text-n-teal-12'
            : 'bg-n-ruby-3 text-n-ruby-12'
        "
      >
        <span
          class="mt-0.5 size-5 shrink-0"
          :class="
            feito === 'aprovado' ? 'i-lucide-check-circle' : 'i-lucide-x-circle'
          "
          aria-hidden="true"
        />
        <div class="flex flex-col gap-1">
          <p class="mb-0 text-base font-semibold">
            {{
              porNome
                ? $t(`${P}.PEDIDO.${chaveDoFeito}`, { nome: porNome })
                : $t(`${P}.PEDIDO.${chaveDoFeito}`)
            }}
          </p>
          <p v-if="feito === 'recusado' && motivoDito" class="mb-0 text-sm">
            {{ $t(`${P}.PEDIDO.MOTIVO_DITO`, { motivo: motivoDito }) }}
          </p>
        </div>
      </div>

      <p
        v-else-if="estado === 'encerrado'"
        data-pedido-encerrado
        role="status"
        class="p-5 mb-0 text-base rounded-2xl bg-n-solid-2 text-n-slate-12"
      >
        {{ $t(`${P}.PEDIDO.ENCERRADO`) }}
      </p>

      <div v-else-if="recusando" class="flex flex-col gap-3">
        <TextArea
          v-model="motivo"
          data-pedido-motivo
          :label="$t(`${P}.PEDIDO.MOTIVO`)"
          :placeholder="$t(`${P}.PEDIDO.MOTIVO_EXEMPLO`)"
          :max-length="500"
        />
        <div class="flex flex-col gap-3 sm:flex-row">
          <Button
            data-pedido-confirmar-recusa
            type="button"
            :label="$t(`${P}.PEDIDO.CONFIRMAR_RECUSA`)"
            icon="i-lucide-x"
            ruby
            lg
            :is-loading="enviando"
            :disabled="enviando"
            class="justify-center w-full min-h-14 sm:flex-1"
            @click="recusar"
          />
          <Button
            type="button"
            :label="$t(`${P}.PEDIDO.VOLTAR`)"
            slate
            faded
            lg
            :disabled="enviando"
            class="justify-center w-full min-h-14 sm:w-auto"
            @click="recusando = false"
          />
        </div>
      </div>

      <div v-else class="grid gap-3 sm:grid-cols-2">
        <Button
          data-pedido-aprovar
          type="button"
          :label="$t(`${P}.PEDIDO.APROVAR`)"
          icon="i-lucide-check"
          teal
          lg
          :is-loading="enviando"
          :disabled="enviando"
          class="justify-center w-full text-lg min-h-16"
          @click="emit('aprovar')"
        />
        <Button
          data-pedido-recusar
          type="button"
          :label="$t(`${P}.PEDIDO.RECUSAR`)"
          icon="i-lucide-x"
          ruby
          faded
          lg
          :disabled="enviando"
          class="justify-center w-full text-lg min-h-16"
          @click="recusando = true"
        />
      </div>
    </div>

    <aside v-if="card" class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-11">
        {{ $t(`${P}.PEDIDO.CARD`) }}
      </span>
      <CrmKanbanCard
        :card="card"
        :com-valor="comValor"
        stage-color="#2781F6"
        standalone
      />
    </aside>
  </div>
</template>

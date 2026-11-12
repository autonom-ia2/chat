<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CrmKanbanCard from 'dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue';
import { fraseDoValor } from '../frases';
import { usePodeLerValor } from '../usePodeLerValor';
import { P, PRAZO_PADRAO } from './passosNovos';
import { cardDoPedido, valorDeExemplo } from './adaptadorFalso';
import { duracaoEmFrase, quemEmFrase } from './frasesDosNovos';

// #2931 — o lado de quem aprova: o pedido no painel, com o card ao lado e dois
// botões grandes. Recusar pede um motivo, que é opcional. No protótipo a
// resposta fica só na tela (o adaptador não grava nada).
const props = defineProps({
  passo: { type: Object, required: true },
  catalogo: { type: Object, required: true },
});

const { t } = useI18n();
const dialogo = ref(null);
// null: escolhendo; 'recusando': escrevendo o motivo; 'aprovado' | 'recusado'.
const estado = ref(null);
const motivo = ref('');

const VALOR = 'sales_value_view';
const podeLer = usePodeLerValor();
const podeVerValor = computed(() => podeLer.value(VALOR));
const card = computed(() => cardDoPedido(t));

// O dado do texto sai com o valor de exemplo; o valor do card, oculto para
// quem não pode ver valores.
const pergunta = computed(() =>
  (props.passo.pergunta || [])
    .map(parte =>
      typeof parte === 'string'
        ? parte
        : valorDeExemplo(parte.$valor, podeVerValor.value, t) ||
          fraseDoValor(parte.$valor, props.catalogo, t)
    )
    .join('')
    .trim()
);
const prazo = computed(() =>
  duracaoEmFrase(props.passo.prazo || PRAZO_PADRAO, t)
);

const abrir = () => {
  estado.value = null;
  motivo.value = '';
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="3xl"
    :title="$t(`${P}.PEDIDO.TITULO`)"
    :description="$t(`${P}.PEDIDO.SUBTITULO`)"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
  >
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
          <p class="mb-0 text-sm text-n-slate-11">
            {{
              $t(`${P}.PEDIDO.PRAZO`, {
                prazo,
                quem: quemEmFrase(passo.quem, t),
              })
            }}
          </p>
        </div>

        <div
          v-if="estado === 'aprovado' || estado === 'recusado'"
          data-pedido-feito
          role="status"
          class="flex items-start gap-3 p-5 rounded-2xl"
          :class="
            estado === 'aprovado'
              ? 'bg-n-teal-3 text-n-teal-12'
              : 'bg-n-ruby-3 text-n-ruby-12'
          "
        >
          <span
            class="mt-0.5 size-5 shrink-0"
            :class="
              estado === 'aprovado'
                ? 'i-lucide-check-circle'
                : 'i-lucide-x-circle'
            "
            aria-hidden="true"
          />
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-base font-semibold">
              {{ $t(`${P}.PEDIDO.${estado.toUpperCase()}`) }}
            </p>
            <p
              v-if="estado === 'recusado' && motivo.trim()"
              class="mb-0 text-sm"
            >
              {{ $t(`${P}.PEDIDO.MOTIVO_DITO`, { motivo: motivo.trim() }) }}
            </p>
          </div>
        </div>

        <div v-else-if="estado === 'recusando'" class="flex flex-col gap-3">
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
              class="justify-center w-full min-h-14 sm:flex-1"
              @click="estado = 'recusado'"
            />
            <Button
              type="button"
              :label="$t(`${P}.PEDIDO.VOLTAR`)"
              slate
              faded
              lg
              class="justify-center w-full min-h-14 sm:w-auto"
              @click="estado = null"
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
            class="justify-center w-full text-lg min-h-16"
            @click="estado = 'aprovado'"
          />
          <Button
            data-pedido-recusar
            type="button"
            :label="$t(`${P}.PEDIDO.RECUSAR`)"
            icon="i-lucide-x"
            ruby
            faded
            lg
            class="justify-center w-full text-lg min-h-16"
            @click="estado = 'recusando'"
          />
        </div>
      </div>

      <aside class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-11">
          {{ $t(`${P}.PEDIDO.CARD`) }}
        </span>
        <CrmKanbanCard
          :card="card"
          :com-valor="podeVerValor"
          stage-color="#2781F6"
          standalone
        />
      </aside>
    </div>

    <template #footer>
      <div class="flex justify-end">
        <Button
          data-pedido-fechar
          type="button"
          :label="$t(`${P}.PEDIDO.FECHAR`)"
          slate
          link
          class="min-h-11"
          @click="fechar"
        />
      </div>
    </template>
  </Dialog>
</template>

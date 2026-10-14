<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmCardAutoFollowupStatus from '../../CrmCardAutoFollowupStatus.vue';
import CampoQuando from '../CampoQuando.vue';
import { atrasado } from '../proximoPasso';
import { atalhosDeData } from '../atalhosDeData';

// #1423 — os retornos do card. "Combinado com o cliente": o atrasado em
// vermelho, com Feito e Cancelar na própria linha (RT-02). Depois, o "Chamar
// de volta sozinho" (RT-13) e, recolhidos, os feitos ou cancelados (RT-14).
// "Adiar" abre a data e a hora na própria linha (a mesma rota do arrastar no
// calendário, rescheduleFollowUp).
const props = defineProps({
  card: { type: Object, required: true },
  retornos: { type: Array, default: () => [] },
  formato: { type: Object, required: true },
  carregando: { type: Boolean, default: false },
  salvando: { type: Boolean, default: false },
  podeGerenciar: { type: Boolean, default: false },
  podeIa: { type: Boolean, default: false },
  podeRegistros: { type: Boolean, default: false },
});
const emit = defineEmits(['feito', 'cancelar', 'adiar', 'mudou']);

const { t } = useI18n();
const R = 'CRM_CARD.RETORNOS';
const ABERTOS = ['pending', 'overdue'];
const agora = new Date();
const abertos = computed(() =>
  props.retornos
    .filter(item => ABERTOS.includes(item.status))
    .sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
    .map(item => ({ ...item, atrasado: atrasado(item, agora) }))
);
const fechados = computed(() =>
  props.retornos.filter(item => !ABERTOS.includes(item.status))
);
const MODO = {
  reminder_only: 'LEMBRETE',
  snooze_conversation: 'ESCONDER',
  auto_send_message: 'MENSAGEM',
};
const modo = item =>
  t(`CRM_CARD.RETORNO.MODO.${MODO[item.automation_mode] || 'LEMBRETE'}.CURTO`);
const adiando = ref(null);
const novaData = ref('');
const atalhos = computed(() => atalhosDeData(t));
const abrirAdiar = item => {
  adiando.value = item.id;
  novaData.value = '';
};
const confirmarAdiar = item => {
  if (!novaData.value) return;
  emit('adiar', { item, quando: new Date(novaData.value).toISOString() });
  adiando.value = null;
};
const situacao = item =>
  t(`CRM_KANBAN.FOLLOW_UP_STATUS.${String(item.status).toUpperCase()}`);
</script>

<template>
  <section class="flex flex-col gap-5" data-agenda-retornos>
    <p
      v-if="carregando"
      role="status"
      class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" aria-hidden="true" />
      {{ t('CRM_CARD.CARREGANDO') }}
    </p>

    <section class="flex flex-col gap-3">
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${R}.COMBINADO`) }}
      </h3>
      <ul v-if="abertos.length" class="m-0 flex list-none flex-col gap-3 p-0">
        <li
          v-for="item in abertos"
          :key="item.id"
          :data-retorno="item.atrasado ? 'atrasado' : 'marcado'"
          class="flex flex-col gap-3 rounded-2xl border bg-n-solid-1 p-4 shadow-sm sm:p-5"
          :class="
            item.atrasado ? 'border-n-ruby-7 bg-n-ruby-2' : 'border-n-weak'
          "
        >
          <div class="flex items-start gap-3">
            <span
              class="grid size-10 shrink-0 place-items-center rounded-2xl"
              :class="
                item.atrasado
                  ? 'bg-n-ruby-3 text-n-ruby-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
              aria-hidden="true"
            >
              <span
                class="size-5"
                :class="
                  item.atrasado ? 'i-lucide-alarm-clock' : 'i-lucide-bell-ring'
                "
              />
            </span>
            <div class="flex min-w-0 flex-1 flex-col gap-1">
              <span
                class="w-fit rounded-lg px-2 py-0.5 text-sm font-medium"
                :class="
                  item.atrasado
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-amber-3 text-n-amber-11'
                "
              >
                {{
                  item.atrasado
                    ? t(`${R}.ATRASADO`, {
                        quando: formato.quando(item.due_at),
                      })
                    : formato.quando(item.due_at)
                }}
              </span>
              <p class="mb-0 text-base font-semibold text-n-slate-12">
                {{ item.title }}
              </p>
              <p class="mb-0 text-sm text-n-slate-11">{{ modo(item) }}</p>
              <p v-if="item.description" class="mb-0 text-sm text-n-slate-12">
                {{ item.description }}
              </p>
            </div>
          </div>
          <div
            v-if="podeGerenciar"
            class="flex flex-wrap gap-2 sm:ps-[3.25rem]"
          >
            <Button
              :label="t(`${R}.FEITO`)"
              icon="i-lucide-check"
              slate
              outline
              class="!min-h-11 !outline-n-weak"
              :is-loading="salvando"
              @click="emit('feito', item)"
            />
            <Button
              data-retorno-adiar
              :label="t(`${R}.ADIAR`)"
              icon="i-lucide-calendar-clock"
              slate
              ghost
              class="!min-h-11"
              :disabled="salvando"
              @click="abrirAdiar(item)"
            />
            <Button
              :label="t(`${R}.CANCELAR`)"
              icon="i-lucide-x"
              ruby
              ghost
              class="!min-h-11"
              :disabled="salvando"
              @click="emit('cancelar', item)"
            />
          </div>
          <div
            v-if="adiando === item.id"
            data-retorno-adiar-quando
            class="flex flex-col gap-3 border-t border-n-weak pt-3 sm:ps-[3.25rem]"
          >
            <CampoQuando
              v-model="novaData"
              :rotulo="t(`${R}.ADIAR_PARA`)"
              :atalhos="atalhos"
            />
            <span class="flex flex-wrap gap-2">
              <Button
                data-retorno-adiar-confirma
                :label="t(`${R}.ADIAR_CONFIRMA`)"
                icon="i-lucide-check"
                class="!min-h-11"
                :disabled="!novaData || salvando"
                @click="confirmarAdiar(item)"
              />
              <Button
                :label="t('CRM_CARD.CANCELAR')"
                slate
                ghost
                class="!min-h-11"
                @click="adiando = null"
              />
            </span>
          </div>
        </li>
      </ul>
      <div
        v-else-if="!carregando"
        class="rounded-2xl border border-dashed border-n-weak px-4 py-8 text-center"
      >
        <p class="mb-0 text-base text-n-slate-12">{{ t(`${R}.VAZIO`) }}</p>
      </div>
    </section>

    <CrmCardAutoFollowupStatus
      :card="card"
      :can-manage-ai="podeIa"
      :can-manage-records="podeRegistros"
      textos="CRM_CARD.CHAMAR"
      @reset="emit('mudou')"
    />

    <details
      v-if="fechados.length"
      class="group rounded-2xl border border-n-weak bg-n-solid-1"
    >
      <summary
        class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
      >
        {{ t(`${R}.FECHADOS`, { n: fechados.length }) }}
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
          aria-hidden="true"
        />
      </summary>
      <ul
        class="m-0 flex list-none flex-col divide-y divide-n-weak border-t border-n-weak p-0"
      >
        <li
          v-for="item in fechados"
          :key="item.id"
          class="flex items-start justify-between gap-3 px-4 py-3"
        >
          <span class="flex min-w-0 flex-col">
            <span class="text-sm font-medium text-n-slate-12">{{
              item.title
            }}</span>
            <span class="text-sm text-n-slate-11">
              {{ [formato.quando(item.due_at), modo(item)].join(' · ') }}
            </span>
            <span v-if="item.description" class="text-sm text-n-slate-11">{{
              item.description
            }}</span>
          </span>
          <span
            class="shrink-0 rounded-lg bg-n-slate-4 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ situacao(item) }}
          </span>
        </li>
      </ul>
    </details>
  </section>
</template>

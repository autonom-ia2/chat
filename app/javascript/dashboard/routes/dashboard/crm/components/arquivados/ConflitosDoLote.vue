<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { motivoDoPulado } from './motivoDoErro';

// O fim do "Restaurar (N)" (#2095, decisão 9 revisada): os cards sem conflito já voltaram; os de cliente que já tem
// card aberto no mesmo funil aparecem lado a lado (o arquivado e o aberto, com título e etapa), com "Restaurar mesmo
// assim" por linha e para todos. Os pulados por outro motivo também aparecem, com o motivo: nada fica calado.
const props = defineProps({
  // [{ id, error, open_card?: { id, title, stage_name }, arquivado: { title, stage_name } }]
  pulados: { type: Array, required: true },
  ocupados: { type: Object, default: () => ({}) },
  erros: { type: Object, default: () => ({}) },
  ocupadoTodos: { type: Boolean, default: false },
});
const emit = defineEmits(['forcar', 'forcarTodos', 'abrirCard', 'fechar']);

const { t } = useI18n();
const CONFLITO = 'crm.card_restore_conflict';
const conflitos = computed(() =>
  props.pulados.filter(item => item.error === CONFLITO)
);
const outros = computed(() =>
  props.pulados.filter(item => item.error !== CONFLITO)
);
</script>

<template>
  <section
    data-conflitos-do-lote
    class="flex flex-col gap-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3"
  >
    <template v-if="conflitos.length">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{
          t(
            'CRM_ARQUIVADOS.LOTE.CONFLITOS_TITULO',
            { count: conflitos.length },
            conflitos.length
          )
        }}
      </h3>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_ARQUIVADOS.LOTE.CONFLITOS_TEXTO') }}
      </p>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="item in conflitos"
          :key="item.id"
          data-conflito-linha
          class="flex flex-col gap-2 rounded-lg bg-n-solid-1 p-3"
        >
          <div class="grid gap-2 sm:grid-cols-2">
            <div class="min-w-0">
              <p class="mb-0 text-xs font-medium text-n-slate-11">
                {{ t('CRM_ARQUIVADOS.LOTE.ARQUIVADO') }}
              </p>
              <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                {{ item.arquivado?.title }}
              </p>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ item.arquivado?.stage_name }}
              </p>
            </div>
            <div class="min-w-0">
              <p class="mb-0 text-xs font-medium text-n-slate-11">
                {{ t('CRM_ARQUIVADOS.LOTE.ABERTO') }}
              </p>
              <template v-if="item.open_card">
                <button
                  type="button"
                  class="block min-h-11 max-w-full truncate rounded text-start text-sm font-medium text-n-blue-11 underline-offset-2 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                  @click="emit('abrirCard', item.open_card.id)"
                >
                  {{ item.open_card.title }}
                </button>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ item.open_card.stage_name }}
                </p>
              </template>
              <p v-else class="mb-0 text-sm text-n-slate-11">
                {{ t('CRM_ARQUIVADOS.LOTE.ABERTO_SEM_ACESSO') }}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <Button
              data-conflito-forcar-um
              :label="t('CRM_ARQUIVADOS.CONFLITO.MESMO_ASSIM')"
              slate
              faded
              class="!min-h-11"
              :is-loading="Boolean(ocupados[item.id])"
              :disabled="Boolean(ocupados[item.id]) || ocupadoTodos"
              @click="emit('forcar', item.id)"
            />
          </div>
          <p
            v-if="erros[item.id]"
            role="alert"
            class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
          >
            {{ erros[item.id] }}
          </p>
        </li>
      </ul>
      <div class="flex flex-wrap gap-2">
        <Button
          v-if="conflitos.length > 1"
          data-conflito-forcar-todos
          :label="t('CRM_ARQUIVADOS.LOTE.TODOS_MESMO_ASSIM')"
          slate
          faded
          class="!min-h-11"
          :is-loading="ocupadoTodos"
          :disabled="ocupadoTodos"
          @click="
            emit(
              'forcarTodos',
              conflitos.map(item => item.id)
            )
          "
        />
      </div>
    </template>
    <template v-if="outros.length">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{
          t(
            'CRM_ARQUIVADOS.LOTE.OUTROS_TITULO',
            { count: outros.length },
            outros.length
          )
        }}
      </h3>
      <ul class="m-0 flex list-none flex-col gap-1 p-0">
        <li
          v-for="item in outros"
          :key="item.id"
          data-pulado-linha
          class="text-sm text-n-slate-12"
        >
          {{
            t('CRM_ARQUIVADOS.LOTE.PULADO', {
              nome: item.arquivado?.title || `#${item.id}`,
              motivo: motivoDoPulado(t, item.error),
            })
          }}
        </li>
      </ul>
    </template>
    <div>
      <Button
        :label="t('CRM_ARQUIVADOS.LOTE.ENTENDI')"
        slate
        ghost
        class="!min-h-11"
        @click="emit('fechar')"
      />
    </div>
  </section>
</template>

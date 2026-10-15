<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { diaDaParede, diaLongo, horaDe, paredeDe } from './recorrencia';

// #1461 — um lembrete de uma vez só, sem card, aberto pelo calendário: o que
// é, quando, de quem e as duas ações da linha do card (Feito e Cancelar).
const props = defineProps({
  followUpId: { type: [Number, String], required: true },
});
const emit = defineEmits(['mudou', 'carregou']);

const { t, locale } = useI18n();
const U = 'CRM_LEMBRETE.UNICO';
const item = ref(null);
const erro = ref(false);
const salvando = ref(false);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await CrmKanbanAPI.getFollowUp(props.followUpId);
    item.value = data.payload;
    emit('carregou', item.value);
  } catch {
    erro.value = true;
  }
};
onMounted(carregar);

const quando = computed(() => {
  if (!item.value) return '';
  const texto = paredeDe(item.value.due_at, item.value.timezone);
  return t(`${U}.QUANDO`, {
    dia: diaLongo(diaDaParede(texto), locale.value.replace('_', '-')),
    hora: horaDe(texto),
    fuso: rotuloDoFuso(item.value.timezone),
  });
});
const aberto = computed(() =>
  ['pending', 'overdue'].includes(item.value?.status)
);
const agir = async (acao, aviso) => {
  salvando.value = true;
  try {
    await acao(item.value.id);
    useAlert(aviso);
    await carregar();
    emit('mudou');
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'));
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <p
    v-if="erro"
    role="alert"
    class="mb-0 rounded-2xl border border-n-ruby-7 bg-n-ruby-2 p-4 text-n-ruby-11"
  >
    {{ t('CRM_LEMBRETE.SERIE.ERRO_CARREGAR') }}
  </p>
  <article
    v-else-if="item"
    data-lembrete-unico
    class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
  >
    <div class="flex items-start gap-4">
      <span
        class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-amber-3 text-n-amber-11"
        aria-hidden="true"
      >
        <span class="i-lucide-bell-ring size-6" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <span
          class="w-fit rounded-lg bg-n-alpha-2 px-2 py-0.5 text-sm font-medium text-n-slate-11"
        >
          {{ t(`CRM_KANBAN.FOLLOW_UP_STATUS.${item.status.toUpperCase()}`) }}
        </span>
        <p class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ quando }}
        </p>
        <p v-if="item.company" class="mb-0 text-sm text-n-slate-11">
          {{ t(`${U}.EMPRESA`, { nome: item.company.name }) }}
        </p>
        <p v-if="item.contact" class="mb-0 text-sm text-n-slate-11">
          {{
            t('CRM_LEMBRETE.SERIE.LIGADO_CONTATO', { nome: item.contact.name })
          }}
        </p>
        <p v-if="item.description" class="mb-0 text-sm text-n-slate-12">
          {{ item.description }}
        </p>
      </div>
    </div>
    <div v-if="aberto" class="flex flex-wrap gap-2 sm:ps-16">
      <Button
        data-unico-feito
        :label="t('CRM_CARD.RETORNOS.FEITO')"
        icon="i-lucide-check"
        slate
        outline
        class="!min-h-11 !outline-n-weak"
        :disabled="salvando"
        @click="
          agir(
            CrmKanbanAPI.completeFollowUp.bind(CrmKanbanAPI),
            t(`${U}.FEITO_OK`)
          )
        "
      />
      <Button
        data-unico-cancelar
        :label="t('CRM_CARD.RETORNOS.CANCELAR')"
        icon="i-lucide-x"
        ruby
        ghost
        class="!min-h-11"
        :disabled="salvando"
        @click="
          agir(
            CrmKanbanAPI.cancelFollowUp.bind(CrmKanbanAPI),
            t(`${U}.CANCELADO_OK`)
          )
        "
      />
    </div>
  </article>
</template>

<script setup>
import { computed, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { useBookingInvite } from 'dashboard/components-next/Booking/useBookingInvite';
import {
  stateLabelKey,
  stateToneClass,
} from 'dashboard/components-next/Booking/bookingInvite';

// #1423 — "Mandar o link" dentro da gaveta: o link da página de agendamento
// para o cliente escolher o horário (#1190). A mesma lógica da janela do
// cabeçalho da conversa (useBookingInvite): gera ou reaproveita o link, troca a
// página, envia na conversa, copia, cancela e gera outro. Aqui: um
// cartão-frase com o que vai acontecer, a mensagem e, no rodapé, um botão azul
// (Enviar na conversa; sem conversa, Copiar o link; link vencido, Gerar outro).
const props = defineProps({
  card: { type: Object, required: true },
  nome: { type: String, required: true },
});
const emit = defineEmits(['enviou', 'semLink', 'criarPagina']);

const { t } = useI18n();
const L = 'CRM_CARD.LINK';
const B = 'CRM_KANBAN.BOOKING_INVITE';

const link = useBookingInvite({
  conversation: ref(null),
  card: toRef(props, 'card'),
  withStatus: ref(false),
});
const {
  isLoading,
  isSending,
  isCanceling,
  hasNoPage,
  invite,
  pageId,
  text,
  conversationId,
  pageOptions,
  pageTitle,
  validUntil,
  isInviteActive,
  shownState,
  textHasLink,
  showSettingsShortcut,
  canOpenSettings,
} = link;

onMounted(link.prepareInvite);
watch(link.isDisabledOnServer, desligado => desligado && emit('semLink'));

const dialogoCancelar = ref(null);
const confirmarCancelar = async () => {
  await link.cancelLink();
  dialogoCancelar.value?.close();
};
const enviar = async () => {
  if (await link.sendInConversation()) emit('enviou');
};

// O botão azul do rodapé desta tela (a gaveta desenha).
const principal = computed(() => {
  if (!invite.value || hasNoPage.value) return null;
  if (!isInviteActive.value)
    return {
      rotulo: t(`${L}.GERAR_OUTRO`),
      icone: 'i-lucide-refresh-cw',
      acao: link.newLink,
      carregando: isLoading.value,
      desabilitado: isLoading.value,
    };
  if (conversationId.value)
    return {
      rotulo: t(`${L}.ENVIAR`),
      icone: 'i-lucide-send',
      acao: enviar,
      carregando: isSending.value,
      desabilitado: !textHasLink.value || isSending.value || isLoading.value,
    };
  return {
    rotulo: t(`${L}.COPIAR`),
    icone: 'i-lucide-copy',
    acao: link.copyLink,
    desabilitado: isLoading.value,
  };
});

// Página (quando só há uma) e até quando o link vale, numa linha.
const detalhe = computed(() =>
  [
    pageOptions.value.length <= 1 &&
      t(`${L}.PAGINA`, { titulo: pageTitle.value }),
    t(`${L}.VALE_ATE`, { data: validUntil.value }),
  ]
    .filter(Boolean)
    .join(' · ')
);

defineExpose({
  principal,
  ocupado: computed(() => isSending.value || isCanceling.value),
});
</script>

<template>
  <section class="flex flex-col gap-4" data-tela="link-agenda">
    <p
      v-if="isLoading && !invite"
      role="status"
      class="mb-0 flex items-center gap-2 p-4 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" aria-hidden="true" />
      {{ t(`${B}.LOADING`) }}
    </p>

    <article
      v-else-if="hasNoPage"
      data-link-sem-pagina
      class="flex flex-col gap-3 rounded-2xl border border-dashed border-n-amber-7 bg-n-amber-2 p-5"
    >
      <span class="flex items-start gap-3">
        <span
          class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-amber-3 text-n-amber-11"
          aria-hidden="true"
        >
          <span class="i-lucide-calendar-x size-5" />
        </span>
        <span class="flex min-w-0 flex-col gap-1">
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">
            {{ t('CRM_CARD.AGENDA.FALTA_TITULO') }}
          </span>
          <span class="text-sm text-n-slate-12">
            {{
              t(
                canOpenSettings
                  ? 'CRM_CARD.AGENDA.FALTA_TEXTO'
                  : 'CRM_CARD.AGENDA.FALTA_TEXTO_SEM_ACESSO'
              )
            }}
          </span>
        </span>
      </span>
      <Button
        v-if="showSettingsShortcut"
        data-link-criar-pagina
        :label="t('CRM_CARD.AGENDA.CRIAR_PAGINA')"
        icon="i-lucide-calendar-plus"
        slate
        faded
        class="!min-h-11 w-fit sm:ms-12"
        @click="emit('criarPagina')"
      />
    </article>

    <template v-else-if="invite">
      <article
        data-link-frase
        class="flex items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
      >
        <span
          class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-iris-3 text-n-iris-11"
          aria-hidden="true"
        >
          <span class="i-lucide-link size-6" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-1">
          <span class="text-lg font-semibold text-n-slate-12">
            {{
              isInviteActive
                ? t(`${L}.FRASE`, { nome })
                : t(`${L}.FRASE_VENCIDO`)
            }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ detalhe }}
          </span>
          <span
            role="status"
            data-link-estado
            class="w-fit rounded-full px-2 py-0.5 text-xs font-medium"
            :class="stateToneClass(shownState)"
          >
            {{ t(stateLabelKey(shownState)) }}
          </span>
        </span>
      </article>

      <div v-if="pageOptions.length > 1" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12" aria-hidden="true">
          {{ t(`${L}.QUAL_PAGINA`) }}
        </span>
        <ChoiceSelect
          v-model="pageId"
          data-link-pagina
          :options="pageOptions"
          :aria-label="t(`${L}.QUAL_PAGINA`)"
          :disabled="isLoading"
          @change="link.changePage"
        />
      </div>

      <template v-if="isInviteActive">
        <TextArea
          v-model="text"
          data-link-mensagem
          :label="t(`${L}.MENSAGEM`)"
          :max-length="2000"
          :message="textHasLink ? '' : t(`${B}.TEXT_NEEDS_LINK`)"
          :message-type="textHasLink ? 'info' : 'error'"
          auto-height
          min-height="6rem"
        />
        <p
          v-if="!conversationId"
          class="mb-0 rounded-xl bg-n-alpha-2 p-3 text-sm text-n-slate-11"
        >
          {{ t(`${L}.SEM_CONVERSA`) }}
        </p>
        <span class="flex flex-wrap gap-2">
          <Button
            v-if="conversationId"
            data-link-copiar
            :label="t(`${L}.COPIAR`)"
            icon="i-lucide-copy"
            slate
            faded
            class="!min-h-11"
            @click="link.copyLink"
          />
          <Button
            data-link-cancelar
            :label="t(`${L}.CANCELAR`)"
            icon="i-lucide-circle-x"
            ruby
            ghost
            class="!min-h-11"
            :is-loading="isCanceling"
            @click="dialogoCancelar?.open()"
          />
        </span>
      </template>
    </template>

    <Dialog
      ref="dialogoCancelar"
      type="alert"
      :title="t(`${B}.CANCEL_CONFIRM.TITLE`)"
      :description="t(`${B}.CANCEL_CONFIRM.DESCRIPTION`)"
      :cancel-button-label="t(`${B}.CANCEL_CONFIRM.BACK`)"
      :confirm-button-label="t(`${B}.CANCEL_CONFIRM.YES`)"
      :is-loading="isCanceling"
      width="sm"
      @confirm="confirmarCancelar"
    />
  </section>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import OrigemCaminho from '../origem/OrigemCaminho.vue';
import OrigemFormulario from '../origem/OrigemFormulario.vue';
import OrigemAviso from '../origem/OrigemAviso.vue';

// #1423 — de onde o cliente veio (antigos "Vínculos do card"): o caminho até
// aqui (VC-03/VC-04), o que ele preencheu na página (VC-05), o aviso ao
// Facebook e Instagram (MT-01) e a que o card está ligado (VC-06). Tudo em
// palavras simples (OB-05).
const props = defineProps({
  card: { type: Object, required: true },
  conversao: { type: Object, default: null },
});
defineEmits(['conversa']);

const { t } = useI18n();
const O = 'CRM_CARD.ORIGEM';
const temCaminho = computed(() => Boolean(props.card.campaigns?.length));
const conversa = computed(() => props.card.conversation?.display_id || '');
const ligado = computed(() =>
  [
    props.card.contact && {
      rotulo: t(`${O}.PESSOA`),
      valor: props.card.contact.name || props.card.contact.phone_number,
    },
    props.card.inbox && {
      rotulo: t(`${O}.CAIXA`),
      valor: props.card.inbox.name,
    },
    conversa.value && {
      rotulo: t(`${O}.CONVERSA`),
      valor: t('CRM_KANBAN.DRAWER.CONVERSATION_NUMBER', { id: conversa.value }),
    },
  ].filter(Boolean)
);
</script>

<template>
  <section class="flex flex-col gap-5" data-tela="origem">
    <section
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${O}.CAMINHO`) }}
      </h3>
      <OrigemCaminho v-if="temCaminho" :campanhas="card.campaigns" />
      <p v-else class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ t(`${O}.SEM_ORIGEM`) }}
      </p>
    </section>

    <section
      v-if="card.lead_form?.fields?.length"
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${O}.PREENCHEU`) }}
      </h3>
      <OrigemFormulario :formulario="card.lead_form" />
    </section>

    <OrigemAviso :conversao="conversao" />

    <section
      v-if="ligado.length"
      class="flex flex-col gap-1 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <h3 class="mb-1 text-base font-semibold text-n-slate-12">
        {{ t(`${O}.LIGADO`) }}
      </h3>
      <dl class="m-0 flex flex-col divide-y divide-n-weak">
        <div
          v-for="item in ligado"
          :key="item.rotulo"
          class="flex flex-wrap justify-between gap-x-4 py-2.5"
        >
          <dt class="text-sm text-n-slate-11">{{ item.rotulo }}</dt>
          <dd class="m-0 min-w-0 break-words text-[0.9375rem] text-n-slate-12">
            {{ item.valor }}
          </dd>
        </div>
      </dl>
      <Button
        v-if="conversa"
        :label="t('CRM_CARD.ABRIR_CONVERSA')"
        icon="i-lucide-message-circle"
        slate
        faded
        class="!min-h-11 mt-2 w-fit"
        @click="$emit('conversa')"
      />
    </section>
  </section>
</template>

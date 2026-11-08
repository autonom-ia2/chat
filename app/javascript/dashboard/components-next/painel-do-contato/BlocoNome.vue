<script setup>
// #2138 — bloco 1: o nome é o título. Foto, nome como foi escrito, telefone com
// "Copiar", e-mail e empresa só quando há, etiquetas do contato e a recusa de
// mensagens automáticas. "Editar dados" só para quem cuida dos contatos.
// Enquanto o contato carrega, vale o que veio com a conversa (nome e telefone);
// as etiquetas e o resto esperam o contato. Se ele não vier, o erro fica aqui.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';
import EsqueletoOuErro from './EsqueletoOuErro.vue';
import { ESTADO } from './useParteDoPainel';

const props = defineProps({
  contact: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
  estado: { type: String, default: ESTADO.PRONTO },
});
const emit = defineEmits(['editar', 'tentar']);

const { t } = useI18n();
const store = useStore();
const etiquetasDoContato = useMapGetter('contactLabels/getContactLabels');

const telefone = computed(() => props.contact.phone_number || '');
const nome = computed(() => props.contact.name || telefone.value);
const mostraTelefoneEmbaixo = computed(
  () => telefone.value && nome.value !== telefone.value
);
const empresa = computed(
  () => props.contact.additional_attributes?.company_name || ''
);
const temEtiqueta = computed(
  () => (etiquetasDoContato.value(props.contact.id) || []).length > 0
);
const carregado = computed(() => props.estado === ESTADO.PRONTO);
const mostraEtiquetas = computed(
  () => carregado.value && (temEtiqueta.value || props.podeEditar)
);

watch(
  () => [props.contact.id, carregado.value],
  ([id]) => {
    if (id && carregado.value) store.dispatch('contactLabels/get', id);
  },
  { immediate: true }
);

const copiar = async () => {
  await copyTextToClipboard(telefone.value);
  useAlert(t('PAINEL_DO_CONTATO.NOME.NUMERO_COPIADO'));
};
</script>

<template>
  <section class="flex flex-col gap-3 px-4 pt-4 pb-4">
    <div class="flex items-center gap-3">
      <Avatar :src="contact.thumbnail" :name="nome" :size="48" rounded-full />
      <h2
        class="flex-1 min-w-0 m-0 text-lg font-semibold leading-6 break-words text-n-slate-12"
      >
        {{ nome }}
      </h2>
    </div>
    <div class="flex flex-col">
      <div v-if="telefone" class="flex items-center justify-between gap-2">
        <span
          v-if="mostraTelefoneEmbaixo"
          class="text-sm tabular-nums text-n-slate-12"
        >
          {{ telefone }}
        </span>
        <span v-else class="sr-only">{{ telefone }}</span>
        <Button
          :label="t('PAINEL_DO_CONTATO.NOME.COPIAR')"
          icon="i-lucide-copy"
          variant="ghost"
          color="slate"
          size="sm"
          class="min-h-11 -mr-2"
          @click="copiar"
        />
      </div>
      <span
        v-if="contact.email"
        class="text-sm break-all text-n-slate-12 min-h-6"
      >
        {{ contact.email }}
      </span>
      <span v-if="empresa" class="text-sm text-n-slate-12 min-h-6">
        {{ empresa }}
      </span>
    </div>
    <EsqueletoOuErro
      v-if="estado !== ESTADO.PRONTO"
      :estado="estado"
      :linhas="1"
      @tentar="emit('tentar')"
    />
    <!-- A lista de etiquetas abre presa a este grupo (relative), embaixo dele e
         alinhada ao texto: não sai do painel de 320 px quando o botão fica no fim
         da linha. -->
    <div
      v-if="mostraEtiquetas"
      :aria-label="t('PAINEL_DO_CONTATO.NOME.ETIQUETAS')"
      role="group"
      class="relative"
    >
      <ContactLabels
        :contact-id="contact.id"
        :read-only="!podeEditar"
        anchor-menu-to-parent
      />
    </div>
    <p
      v-if="carregado && contact.opted_out_at"
      class="flex gap-2 px-3 py-2 m-0 text-sm rounded-lg bg-n-amber-2 text-n-slate-12"
    >
      <span
        class="i-lucide-bell-off flex-shrink-0 mt-0.5 size-4 text-n-amber-11"
      />
      <span>{{ t('PAINEL_DO_CONTATO.NOME.RECUSA') }}</span>
    </p>
    <div v-if="podeEditar && carregado">
      <Button
        :label="t('PAINEL_DO_CONTATO.NOME.EDITAR')"
        variant="link"
        color="blue"
        size="sm"
        class="min-h-11"
        @click="emit('editar')"
      />
    </div>
  </section>
</template>

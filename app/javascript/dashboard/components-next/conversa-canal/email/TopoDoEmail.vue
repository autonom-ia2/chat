<script setup>
// Topo da conversa de e-mail (#1786): o assunto uma vez, grande, como no leitor de
// e-mail, e logo abaixo o resumo da conversa: a caixa, quantos e-mails, quem está nela
// (fotos) e quantos anexos. À direita, recolher as mensagens antigas (por padrão
// abertas; a escolha fica guardada para cada atendente).
// O assunto do FUNIL (CRM) é outra coisa e continua no seletor da caixa de resposta.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { MESSAGE_TYPES } from '../../message/constants.js';
import { useEmailDaConversa } from './useConversaDeEmail';
import { remetenteDoEmail } from './dadosDoEmail';
import AcoesDaPasta from './AcoesDaPasta.vue';

const props = defineProps({
  // As mensagens da lista, já em camelCase.
  mensagens: { type: Array, default: () => [] },
});

const { t } = useI18n();
const email = useEmailDaConversa();
const caixaPorId = useMapGetter('inboxes/getInbox');
const FOTOS_A_MOSTRAR = 4;

const emails = computed(() =>
  props.mensagens.filter(
    m =>
      !m.private &&
      [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(m.messageType)
  )
);
const pessoas = computed(() => {
  const vistas = new Map();
  emails.value.forEach(m => {
    const quem = remetenteDoEmail({
      contentAttributes: m.contentAttributes,
      sender: m.sender,
      recebido: m.messageType === MESSAGE_TYPES.INCOMING,
    });
    const chave = (quem.endereco || quem.nome || '').toLowerCase();
    if (chave && !vistas.has(chave)) vistas.set(chave, quem);
  });
  return [...vistas.values()];
});
const anexos = computed(() =>
  emails.value.reduce((soma, m) => soma + (m.attachments?.length || 0), 0)
);
const caixa = computed(
  () => caixaPorId.value(emails.value[0]?.inboxId)?.name || ''
);

const DADO = 'inline-flex items-center gap-1.5 text-xs text-n-slate-11';
</script>

<template>
  <li
    class="list-none w-full max-w-[960px] mx-auto flex flex-wrap items-start justify-between gap-x-4 gap-y-3 pt-5 pb-4 px-2 sm:px-4 border-b border-n-weak"
    data-topo-do-email
  >
    <div class="basis-full sm:basis-0 flex-1 min-w-0">
      <h2
        class="text-[22px] leading-7 font-medium tracking-[-0.01em] text-n-slate-12 break-words [text-wrap:balance]"
      >
        {{ email.assunto.value || t('CONVERSA_CANAL.EMAIL.SEM_ASSUNTO') }}
      </h2>
      <div
        class="flex flex-wrap items-center gap-x-3 gap-y-1.5 mt-2"
        data-resumo-da-conversa
      >
        <span
          v-if="caixa"
          class="inline-flex items-center gap-1 h-6 px-2 rounded-md bg-n-alpha-2 text-xs font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-inbox" class="size-3.5 text-n-slate-11" />
          {{ caixa }}
        </span>
        <span :class="DADO" class="tabular-nums">
          <Icon icon="i-lucide-mails" class="size-3.5" />
          {{
            t(
              'CONVERSA_CANAL.EMAIL.TOTAL_DE_EMAILS',
              { total: emails.length },
              emails.length
            )
          }}
        </span>
        <span v-if="pessoas.length > 1" :class="DADO">
          <span class="flex -space-x-1.5" aria-hidden="true">
            <Avatar
              v-for="pessoa in pessoas.slice(0, FOTOS_A_MOSTRAR)"
              :key="pessoa.endereco || pessoa.nome"
              :name="pessoa.nome"
              :src="pessoa.foto"
              :size="24"
              rounded-full
              class="ring-2 ring-n-surface-1"
            />
          </span>
          <span :title="pessoas.map(p => p.nome).join(', ')">
            {{
              t(
                'CONVERSA_CANAL.EMAIL.TOTAL_DE_PESSOAS',
                { total: pessoas.length },
                pessoas.length
              )
            }}
          </span>
        </span>
        <span v-if="anexos" :class="DADO" class="tabular-nums">
          <Icon icon="i-lucide-paperclip" class="size-3.5" />
          {{ t('CONVERSA_CANAL.EMAIL.ANEXOS', { total: anexos }, anexos) }}
        </span>
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-1">
      <AcoesDaPasta />
      <button
        v-if="emails.length > 1"
        type="button"
        class="inline-flex items-center gap-1.5 min-h-10 px-3 rounded-full text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-pressed="email.recolher.value"
        data-recolher-antigas
        @click="email.alternarRecolher"
      >
        <Icon
          :icon="
            email.recolher.value
              ? 'i-lucide-unfold-vertical'
              : 'i-lucide-fold-vertical'
          "
          class="size-4"
        />
        {{
          email.recolher.value
            ? t('CONVERSA_CANAL.EMAIL.ABRIR_TODAS')
            : t('CONVERSA_CANAL.EMAIL.RECOLHER_ANTIGAS')
        }}
      </button>
    </div>
  </li>
</template>

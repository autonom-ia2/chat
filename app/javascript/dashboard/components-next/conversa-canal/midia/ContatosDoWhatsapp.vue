<script setup>
// Vários contatos num balão só (#1702), como no WhatsApp: as fotos empilhadas,
// "Fulano e mais N contatos" e, embaixo de uma linha fina, "Ver todos", que abre a
// lista ali mesmo (nome e telefone de cada um). Quem escolhe é Message.vue, com a
// pele, quando todos os anexos da mensagem são contatos ou quando shared_contacts
// traz mais de um (#1709: aí cada contato aparece uma vez, com todos os telefones).
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import { contatosDoBalao } from './contatos';

const { attachments, contentAttributes } = useMessageContext();
const { t } = useI18n();

const contatos = computed(() =>
  contatosDoBalao(attachments.value, contentAttributes?.value)
);
const primeiro = computed(() => contatos.value[0] || {});
const outros = computed(() => contatos.value.length - 1);
const nomeDe = contato =>
  contato.nome || contato.telefone || t('CONVERSA_CANAL.CONTATOS.SEM_NOME');

const resumo = computed(() =>
  t(
    'CONVERSA_CANAL.CONTATOS.RESUMO',
    { nome: nomeDe(primeiro.value), n: outros.value },
    outros.value
  )
);

// Até 3 fotos empilhadas, como no app.
const PILHA = 3;
const pilha = computed(() => contatos.value.slice(0, PILHA));

const aberto = ref(false);
const idLista = `contatos-${useId()}`;
</script>

<template>
  <BaseBubble class="!p-[3px]" data-bubble-name="contatos">
    <div class="w-[280px] max-w-full" data-contatos-do-whatsapp>
      <div class="flex items-center gap-3 px-2 pt-2 pb-3">
        <span class="flex shrink-0" aria-hidden="true">
          <span
            v-for="(contato, posicao) in pilha"
            :key="contato.chave"
            class="grid place-content-center size-9 rounded-full border-2 border-white dark:border-[#242626] bg-[#DFE5E7] dark:bg-[#6A7175]"
            :class="posicao ? '-ms-4' : ''"
          >
            <span
              class="i-ph-user-fill size-5 text-white dark:text-[#C9CCCC]"
            />
          </span>
        </span>
        <span
          class="min-w-0 text-[15px] font-medium text-[#0A0A0A] dark:text-[#FAFAFA]"
          data-resumo-dos-contatos
        >
          {{ resumo }}
        </span>
      </div>
      <ul
        v-if="aberto"
        :id="idLista"
        class="m-0 px-2 pb-2 flex flex-col gap-2 list-none"
        data-lista-de-contatos
      >
        <li v-for="contato in contatos" :key="contato.chave" class="min-w-0">
          <span
            class="block text-[14px] truncate text-[#0A0A0A] dark:text-[#FAFAFA]"
          >
            {{ nomeDe(contato) }}
          </span>
          <template v-if="contato.nome">
            <span
              v-for="telefone in contato.telefones"
              :key="telefone"
              class="block text-[13px] truncate text-[#666666] dark:text-[#A7A8A8]"
            >
              {{ telefone }}
            </span>
          </template>
        </li>
      </ul>
      <button
        type="button"
        class="w-full h-11 mt-3 -mb-1 border-t border-[#000]/10 dark:border-white/10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]"
        :aria-expanded="aberto"
        :aria-controls="idLista"
        data-ver-todos-os-contatos
        @click="aberto = !aberto"
      >
        {{
          aberto
            ? t('CONVERSA_CANAL.CONTATOS.OCULTAR')
            : t('CONVERSA_CANAL.CONTATOS.VER_TODOS')
        }}
      </button>
    </div>
  </BaseBubble>
</template>

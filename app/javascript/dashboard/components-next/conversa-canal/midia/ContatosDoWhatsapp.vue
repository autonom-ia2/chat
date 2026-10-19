<script setup>
// Vários contatos num balão só (#1702), como no WhatsApp: as fotos empilhadas,
// "Fulano e N outros contatos" e, embaixo de uma linha fina, "Ver todos", que abre a
// janela com a lista (nome, telefones e as ações do cartão de contato: "Conversar" e
// "Salvar contato"). Quem escolhe é Message.vue, com a pele: todos os anexos da
// mensagem são contatos, shared_contacts traz mais de um (#1709: cada contato aparece
// uma vez, com todos os telefones) ou a Cloud criou uma mensagem por contato com o
// mesmo source_id (useContatosDaMensagem: a 1ª desenha o cartão, as outras somem).
// A janela é a mesma das opções em lista (OpcoesDoWhatsapp): presa à esquerda da
// conversa, por cima dela.
import { computed, nextTick, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import NovaConversaEntrada from '../../NovaConversa/NovaConversaEntrada.vue';
import { useContatosDaMensagem } from '../album/useAlbuns';
import { contatosDoCartao } from './contatos';
import { soDigitos, useAcoesDoContato } from './useAcoesDoContato';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';

const { id, attachments, contentAttributes } = useMessageContext();
const { t } = useI18n();
const { salvar, paraConversar } = useAcoesDoContato();
// Salvar e Conversar procuram o número na base de contatos: pedem ver contatos (#1849).
const { canViewRelationshipRecords } = useRelationshipPermissions();

const doMesmoEnvio = useContatosDaMensagem(id);
const contatos = computed(() =>
  contatosDoCartao(
    doMesmoEnvio.value || [
      {
        attachments: attachments.value || [],
        contentAttributes: contentAttributes?.value || {},
      },
    ]
  )
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

// A janela abre por cima da conversa, presa à esquerda do painel; fora do painel
// (sem onde prender), abre ali mesmo, embaixo do balão.
const raiz = useTemplateRef('raiz');
const fechar = useTemplateRef('fechar');
const abrir = useTemplateRef('abrir');
const alvo = ref(null);
const aberta = ref(false);
const idJanela = `contatos-${useId()}`;

const abrirJanela = async () => {
  alvo.value =
    raiz.value?.closest('.conversation-panel')?.parentElement || null;
  aberta.value = true;
  await nextTick();
  fechar.value?.focus();
};
// Ao fechar, o foco volta para "Ver todos", de onde a pessoa saiu.
const fecharJanela = async () => {
  aberta.value = false;
  await nextTick();
  abrir.value?.focus();
};

// A janela é modal: o Tab roda entre os controles dela e não sai para a conversa.
const janela = useTemplateRef('janela');
const prenderFoco = evento => {
  const controles = [...(janela.value?.querySelectorAll('button') || [])];
  if (!controles.length) return;
  const [primeiroControle] = controles;
  const ultimoControle = controles.at(-1);
  const ativo = document.activeElement;
  if (evento.shiftKey && ativo === primeiroControle) {
    evento.preventDefault();
    ultimoControle.focus();
  } else if (!evento.shiftKey && ativo === ultimoControle) {
    evento.preventDefault();
    primeiroControle.focus();
  }
};

// "Conversar": a Nova conversa daquele contato recebe o id quando ele é achado ou criado.
const conversarCom = ref({ posicao: null, id: null });
const conversar = async (contato, posicao) => {
  const idDoContato = await paraConversar(contato.paraConversar, contato.nome);
  if (idDoContato) conversarCom.value = { posicao, id: idDoContato };
};
const salvarContato = contato =>
  salvar(soDigitos(contato.telefone), contato.nome);

const ACAO =
  'w-full h-10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]';
</script>

<template>
  <BaseBubble class="!p-[3px]" data-bubble-name="contatos">
    <div ref="raiz" class="w-[280px] max-w-full" data-contatos-do-whatsapp>
      <div class="flex items-center gap-3 px-2 pt-2 pb-3">
        <span class="flex shrink-0" aria-hidden="true">
          <span
            v-for="(contato, posicao) in pilha"
            :key="posicao"
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
      <button
        ref="abrir"
        type="button"
        class="w-full h-11 mt-3 -mb-1 border-t border-[#000]/10 dark:border-white/10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]"
        aria-haspopup="dialog"
        :aria-expanded="aberta"
        :aria-controls="aberta ? idJanela : undefined"
        data-ver-todos-os-contatos
        @click="abrirJanela"
      >
        {{ t('CONVERSA_CANAL.CONTATOS.VER_TODOS') }}
      </button>

      <Teleport v-if="aberta" :to="alvo || 'body'" :disabled="!alvo">
        <div
          v-if="alvo"
          class="absolute inset-0 z-40 bg-[#000]/35"
          data-fundo-dos-contatos
          @click="fecharJanela"
        />
        <div
          :id="idJanela"
          ref="janela"
          role="dialog"
          aria-modal="true"
          :aria-label="resumo"
          class="flex flex-col overflow-hidden bg-white dark:bg-[#242626]"
          :class="
            alvo
              ? 'absolute z-50 top-3 bottom-3 ltr:left-3 rtl:right-3 w-[417px] max-w-[calc(100%-24px)] rounded-[24px] shadow-[0_4px_24px_rgba(0,0,0,0.2)]'
              : 'mt-2 rounded-lg'
          "
          data-janela-dos-contatos
          @keydown.esc="fecharJanela"
          @keydown.tab="prenderFoco"
        >
          <div class="flex items-center gap-6 h-16 px-6 flex-shrink-0">
            <button
              ref="fechar"
              type="button"
              class="grid place-content-center size-10 -ms-2 rounded-full text-[#0A0A0A] dark:text-[#FAFAFA] hover:bg-[#000]/5 dark:hover:bg-white/5"
              :aria-label="t('CONVERSA_CANAL.MIDIA.FECHAR')"
              data-fechar-contatos
              @click="fecharJanela"
            >
              <Icon icon="i-ph-x" class="size-6" />
            </button>
            <span class="text-[16px] text-[#0A0A0A] dark:text-[#FAFAFA]">
              {{ t('CONVERSA_CANAL.CONTATOS.TITULO', contatos.length) }}
            </span>
          </div>
          <ul
            class="flex-1 overflow-y-auto m-0 px-3 pb-4 flex flex-col gap-2 list-none"
            data-lista-de-contatos
          >
            <li
              v-for="(contato, posicao) in contatos"
              :key="posicao"
              class="min-w-0 rounded-[10px] border border-[#000]/10 dark:border-white/10"
            >
              <div class="flex items-center gap-3 px-3 py-3">
                <div
                  class="grid place-content-center size-10 shrink-0 rounded-full bg-[#DFE5E7] dark:bg-[#6A7175]"
                  aria-hidden="true"
                >
                  <i
                    class="i-ph-user-fill size-6 text-white dark:text-[#C9CCCC]"
                  />
                </div>
                <div class="min-w-0">
                  <span
                    class="block text-[15px] font-medium truncate text-[#0A0A0A] dark:text-[#FAFAFA]"
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
                </div>
              </div>
              <div
                v-if="contato.comAcoes && canViewRelationshipRecords"
                class="flex border-t border-[#000]/10 dark:border-white/10 divide-x divide-[#000]/10 dark:divide-white/10 [&>*]:flex-1"
                data-acoes-do-contato
              >
                <NovaConversaEntrada
                  :contact-id="
                    conversarCom.posicao === posicao ? conversarCom.id : null
                  "
                >
                  <template #trigger>
                    <button
                      type="button"
                      :class="ACAO"
                      data-conversar-com-contato
                      @click="conversar(contato, posicao)"
                    >
                      {{ t('CONVERSA_CANAL.CONTATO.CONVERSAR') }}
                    </button>
                  </template>
                </NovaConversaEntrada>
                <button
                  type="button"
                  :class="ACAO"
                  data-salvar-contato
                  @click="salvarContato(contato)"
                >
                  {{ t('CONVERSATION.SAVE_CONTACT') }}
                </button>
              </div>
            </li>
          </ul>
        </div>
      </Teleport>
    </div>
  </BaseBubble>
</template>

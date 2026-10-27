<script setup>
// #2138 — o painel do contato na conversa (Proposta 1, versão 4), atrás da chave
// `painel_contato_enxuto` da conta (o ContactPanel escolhe entre este e o antigo).
// Responde três perguntas: quem é a pessoa, quem cuida da conversa e o que foi
// combinado. Cada bloco só aparece quando tem conteúdo. As linhas que abrem
// ocupam o lugar do painel, com "Voltar" no alto.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { useFase2 } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useFase2';
import wootConstants from 'dashboard/constants/globals';
import Button from 'dashboard/components-next/button/Button.vue';
import ContatoBasico from 'dashboard/routes/dashboard/conversation/contact/ContatoBasico.vue';
import EditContact from 'dashboard/routes/dashboard/conversation/contact/EditContact.vue';
import BlocoNome from './BlocoNome.vue';
import BlocoQuemCuida from './BlocoQuemCuida.vue';
import BlocoCombinado from './BlocoCombinado.vue';
import BlocoAssunto from './BlocoAssunto.vue';
import BlocoOrigem from './BlocoOrigem.vue';
import BlocoRelacao from './BlocoRelacao.vue';
import BlocoEtiquetas from './etiquetas/BlocoEtiquetas.vue';
import { useRelacaoLigada } from 'dashboard/components-next/contato-relacao/useRelacaoLigada';
import BlocoDoPainel from './BlocoDoPainel.vue';
import LinhaQueAbre from './LinhaQueAbre.vue';
import TelaDaLista from './TelaDaLista.vue';
import EsqueletoOuErro from './EsqueletoOuErro.vue';
import { ESTADO } from './useParteDoPainel';
import { useListasDoContato } from './useListasDoContato';

const props = defineProps({
  conversation: { type: Object, required: true },
  contact: { type: Object, required: true },
  podeVerContatos: { type: Boolean, default: false },
  podeOperar: { type: Boolean, default: false },
  conversationAttributes: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['fechar']);

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { width } = useWindowSize();
const contaId = useMapGetter('getCurrentAccountId');
const { canManageRelationshipRecords } = useRelationshipPermissions();
const { canViewCrm } = useCrmPermissions();
const fase2 = useFase2();
const relacaoLigada = useRelacaoLigada();

const noCelular = computed(
  () => width.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);
const crmLigado = computed(
  () =>
    (store.getters['globalConfig/get']?.crmKanbanEnabled === true ||
      window.globalConfig?.CRM_KANBAN_ENABLED === 'true') &&
    canViewCrm.value
);

const editando = ref(false);
// Quando o bloco das etiquetas some com o foco dentro (tirou a última), o foco
// vai para o título do bloco de cima ("Quem cuida"), não para o <body>.
const quemCuida = ref(null);
const focarAoSumir = () => quemCuida.value?.focarTitulo();
const aberta = ref(null);
watch(
  () => props.conversation.id,
  () => {
    aberta.value = null;
  }
);

// O contato vem do ContactPanel (contacts/show). Enquanto não chega, o nome e o
// telefone vêm da conversa; se a leitura terminar sem ele, o bloco do nome
// mostra o erro e "Tentar de novo".
const uiDosContatos = useMapGetter('contacts/getUIFlags');
const contatoCarregado = computed(() => Boolean(props.contact?.id));
const contatoTentado = ref(false);
watch(
  () => uiDosContatos.value?.isFetchingItem,
  (agora, antes) => {
    if (antes && !agora) contatoTentado.value = true;
  }
);
watch(
  () => props.conversation.meta?.sender?.id,
  () => {
    contatoTentado.value = false;
  }
);
const estadoDoContato = computed(() => {
  if (contatoCarregado.value) return ESTADO.PRONTO;
  return contatoTentado.value ? ESTADO.ERRO : ESTADO.CARREGANDO;
});
const contato = computed(() =>
  contatoCarregado.value ? props.contact : props.conversation.meta?.sender || {}
);
const lerContatoDeNovo = () => {
  const id = props.conversation.meta?.sender?.id;
  if (id) store.dispatch('contacts/show', { id });
};

const listas = useListasDoContato({
  contact: computed(() =>
    props.podeVerContatos && contatoCarregado.value ? props.contact : null
  ),
  conversationId: computed(() => props.conversation.id),
});

const linhas = computed(() =>
  [
    {
      tipo: 'conversas',
      count: listas.conversas.value.length,
      texto: n => t('PAINEL_DO_CONTATO.LISTAS.CONVERSAS', { count: n }),
      so: props.podeVerContatos,
    },
    {
      tipo: 'arquivos',
      count: listas.arquivos.value.length,
      texto: n => t('PAINEL_DO_CONTATO.LISTAS.ARQUIVOS', { count: n }),
      so: true,
    },
    {
      tipo: 'informacoes',
      count: listas.informacoes.value.length,
      texto: n => t('PAINEL_DO_CONTATO.LISTAS.INFORMACOES', { count: n }),
      so: props.podeVerContatos,
    },
    {
      tipo: 'acompanham',
      count: listas.quemAcompanha.value.length,
      texto: n => t('PAINEL_DO_CONTATO.LISTAS.ACOMPANHAM', { count: n }),
      so: true,
    },
  ].filter(linha => linha.so && linha.count > 0)
);

const verPagina = () =>
  router.push({
    name: 'contacts_edit',
    params: { accountId: contaId.value, contactId: props.contact.id },
  });
</script>

<template>
  <div class="flex flex-col w-full min-h-full" data-painel-do-contato>
    <TelaDaLista
      v-if="aberta"
      :tipo="aberta"
      :listas="{
        conversas: listas.conversas.value,
        arquivos: listas.arquivos.value,
        informacoes: listas.informacoes.value,
        quemAcompanha: listas.quemAcompanha.value,
      }"
      :contact="contact"
      :pode-editar="canManageRelationshipRecords"
      @voltar="aberta = null"
    />
    <template v-else>
      <header
        class="sticky top-0 z-10 flex items-center justify-between gap-2 px-4 border-b bg-n-surface-2 border-n-weak min-h-12"
      >
        <Button
          v-if="noCelular"
          :label="t('PAINEL_DO_CONTATO.VOLTAR_PARA_CONVERSA')"
          icon="i-lucide-arrow-left"
          variant="ghost"
          color="slate"
          size="sm"
          class="-ml-2 min-h-11"
          @click="emit('fechar')"
        />
        <template v-else>
          <h2 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('PAINEL_DO_CONTATO.TITULO') }}
          </h2>
          <Button
            v-tooltip="t('PAINEL_DO_CONTATO.FECHAR')"
            :aria-label="t('PAINEL_DO_CONTATO.FECHAR')"
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            class="min-h-11 min-w-11"
            @click="emit('fechar')"
          />
        </template>
      </header>
      <p
        v-if="!podeOperar"
        class="flex items-center gap-2 px-4 py-2 m-0 text-sm border-b bg-n-alpha-1 text-n-slate-12 border-n-weak"
        data-test-id="faixa-so-leitura"
      >
        <span class="flex-shrink-0 i-lucide-eye size-4 text-n-slate-11" />
        {{ t('PAINEL_DO_CONTATO.SO_LEITURA') }}
      </p>

      <BlocoNome
        v-if="podeVerContatos"
        :contact="contato"
        :estado="estadoDoContato"
        :pode-editar="canManageRelationshipRecords"
        @editar="editando = true"
        @tentar="lerContatoDeNovo"
      />
      <ContatoBasico
        v-else
        :contact="contact"
        :conversation-id="conversation.id"
      />
      <div class="flex flex-col border-t border-n-weak">
        <BlocoQuemCuida
          ref="quemCuida"
          :conversation="conversation"
          :pode-operar="podeOperar"
          :fase2="fase2"
        />
        <!-- #2202 (PR 3): as etiquetas da conversa, só quando ela tem alguma. -->
        <BlocoEtiquetas
          :pode-operar="podeOperar"
          :focar-ao-sumir="focarAoSumir"
        />
        <BlocoCombinado v-if="crmLigado" :contact-id="contact.id" />
        <BlocoRelacao
          v-if="
            relacaoLigada && crmLigado && podeVerContatos && contatoCarregado
          "
          :contact-id="contact.id"
          :pode-editar="canManageRelationshipRecords && podeOperar"
        />
        <BlocoAssunto
          v-if="crmLigado && !podeOperar"
          :conversation="conversation"
        />
        <BlocoOrigem
          :contact-id="contact.id"
          :conversation-attributes="conversationAttributes"
        />
        <BlocoDoPainel
          v-if="listas.carregando.value && !linhas.length"
          data-test-id="bloco-mais-carregando"
        >
          <EsqueletoOuErro :estado="ESTADO.CARREGANDO" />
        </BlocoDoPainel>
        <BlocoDoPainel
          v-else-if="linhas.length || listas.comErro.value"
          data-test-id="bloco-mais"
        >
          <div class="flex flex-col">
            <LinhaQueAbre
              v-for="linha in linhas"
              :key="linha.tipo"
              :texto="linha.texto(linha.count)"
              @abrir="aberta = linha.tipo"
            />
          </div>
          <EsqueletoOuErro
            v-if="listas.comErro.value"
            :estado="ESTADO.ERRO"
            @tentar="listas.tentarDeNovo"
          />
        </BlocoDoPainel>
        <BlocoDoPainel
          v-if="podeVerContatos && contatoCarregado"
          data-test-id="ver-pagina"
        >
          <div class="flex flex-col gap-1">
            <LinhaQueAbre
              :texto="t('PAINEL_DO_CONTATO.PE.VER_PAGINA')"
              @abrir="verPagina"
            />
            <p class="m-0 text-sm text-n-slate-11">
              {{ t('PAINEL_DO_CONTATO.PE.FRASE') }}
            </p>
          </div>
        </BlocoDoPainel>
      </div>
    </template>
    <EditContact
      v-if="canManageRelationshipRecords && podeVerContatos && contatoCarregado"
      :show="editando"
      :contact="contact"
      @cancel="editando = false"
    />
  </div>
</template>

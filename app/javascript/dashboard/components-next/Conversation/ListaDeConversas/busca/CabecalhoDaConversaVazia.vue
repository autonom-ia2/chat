<script setup>
// #2211 (rodada 5) — o topo da conversa vazia com a mesma estrutura e o mesmo estilo do topo da
// conversa de verdade (ConversationHeader): avatar, nome e, embaixo, a caixa (ícone e nome);
// com a cara do WhatsApp, a faixa do app (TOPO_DA_CONVERSA). Antes de existir conversa não há
// número da conversa, CRM, Resolver nem os outros botões; no lugar deles, "Trocar" a caixa.
// O ConversationHeader lê a conversa aberta da store; aqui ainda não existe conversa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'next/avatar/Avatar.vue';
import { TOPO_DA_CONVERSA } from 'dashboard/components-next/conversa-canal/visualWhatsapp';
import { linhaDaCaixa } from './caixasDaConversaVazia';
import { iconeDaCaixa } from '../iconeDaCaixa';
import { nomeNoAvatar } from './buscaDaLista';

const props = defineProps({
  nome: { type: String, default: '' },
  foto: { type: String, default: '' },
  caixa: { type: Object, default: null },
  comTrocar: { type: Boolean, default: false },
  caraDoWhatsapp: { type: Boolean, default: false },
});
const emit = defineEmits(['voltar', 'trocar']);

const { t } = useI18n();
const icone = computed(() => iconeDaCaixa(props.caixa));
const linha = computed(() => linhaDaCaixa(props.caixa));
// O separador do "#número • caixa" do topo da conversa.
const MARCADOR = '•';
// Como no topo da conversa: a caixa só aparece quando a conta tem mais de uma.
const caixasDaConta = useMapGetter('inboxes/getInboxes');
const comCaixa = computed(
  () => Boolean(props.caixa) && caixasDaConta.value.length > 1
);
</script>

<template>
  <header
    class="flex flex-col gap-3 items-center justify-between flex-none w-full min-w-0 xl:flex-row px-3 pt-3 pb-2 min-h-24 xl:min-h-0 xl:h-12 border-b border-b-n-weak"
    :class="caraDoWhatsapp && TOPO_DA_CONVERSA"
    data-topo-da-conversa-vazia
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <!-- Como o "Anterior" da conversa no celular: volta para a lista como estava. -->
      <button
        type="button"
        data-voltar
        class="flex items-center p-0 text-base font-normal bg-transparent border-0 cursor-pointer md:hidden me-2 min-h-11 text-n-slate-11"
        @click="emit('voltar')"
      >
        <i class="i-lucide-chevron-left -ml-1 text-lg" />
        {{ t('GENERAL_SETTINGS.BACK') }}
      </button>
      <Avatar
        :name="nomeNoAvatar(nome)"
        :src="foto"
        :size="caraDoWhatsapp ? 40 : 32"
        :rounded-full="caraDoWhatsapp"
        hide-offline-status
      />
      <div class="flex flex-col items-start min-w-0 ms-2 overflow-hidden">
        <span
          class="text-sm font-medium truncate leading-tight text-n-slate-12 max-w-full"
          :class="{
            '!text-base !text-[#0A0A0A] dark:!text-[#FAFAFA]': caraDoWhatsapp,
          }"
          data-nome
        >
          {{ nome }}
        </span>
        <div
          v-if="comCaixa"
          class="flex items-center gap-0.5 min-w-0 max-w-full"
          :title="caixa.name"
          data-caixa-escolhida
        >
          <span
            class="size-4 flex-shrink-0 text-n-slate-11"
            :class="icone"
            aria-hidden="true"
          />
          <span class="truncate text-label-small text-n-slate-11">
            {{ caixa.name }}
          </span>
          <!-- Como o "#número • caixa" da conversa: aqui, a caixa e o número dela (ou o e-mail). -->
          <span
            v-if="linha"
            class="min-w-0 max-w-[65%] flex-shrink-0 truncate text-label-small text-n-slate-11"
            data-numero-da-caixa
          >
            {{ MARCADOR }} {{ linha }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto"
    >
      <button
        v-if="comTrocar"
        type="button"
        data-trocar-caixa
        class="inline-flex items-center gap-1 px-3 text-sm font-medium border rounded-lg min-h-11 xl:min-h-8 border-n-weak bg-n-button-color text-n-slate-12 hover:bg-n-alpha-2"
        :aria-label="
          t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.TROCAR_ARIA', {
            caixa: caixa?.name,
          })
        "
        @click="emit('trocar')"
      >
        <span class="size-4" :class="icone" aria-hidden="true" />
        {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.TROCAR') }}
      </button>
    </div>
  </header>
</template>

<script setup>
// Sub-itens da caixa de e-mail no menu novo (#1809, fase 1), como no Gmail: Escrever,
// Entrada, Spam e Lixeira. Aparecem embaixo da caixa quando ela está aberta, só em
// caixa de e-mail e com a chave `conversa_email_nova`. Escrever é ação (abre a gaveta
// "Nova conversa" já nesta caixa), não rota: não acende como item ativo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import { useMapGetter } from 'dashboard/composables/store';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { PASTAS, usePastaDoEmail } from './pastaDoEmail';

const props = defineProps({
  folha: { type: Object, required: true },
  tema: { type: Object, required: true },
});
const emit = defineEmits(['navegou']);

const { t } = useI18n();
const route = useRoute();
const caixaPorId = useMapGetter('inboxes/getInbox');
const contaAtual = useMapGetter('getCurrentAccountId');
const temChave = useMapGetter('accounts/isFeatureEnabledonAccount');
const { pasta, abrirPasta } = usePastaDoEmail();

const caixaId = computed(() => props.folha.to?.params?.inbox_id);
const caixa = computed(() =>
  caixaId.value ? caixaPorId.value(Number(caixaId.value)) : null
);
const aberta = computed(
  () => String(route.params.inbox_id || '') === String(caixaId.value || '')
);
const visivel = computed(
  () =>
    aberta.value &&
    caixa.value?.channel_type === INBOX_TYPES.EMAIL &&
    temChave.value(contaAtual.value, 'conversa_email_nova')
);

const ITENS = [
  { pasta: null, chave: 'ENTRADA', icone: 'i-lucide-inbox' },
  { pasta: PASTAS.SPAM, chave: 'SPAM', icone: 'i-lucide-octagon-alert' },
  { pasta: PASTAS.LIXEIRA, chave: 'LIXEIRA', icone: 'i-lucide-trash-2' },
];

const ativo = item => aberta.value && (pasta.value || null) === item.pasta;
const ir = async item => {
  await abrirPasta(caixaId.value, item.pasta);
  emit('navegou');
};

const LINHA =
  'flex items-center w-full min-w-0 gap-2.5 ps-14 pe-2 text-[0.9375rem] leading-5 rounded-lg min-h-11 text-start transition-colors duration-150 motion-reduce:transition-none';
</script>

<template>
  <ul
    v-if="visivel"
    class="grid m-0 p-0 list-none min-w-0"
    :aria-label="t('CONVERSA_CANAL.EMAIL.PASTA.DA_CAIXA', { nome: caixa.name })"
    data-pastas-do-email
  >
    <!-- A gaveta abre com o clique no próprio gatilho (o span dela); o botão só
         desenha a linha, que ocupa a largura toda. -->
    <li class="min-w-0 [&>span]:!flex [&>span]:w-full">
      <NovaConversaEntrada :caixa-id="caixa.id">
        <template #trigger>
          <button
            type="button"
            :class="[LINHA, tema.foco, tema.textoFilho, tema.passar]"
            data-escrever-email
          >
            <Icon icon="i-lucide-pencil" class="size-4 shrink-0" />
            <span class="flex-1 min-w-0 truncate font-medium">
              {{ t('CONVERSA_CANAL.EMAIL.PASTA.ESCREVER') }}
            </span>
          </button>
        </template>
      </NovaConversaEntrada>
    </li>
    <li v-for="item in ITENS" :key="item.chave" class="min-w-0">
      <button
        type="button"
        :class="[
          LINHA,
          tema.foco,
          ativo(item) ? tema.ativo : [tema.textoFilho, tema.passar],
        ]"
        :aria-current="ativo(item) ? 'page' : undefined"
        :data-pasta-do-email="item.pasta || 'entrada'"
        @click="ir(item)"
      >
        <Icon :icon="item.icone" class="size-4 shrink-0" />
        <span class="flex-1 min-w-0 truncate">
          {{ t(`CONVERSA_CANAL.EMAIL.PASTA.${item.chave}`) }}
        </span>
      </button>
    </li>
  </ul>
</template>

<script setup>
// Faixa no topo da lista quando ela mostra uma caixa WAHA comum cujo WhatsApp
// parou (#1941, item 5): diz o estado e leva à aba de conexão da caixa.
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useEstadoDaConexao } from './useEstadoDaConexao';

const props = defineProps({
  caixa: { type: Object, default: null },
});

const { t } = useI18n();
const router = useRouter();
const { estado, mostrar } = useEstadoDaConexao(() => props.caixa);

const usuario = useMapGetter('getCurrentUser');
const idDaConta = useMapGetter('getCurrentAccountId');
const { podeAbrir } = usePodeAbrir();

const conexaoDaCaixa = computed(() => ({
  name: 'settings_inbox_show',
  params: {
    accountId: idDaConta.value,
    inboxId: props.caixa.id,
    tab: 'connection',
  },
}));

// O botão só para quem reconecta: a aba de conexão pede gerenciar a caixa (o servidor
// confere `update?`), e a rota das configurações precisa abrir (flag e permissão dela).
const podeReconectar = computed(
  () =>
    hasPermissions(
      ['administrator', 'inbox_manage'],
      getUserPermissions(usuario.value, idDaConta.value)
    ) && podeAbrir(conexaoDaCaixa.value)
);

// Os mesmos nomes de estado da aba de conexão.
const rotulo = computed(
  () =>
    ({
      awaiting_scan: t('INBOX_MGMT.WAHA_CONNECTION.STATUS.AWAITING'),
      failed: t('INBOX_MGMT.WAHA_CONNECTION.STATUS.FAILED'),
      disconnected: t('INBOX_MGMT.WAHA_CONNECTION.STATUS.DISCONNECTED'),
    })[estado.value]
);

const irParaConexao = () => router.push(conexaoDaCaixa.value);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="mostrar" class="px-3 pb-2" data-faixa="whatsapp-desconectado">
    <Banner
      color="slate"
      :action-label="
        podeReconectar ? t('CONVERSA_CANAL.FAIXA_WHATSAPP.RECONECTAR') : null
      "
      @action="irParaConexao"
    >
      <p class="font-medium text-n-slate-12">{{ rotulo }}</p>
      <p>
        {{ t('CONVERSA_CANAL.FAIXA_WHATSAPP.SEM_MENSAGENS') }}
        <template v-if="!podeReconectar">
          {{ t('CONVERSA_CANAL.FAIXA_WHATSAPP.PECA_AO_ADMIN') }}
        </template>
      </p>
    </Banner>
  </div>
</template>

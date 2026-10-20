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
import { INBOX_PERMISSIONS } from 'dashboard/constants/permissions';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useEstadoDaConexao } from './useEstadoDaConexao';

const props = defineProps({
  caixa: { type: Object, default: null },
});

const { t } = useI18n();
const router = useRouter();
const { estado, mostrar } = useEstadoDaConexao(() => props.caixa);

// O botão só para quem abre as configurações da caixa (a mesma regra da rota).
const usuario = useMapGetter('getCurrentUser');
const idDaConta = useMapGetter('getCurrentAccountId');
const podeReconectar = computed(() =>
  hasPermissions(
    ['administrator', ...INBOX_PERMISSIONS],
    getUserPermissions(usuario.value, idDaConta.value)
  )
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

const irParaConexao = () =>
  router.push({
    name: 'settings_inbox_show',
    params: { inboxId: props.caixa.id, tab: 'connection' },
  });
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

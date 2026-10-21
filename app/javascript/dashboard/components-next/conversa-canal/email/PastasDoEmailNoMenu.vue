<script setup>
// Sub-itens da caixa de e-mail no menu (#1809, fase 1), como no Gmail: Escrever,
// Entrada, Spam e Lixeira. Só em caixa de e-mail e com a chave `conversa_email_nova`.
// - No menu aberto (ForkSidebarFolha): aparecem embaixo da caixa quando ela está aberta.
// - No balão do menu recolhido (`compacto`): sempre embaixo da caixa. O balão do
//   Chatwoot desenha a caixa dentro de um link; os botões daqui cancelam o link
//   (preventDefault, que o RouterLink respeita) e fecham o balão eles mesmos.
// Escrever é ação (abre a gaveta "Nova conversa" já nesta caixa), não rota. Quem só lê
// conversas (#1800) não vê o Escrever; as pastas continuam, para ler o que está nelas.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';
import { usePopoverState } from 'dashboard/components-next/sidebar/provider';
import { ENVIADOS, PASTAS, usePastaDoEmail } from './pastaDoEmail';
import { caixaDaFolha, useCaixaDeEmailNova } from './caixaDeEmailNova';
import { pedirEscrever } from './escreverEmail';

const props = defineProps({
  folha: { type: Object, required: true },
  tema: { type: Object, default: null },
  compacto: { type: Boolean, default: false },
});
const emit = defineEmits(['navegou']);

const { t } = useI18n();
const route = useRoute();
const caixaPorId = useMapGetter('inboxes/getInbox');
const ehEmailNova = useCaixaDeEmailNova();
const { pasta, abrirPasta } = usePastaDoEmail();
const { closeActivePopover } = usePopoverState();
const podeEscrever = usePodeComecarConversa();
const contaAtual = useMapGetter('getCurrentAccountId');
const temChave = useMapGetter('accounts/isFeatureEnabledonAccount');

const caixaId = computed(() => caixaDaFolha(props.folha));
const caixa = computed(() => caixaPorId.value(Number(caixaId.value)) || {});
const aberta = computed(
  () => String(route.params.inbox_id || '') === String(caixaId.value || '')
);
const visivel = computed(
  () => ehEmailNova(caixaId.value) && (props.compacto || aberta.value)
);

// Enviados (#1938) só com a chave `email_enviados`, logo depois da Entrada, como no Gmail.
const ITENS = computed(() => [
  { pasta: null, chave: 'ENTRADA', icone: 'i-lucide-inbox' },
  ...(temChave.value(contaAtual.value, FEATURE_FLAGS.EMAIL_ENVIADOS)
    ? [{ pasta: ENVIADOS, chave: 'ENVIADOS', icone: 'i-lucide-send' }]
    : []),
  { pasta: PASTAS.SPAM, chave: 'SPAM', icone: 'i-lucide-octagon-alert' },
  { pasta: PASTAS.LIXEIRA, chave: 'LIXEIRA', icone: 'i-lucide-trash-2' },
]);

const ativo = item => aberta.value && (pasta.value || null) === item.pasta;
// No balão, o clique não pode seguir para o link da caixa (zeraria a pasta): para aqui
// e o balão fecha por nós.
const ir = async (item, evento) => {
  evento?.preventDefault();
  if (props.compacto) {
    evento?.stopPropagation();
    closeActivePopover?.();
  }
  await abrirPasta(caixaId.value, item.pasta);
  emit('navegou');
};

const escreverDoBalao = () => {
  closeActivePopover?.();
  pedirEscrever(caixaId.value);
};

const LINHA = computed(() =>
  props.compacto
    ? 'flex items-center w-full min-w-0 gap-2 ps-6 pe-2 py-1.5 min-h-9 rounded-lg text-sm text-start transition-colors duration-150'
    : 'flex items-center w-full min-w-0 gap-2.5 ps-14 pe-2 text-[0.9375rem] leading-5 rounded-lg min-h-11 text-start transition-colors duration-150 motion-reduce:transition-none'
);
const estilo = item => {
  if (props.compacto) {
    return ativo(item)
      ? 'text-n-slate-12 bg-n-alpha-2'
      : 'text-n-slate-11 hover:bg-n-alpha-2';
  }
  return [
    props.tema?.foco,
    ativo(item)
      ? props.tema?.ativo
      : [props.tema?.textoFilho, props.tema?.passar],
  ];
};
</script>

<template>
  <ul
    v-if="visivel"
    class="grid m-0 p-0 list-none min-w-0"
    :aria-label="t('CONVERSA_CANAL.EMAIL.PASTA.DA_CAIXA', { nome: caixa.name })"
    data-pastas-do-email
    :data-compacto="compacto || undefined"
  >
    <!-- A gaveta abre com o clique no próprio gatilho (o span dela); o botão só
         desenha a linha, que ocupa a largura toda. -->
    <li v-if="podeEscrever && compacto" class="min-w-0">
      <button
        type="button"
        :class="[LINHA, estilo({})]"
        data-escrever-email
        @click.prevent.stop="escreverDoBalao"
      >
        <Icon icon="i-lucide-pencil" class="size-4 shrink-0" />
        <span class="flex-1 min-w-0 truncate font-medium">
          {{ t('CONVERSA_CANAL.EMAIL.PASTA.ESCREVER') }}
        </span>
      </button>
    </li>
    <li v-else-if="podeEscrever" class="min-w-0 [&>span]:!flex [&>span]:w-full">
      <NovaConversaEntrada :caixa-id="caixa.id">
        <template #trigger>
          <button
            type="button"
            :class="[LINHA, estilo({})]"
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
        :class="[LINHA, estilo(item)]"
        :aria-current="ativo(item) ? 'page' : undefined"
        :data-pasta-do-email="item.pasta || 'entrada'"
        @click="ir(item, $event)"
      >
        <Icon :icon="item.icone" class="size-4 shrink-0" />
        <span class="flex-1 min-w-0 truncate">
          {{ t(`CONVERSA_CANAL.EMAIL.PASTA.${item.chave}`) }}
        </span>
      </button>
    </li>
  </ul>
  <!-- Fora da caixa de e-mail nova: não mostra nada. -->
  <template v-else />
</template>

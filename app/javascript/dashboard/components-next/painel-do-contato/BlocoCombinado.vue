<script setup>
// #2138 — "Combinado": os lembretes abertos do contato, o atrasado primeiro, com a
// data falada no fuso da conta. Até 3; "Ver os outros {n}" abre o resto ali mesmo.
// Sem lembrete, o bloco não aparece; 403 (sem acesso ao CRM) também esconde, sem erro.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { crmSubjectsChange } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import { atrasado } from 'dashboard/routes/dashboard/crm/components/card/proximoPasso';
import Button from 'dashboard/components-next/button/Button.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';
import { useDataFalada } from './useDataFalada';
import { primeiraMaiuscula } from './dataFalada';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const VISIVEIS = 3;
const LIMITE = 20;

const { t } = useI18n();
const { quandoFalado } = useDataFalada();

const estado = ref('carregando');
const lembretes = ref([]);
const total = ref(0);
const abertoTudo = ref(false);
let pedido = 0;

const carregar = async () => {
  pedido += 1;
  const meu = pedido;
  abertoTudo.value = false;
  if (!props.contactId) {
    estado.value = 'escondido';
    return;
  }
  estado.value = 'carregando';
  try {
    const { data } = await CrmKanbanAPI.getFollowUps({
      contact_id: props.contactId,
      status: ['pending', 'overdue'],
      per_page: LIMITE,
    });
    if (meu !== pedido) return;
    lembretes.value = data.payload || [];
    total.value = data.meta?.count ?? lembretes.value.length;
    estado.value = lembretes.value.length ? 'pronto' : 'escondido';
  } catch (erro) {
    if (meu !== pedido) return;
    estado.value = erro?.response?.status === 403 ? 'escondido' : 'erro';
  }
};

watch(() => props.contactId, carregar, { immediate: true });
// Assunto criado ou trocado (aqui ou em tempo real): lê de novo.
watch(() => crmSubjectsChange.value.version, carregar);

const TIPOS = {
  task: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.TASK'),
  message: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.MESSAGE'),
  call: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.CALL'),
  meeting: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.MEETING'),
  note: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.NOTE'),
};

const semPontoFinal = texto =>
  texto.endsWith('.') ? texto.slice(0, -1) : texto;

const agora = () => new Date();
const ordenados = computed(() => {
  const momento = agora();
  return [...lembretes.value]
    .map(item => ({ item, atrasado: atrasado(item, momento) }))
    .sort(
      (a, b) =>
        Number(b.atrasado) - Number(a.atrasado) ||
        new Date(a.item.due_at) - new Date(b.item.due_at)
    );
});

const frase = ({ item, atrasado: estaAtrasado }) => {
  const quando = quandoFalado(new Date(item.due_at));
  const oQue = semPontoFinal(
    String(item.title || '').trim() || TIPOS[item.follow_up_type]?.() || ''
  );
  if (estaAtrasado)
    return t('PAINEL_DO_CONTATO.COMBINADO.ERA_PARA', { quando, oQue });
  if (item.automation_mode === 'auto_send_message')
    return t('PAINEL_DO_CONTATO.COMBINADO.AUTOMATICA', {
      quando: primeiraMaiuscula(quando),
    });
  return t('PAINEL_DO_CONTATO.COMBINADO.QUANDO', {
    quando: primeiraMaiuscula(quando),
    oQue,
  });
};

const mostrados = computed(() =>
  abertoTudo.value ? ordenados.value : ordenados.value.slice(0, VISIVEIS)
);
const outros = computed(() =>
  Math.max(Math.min(total.value, LIMITE) - VISIVEIS, 0)
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <BlocoDoPainel
    v-if="estado !== 'escondido'"
    :titulo="t('PAINEL_DO_CONTATO.COMBINADO.TITULO')"
  >
    <div v-if="estado === 'carregando'" class="flex flex-col gap-2">
      <span class="h-4 rounded w-4/5 bg-n-alpha-2 animate-pulse" />
      <span class="h-4 rounded w-3/5 bg-n-alpha-2 animate-pulse" />
    </div>
    <div v-else-if="estado === 'erro'" class="flex flex-col items-start">
      <p class="m-0 text-sm text-n-slate-12">
        {{ t('PAINEL_DO_CONTATO.ERRO') }}
      </p>
      <Button
        :label="t('PAINEL_DO_CONTATO.TENTAR_DE_NOVO')"
        variant="link"
        color="blue"
        size="sm"
        class="min-h-11"
        @click="carregar"
      />
    </div>
    <template v-else>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="linha in mostrados"
          :key="linha.item.id"
          class="flex gap-2 text-sm"
          :class="linha.atrasado ? 'text-n-amber-11' : 'text-n-slate-12'"
        >
          <span
            v-if="linha.atrasado"
            class="i-lucide-clock flex-shrink-0 mt-0.5 size-4"
            :aria-label="t('PAINEL_DO_CONTATO.COMBINADO.ATRASADO')"
          />
          <span class="line-clamp-2">{{ frase(linha) }}</span>
        </li>
      </ul>
      <div v-if="outros">
        <Button
          :label="
            abertoTudo
              ? t('PAINEL_DO_CONTATO.COMBINADO.MOSTRAR_MENOS')
              : t('PAINEL_DO_CONTATO.COMBINADO.VER_OS_OUTROS', outros)
          "
          variant="link"
          color="blue"
          size="sm"
          class="min-h-11"
          @click="abertoTudo = !abertoTudo"
        />
      </div>
    </template>
  </BlocoDoPainel>
</template>

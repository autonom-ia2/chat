<script setup>
// #2138 — "Combinado": os lembretes abertos do contato, o atrasado primeiro, com a
// data falada no fuso da conta. Até 3; "Ver os outros {n}" abre o resto ali mesmo.
// Sem lembrete, o bloco não aparece; 403 (sem acesso ao CRM) também esconde, sem erro.
//
// Lê de novo quando: o contato muda; um assunto da conversa muda (crmSubjectsChange);
// e o aviso do lembrete (CrmFollowUpReminderModal) entra ou sai da fila — ele entra
// quando um lembrete vence (evento crm.follow_up.due do ActionCable) e sai quando a
// pessoa conclui, adia ou dispensa. Limite: concluir ou editar pelo card, pelo
// calendário ou em outra aba não chega aqui até a próxima leitura.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { crmSubjectsChange } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import { useCrmFollowUpReminders } from 'dashboard/composables/useCrmFollowUpReminders';
import { atrasado } from 'dashboard/routes/dashboard/crm/components/card/proximoPasso';
import Button from 'dashboard/components-next/button/Button.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';
import EsqueletoOuErro from './EsqueletoOuErro.vue';
import { ESTADO, useParteDoPainel } from './useParteDoPainel';
import { useDataFalada } from './useDataFalada';
import { primeiraMaiuscula } from './dataFalada';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const VISIVEIS = 3;
const LIMITE = 20;

const { t } = useI18n();
const { quandoFalado } = useDataFalada();
const { activeReminder } = useCrmFollowUpReminders();
const abertoTudo = ref(false);

const { estado, dados, carregar, esconder } = useParteDoPainel(
  async () => {
    const { data } = await CrmKanbanAPI.getFollowUps({
      contact_id: props.contactId,
      status: ['pending', 'overdue'],
      per_page: LIMITE,
    });
    const lembretes = data.payload || [];
    return { lembretes, total: data.meta?.count ?? lembretes.length };
  },
  resposta => resposta.lembretes.length > 0
);

const ler = () => {
  abertoTudo.value = false;
  if (props.contactId) carregar();
  else esconder();
};

watch(() => props.contactId, ler, { immediate: true });
watch(() => crmSubjectsChange.value.version, ler);
// O aviso do lembrete deste contato (ou um aviso sem contato) entrou ou saiu.
const doContato = lembrete =>
  lembrete &&
  (lembrete.contact_id == null ||
    String(lembrete.contact_id) === String(props.contactId));
watch(activeReminder, (novo, velho) => {
  if (novo?.id === velho?.id) return;
  if (doContato(novo) || doContato(velho)) ler();
});

const TIPOS = {
  task: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.TASK'),
  message: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.MESSAGE'),
  call: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.CALL'),
  meeting: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.MEETING'),
  note: () => t('PAINEL_DO_CONTATO.COMBINADO.TIPO.NOTE'),
};

const semPontoFinal = texto =>
  texto.endsWith('.') ? texto.slice(0, -1) : texto;

const ordenados = computed(() => {
  const momento = new Date();
  return [...(dados.value?.lembretes || [])]
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
  Math.max(Math.min(dados.value?.total ?? 0, LIMITE) - VISIVEIS, 0)
);
const visivel = computed(() =>
  [ESTADO.CARREGANDO, ESTADO.PRONTO, ESTADO.ERRO].includes(estado.value)
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <BlocoDoPainel
    v-if="visivel"
    :titulo="
      estado === ESTADO.CARREGANDO
        ? ''
        : t('PAINEL_DO_CONTATO.COMBINADO.TITULO')
    "
    data-test-id="bloco-combinado"
  >
    <EsqueletoOuErro
      v-if="estado !== ESTADO.PRONTO"
      :estado="estado"
      @tentar="ler"
    />
    <template v-else>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="linha in mostrados"
          :key="linha.item.id"
          class="flex gap-2 text-sm"
          :class="linha.atrasado ? 'text-n-amber-11' : 'text-n-slate-12'"
          :data-atrasado="linha.atrasado || undefined"
        >
          <span
            v-if="linha.atrasado"
            class="i-lucide-clock flex-shrink-0 mt-0.5 size-4"
            role="img"
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

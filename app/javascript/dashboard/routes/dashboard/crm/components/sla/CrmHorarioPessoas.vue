<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmServiceSchedulesAPI from 'dashboard/api/crmServiceSchedules';
import {
  comMaiuscula,
  diasDosBlocos,
  horarioEmTexto,
} from 'dashboard/helper/horarioEmTexto';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmScheduleEditor from './CrmScheduleEditor.vue';

// #1619 (flag `horario_unico_caixa`) — "Horário de cada pessoa" em CRM › SLA: o calendário de SLA com
// dono pessoa (Crm::ServiceSchedule owner User), o mesmo de Configurações › Agentes, aberto também
// daqui pelo CrmScheduleEditor, que com a flag grava o fuso da conta.
const { t } = useI18n();
const store = useStore();
const NS = 'HORARIO_DO_CANAL.SLA';

const pessoas = useMapGetter('agents/getAgents');

const calendarios = ref([]);
const carregou = ref(false);
const carregando = ref(false);
const erro = ref(false);
const editando = ref(null);

const ler = async () => {
  carregando.value = true;
  try {
    const { data } = await CrmServiceSchedulesAPI.get();
    calendarios.value = (data.payload || []).filter(
      calendario => calendario.owner_type === 'User'
    );
    erro.value = false;
    carregou.value = true;
  } catch {
    // Sem a leitura, toda pessoa pareceria "sem horário" e salvar escreveria por cima do real.
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  ler();
});

const calendarioDe = id =>
  calendarios.value.find(calendario => calendario.owner_id === id) || null;

// Desligado não vale para o SLA: a pessoa segue o horário do canal.
const textoDe = calendario =>
  calendario?.enabled
    ? comMaiuscula(horarioEmTexto(diasDosBlocos(calendario.blocks), t))
    : null;

const linhas = computed(() =>
  (pessoas.value || []).map(pessoa => {
    const calendario = calendarioDe(pessoa.id);
    return {
      id: pessoa.id,
      nome: pessoa.available_name || pessoa.name,
      iniciais: (pessoa.available_name || pessoa.name || '')
        .split(' ')
        .filter(Boolean)
        .slice(0, 2)
        .map(parte => parte[0].toUpperCase())
        .join(''),
      calendario,
      texto: textoDe(calendario),
    };
  })
);

const salvo = calendario => {
  calendarios.value = [
    ...calendarios.value.filter(item => item.owner_id !== calendario.owner_id),
    calendario,
  ];
  editando.value = null;
};
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-base font-medium text-n-slate-12">
        {{ t(`${NS}.PESSOAS_TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.PESSOAS_TEXTO`) }}
      </p>
    </div>

    <div
      v-if="erro"
      data-erro
      class="flex flex-col items-start gap-2 p-4 border rounded-lg border-n-weak"
    >
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.LER_ERRO`) }}</p>
      <Button
        sm
        slate
        faded
        :label="t(`${NS}.TENTAR_DE_NOVO`)"
        :is-loading="carregando"
        @click="ler"
      />
    </div>
    <p v-else-if="!carregou" role="status" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.CARREGANDO`) }}
    </p>
    <p v-else-if="!linhas.length" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.SEM_PESSOAS`) }}
    </p>
    <ul
      v-else
      class="flex flex-col p-0 m-0 list-none border divide-y rounded-xl border-n-weak divide-n-weak"
    >
      <li
        v-for="linha in linhas"
        :key="linha.id"
        data-pessoa
        class="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
      >
        <div class="flex items-center min-w-0 gap-3">
          <span
            aria-hidden="true"
            class="flex items-center justify-center text-xs font-semibold rounded-full size-8 shrink-0 bg-n-blue-3 text-n-blue-11"
          >
            {{ linha.iniciais }}
          </span>
          <div class="min-w-0">
            <p class="m-0 text-sm font-medium truncate text-n-slate-12">
              {{ linha.nome }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ linha.texto || t(`${NS}.PESSOA_SEM_HORARIO`) }}
            </p>
          </div>
        </div>
        <Button
          sm
          slate
          faded
          type="button"
          class="min-h-11"
          :label="linha.texto ? t(`${NS}.ALTERAR`) : t(`${NS}.DEFINIR`)"
          :aria-label="
            linha.texto
              ? t(`${NS}.ALTERAR_ROTULO`, { nome: linha.nome })
              : t(`${NS}.DEFINIR_ROTULO`, { nome: linha.nome })
          "
          @click="editando = linha"
        />
      </li>
    </ul>

    <CrmScheduleEditor
      v-if="editando && carregou && !erro"
      owner-type="User"
      :owner-id="editando.id"
      :owner-name="editando.nome"
      :schedule="editando.calendario"
      @saved="salvo"
      @close="editando = null"
    />
  </section>
</template>

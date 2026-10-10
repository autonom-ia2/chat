<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';
import { TIPO_CANAL, tipoDoCanal, trocaNoCanal } from '../utils/canais';
import EscolhaRadio from './EscolhaRadio.vue';

// #1181 — "Onde e quando {nome} atende" (protótipo T05 e T10). Onde: caixas da leitura L2 (livre,
// já com outro agente — com troca — ou com outro sistema, que não dá para escolher). Quando: sempre,
// só no horário ou só fora dele, salvo em config.response_window. O horário de cada caixa vem de
// quem usa, em `horarios` ({ [inbox_id]: texto | null }): texto mostra o horário, null quer dizer
// "sem horário" (só "Sempre" fica disponível) e caixa ausente aparece sem horário, sem travar.
// Sem lista suspensa nativa: tudo em cartões-rádio.
const props = defineProps({
  canais: { type: Array, required: true },
  agenteId: { type: Number, default: null },
  nome: { type: String, required: true },
  onde: { type: Number, default: null },
  quando: { type: String, default: 'always' },
  horarios: { type: Object, default: () => ({}) },
  // A L2 falhou e a lista veio só das caixas livres (eligible_inboxes).
  semLeitura: { type: Boolean, default: false },
});

const emit = defineEmits(['update:onde', 'update:quando']);

const { t } = useI18n();
const router = useRouter();
const { podeEscolherQuemRecebe } = usePermissoesDaJornada();

const NS = 'AGENTS.JORNADA.ONDE_QUANDO';
const QUANDO = {
  always: 'SEMPRE',
  business_hours: 'DENTRO',
  outside_business_hours: 'FORA',
};

const opcaoDoCanal = canal => {
  const tipo = tipoDoCanal(canal, props.agenteId);
  if (tipo === TIPO_CANAL.EXTERNO) {
    return {
      valor: canal.inbox_id,
      titulo: t('AGENTS.JORNADA.ONDE_QUANDO.EXTERNO', { canal: canal.name }),
      texto: t('AGENTS.JORNADA.ONDE_QUANDO.EXTERNO_TEXTO'),
      desabilitada: true,
    };
  }
  if (tipo === TIPO_CANAL.OCUPADO) {
    return {
      valor: canal.inbox_id,
      titulo: t('AGENTS.JORNADA.ONDE_QUANDO.OCUPADO', {
        canal: canal.name,
        agente: canal.occupied_by.agent_name,
      }),
      texto: t('AGENTS.JORNADA.ONDE_QUANDO.OCUPADO_TEXTO', {
        nome: props.nome,
      }),
      ambar: true,
    };
  }
  return { valor: canal.inbox_id, titulo: canal.name };
};

const opcoesOnde = computed(() => props.canais.map(opcaoDoCanal));

const todosOcupados = computed(
  () =>
    props.canais.length > 0 &&
    !props.canais.some(
      canal => tipoDoCanal(canal, props.agenteId) === TIPO_CANAL.LIVRE
    )
);

const troca = computed(() =>
  trocaNoCanal(props.canais, props.onde, props.agenteId)
);

// undefined = caixa fora do mapa (sem texto, sem trava); null = caixa sem horário.
const horarioDe = inboxId =>
  inboxId in props.horarios ? props.horarios[inboxId] : undefined;

const semHorario = computed(
  () => props.onde !== null && horarioDe(props.onde) === null
);

const opcoesQuando = computed(() => {
  const horario = horarioDe(props.onde);
  return Object.entries(QUANDO).map(([valor, chave]) => {
    let texto = '';
    if (valor === 'always') {
      texto = t('AGENTS.JORNADA.ONDE_QUANDO.SEMPRE_TEXTO');
    } else if (horario) {
      texto = t(`${NS}.${chave}_TEXTO`, { horario });
    }
    return {
      valor,
      titulo: t(`${NS}.${chave}`),
      texto,
      desabilitada: valor !== 'always' && semHorario.value,
    };
  });
});

const escolherOnde = inboxId => {
  emit('update:onde', inboxId);
  if (props.quando !== 'always' && horarioDe(inboxId) === null) {
    emit('update:quando', 'always');
  }
};

const linkQuemRecebe = computed(
  () => router.resolve({ name: 'crm_handoff_settings_index' }).href
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <section class="flex flex-col gap-2">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.ONDE') }}
      </h3>
      <p v-if="todosOcupados" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.TODOS_OCUPADOS', { nome }) }}
      </p>
      <EscolhaRadio
        :rotulo="t('AGENTS.JORNADA.ONDE_QUANDO.ONDE')"
        :opcoes="opcoesOnde"
        :model-value="onde"
        @update:model-value="escolherOnde"
      />
      <p
        v-if="troca"
        data-troca
        class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
      >
        {{
          t('AGENTS.JORNADA.ONDE_QUANDO.TROCA', {
            outro: troca.nome,
            canal: troca.canal,
          })
        }}
      </p>
      <p v-if="semLeitura" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.SEM_LEITURA') }}
      </p>
    </section>

    <section class="flex flex-col gap-2">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.QUANDO') }}
      </h3>
      <EscolhaRadio
        :rotulo="t('AGENTS.JORNADA.ONDE_QUANDO.QUANDO')"
        :opcoes="opcoesQuando"
        :model-value="quando"
        @update:model-value="emit('update:quando', $event)"
      />
      <p v-if="semHorario" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.SEM_HORARIO') }}
      </p>
    </section>

    <div class="flex flex-col gap-1 p-3 text-sm rounded-xl bg-n-blue-2">
      <p class="m-0 text-n-slate-12">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.QUEM_RECEBE', { nome }) }}
      </p>
      <a
        v-if="podeEscolherQuemRecebe"
        data-quem-recebe
        :href="linkQuemRecebe"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 font-medium underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.ESCOLHER_QUEM_RECEBE') }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
      </a>
      <p v-else class="m-0 text-n-slate-11">
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.QUEM_RECEBE_SEM_PERMISSAO') }}
      </p>
    </div>
  </div>
</template>

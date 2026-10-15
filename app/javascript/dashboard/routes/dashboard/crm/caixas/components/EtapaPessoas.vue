<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AgentesDaCaixa from './AgentesDaCaixa.vue';
import { corDoFunil, portaOuRobo, roboExterno } from '../helpers/caixa';
import { aoTeclarNoGrupo } from '../helpers/setas';

// #1149 — etapa 2: quem cuida do quê. Para cada pessoa da caixa, de quais
// assuntos ela cuida (inclusive as conversas ainda sem assunto) e se vê todas
// as conversas deles ou só as que atende. Quem cuida de um funil entra no
// rodízio dos cards novos dele (R8). Administrador vê tudo. Com a Fase 2 dos
// Agentes (`aiAgents`), os agentes de IA vêm antes, com a porta primeiro
// (#1447); sem ela, só a frase do robô que atende primeiro, como sempre.
const props = defineProps({
  // Só os funis marcados na etapa 1.
  funis: { type: Array, required: true },
  todosOsFunis: { type: Array, required: true },
  faltaTriagem: { type: Boolean, default: false },
  // R6: caixa ainda em "Agente vê apenas atribuídos".
  legado: { type: Boolean, default: false },
  // Robô que atende primeiro na caixa ({ id, name }), quando há.
  robo: { type: Object, default: null },
  // 'manter', 'mudar' ou null enquanto a pessoa não escolheu.
  escolha: { type: String, default: null },
});

const emit = defineEmits(['escolherLegado']);
const pessoas = defineModel('pessoas', { type: Array, required: true });
// { porta, pode_mudar, agentes } ou null sem a Fase 2 (helpers/agentesIa).
const aiAgents = defineModel('aiAgents', { type: Object, default: null });

const porta = computed(() => portaOuRobo(aiAgents.value?.porta, props.robo));
// A frase do robô: sem a Fase 2, como sempre; com ela, só quando o robô não
// entra como porta (agente externo, #1570).
const mostraORobo = computed(
  () => Boolean(props.robo) && (!aiAgents.value || !porta.value)
);
const agentesIa = computed({
  get: () => aiAgents.value?.agentes || [],
  set: agentes => {
    aiAgents.value = { ...aiAgents.value, agentes };
  },
});
const temAgentes = computed(
  () =>
    Boolean(aiAgents.value) &&
    (Boolean(porta.value) || agentesIa.value.length > 0)
);

const atualizar = (pessoa, mudanca) => {
  pessoas.value = pessoas.value.map(item =>
    item.id === pessoa.id ? { ...item, ...mudanca } : item
  );
};

const cuida = (pessoa, funil) => pessoa.pipeline_ids.includes(funil.id);
const cuidaDeAlgo = pessoa =>
  (props.funis.length > 1 && pessoa.triage) || pessoa.pipeline_ids.length > 0;

const alternarFunil = (pessoa, funil) =>
  atualizar(pessoa, {
    pipeline_ids: cuida(pessoa, funil)
      ? pessoa.pipeline_ids.filter(id => id !== funil.id)
      : [...pessoa.pipeline_ids, funil.id],
  });

const todosCuidamDeTudo = () => {
  pessoas.value = pessoas.value.map(pessoa =>
    pessoa.administrator
      ? pessoa
      : {
          ...pessoa,
          triage: true,
          only_own: false,
          pipeline_ids: props.funis.map(funil => funil.id),
        }
  );
};

const ordenadas = computed(() =>
  [...pessoas.value].sort(
    (a, b) =>
      Number(a.administrator) - Number(b.administrator) ||
      a.name.localeCompare(b.name)
  )
);

const chipClasse = ativo =>
  ativo
    ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-11'
    : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-slate-7';
</script>

<template>
  <div class="flex flex-col gap-5">
    <p
      v-if="mostraORobo"
      data-robo
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-alpha-2 px-4 py-3 text-[0.9375rem] text-n-slate-12"
    >
      <span class="i-lucide-bot mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{
        roboExterno(robo)
          ? $t('CRM_CAIXAS.PESSOAS.ROBO_EXTERNO', { nome: robo.name })
          : $t('CRM_CAIXAS.PESSOAS.ROBO', { nome: robo.name })
      }}
    </p>
    <div
      v-if="legado"
      data-legado
      class="flex flex-col gap-3 rounded-2xl border border-n-amber-7 bg-n-amber-2 p-4 md:flex-row md:items-center"
    >
      <span
        class="i-lucide-eye-off size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <p class="mb-0 flex-1 text-[0.9375rem] text-n-slate-12">
        {{ $t('CRM_CAIXAS.PESSOAS.LEGADO') }}
      </p>
      <div class="flex shrink-0 flex-wrap gap-2">
        <button
          v-for="opcao in ['manter', 'mudar']"
          :key="opcao"
          type="button"
          :data-legado-escolha="opcao"
          :aria-pressed="escolha === opcao"
          class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-solid px-3 text-[0.9375rem] font-medium"
          :class="chipClasse(escolha === opcao)"
          @click="emit('escolherLegado', opcao)"
        >
          <span
            v-if="escolha === opcao"
            class="i-lucide-check size-4"
            aria-hidden="true"
          />
          {{
            opcao === 'manter'
              ? $t('CRM_CAIXAS.PESSOAS.LEGADO_MANTER')
              : $t('CRM_CAIXAS.PESSOAS.LEGADO_MUDAR')
          }}
        </button>
      </div>
    </div>

    <section v-if="temAgentes" class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_CAIXAS.PESSOAS.AGENTES_TITULO') }}
        </h3>
        <p data-regra class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{
            porta
              ? $t('CRM_CAIXAS.PESSOAS.REGRA', { porta: porta.name })
              : $t('CRM_CAIXAS.PESSOAS.REGRA_SEM_PORTA')
          }}
        </p>
      </div>
      <AgentesDaCaixa
        v-model:agentes="agentesIa"
        :porta="porta"
        :pode-mudar="aiAgents.pode_mudar"
        :funis="funis"
        :todos-os-funis="todosOsFunis"
      />
    </section>

    <div
      class="flex flex-wrap justify-between gap-3"
      :class="temAgentes ? 'items-end' : 'items-center'"
    >
      <div class="flex flex-col gap-1">
        <h3
          v-if="temAgentes"
          class="mb-0 text-base font-semibold text-n-slate-12"
        >
          {{ $t('CRM_CAIXAS.PESSOAS.PESSOAS_TITULO') }}
        </h3>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t('CRM_CAIXAS.PESSOAS.EXPLICA') }}
        </p>
      </div>
      <Button
        data-todos
        :label="$t('CRM_CAIXAS.PESSOAS.TODOS_TUDO')"
        icon="i-lucide-users"
        slate
        ghost
        class="!min-h-11"
        @click="todosCuidamDeTudo"
      />
    </div>

    <p
      v-if="faltaTriagem"
      role="alert"
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-ruby-3 px-4 py-3 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-ruby-11"
        aria-hidden="true"
      />
      {{ $t('CRM_CAIXAS.PESSOAS.FALTA_TRIAGEM') }}
    </p>

    <ul class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="pessoa in ordenadas"
        :key="pessoa.id"
        data-pessoa
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
      >
        <div class="flex flex-wrap items-center gap-3">
          <Avatar :name="pessoa.name" :size="36" rounded-full />
          <div class="min-w-0 flex-1">
            <p class="mb-0 truncate text-base font-semibold text-n-slate-12">
              {{ pessoa.name }}
            </p>
            <p class="mb-0 text-sm text-n-slate-11">
              {{
                pessoa.administrator
                  ? $t('CRM_CAIXAS.PESSOAS.ADMIN_VE_TUDO')
                  : !cuidaDeAlgo(pessoa)
                    ? $t('CRM_CAIXAS.PESSOAS.NAO_VE')
                    : ''
              }}
            </p>
          </div>
          <div
            v-if="!pessoa.administrator && cuidaDeAlgo(pessoa)"
            role="radiogroup"
            :aria-label="$t('CRM_CAIXAS.PESSOAS.VE', { nome: pessoa.name })"
            class="flex w-full shrink-0 rounded-xl bg-n-alpha-2 p-1 sm:w-auto"
            @keydown="
              aoTeclarNoGrupo($event, [false, true], pessoa.only_own, valor =>
                atualizar(pessoa, { only_own: valor })
              )
            "
          >
            <button
              v-for="opcao in [false, true]"
              :key="String(opcao)"
              type="button"
              role="radio"
              :aria-checked="pessoa.only_own === opcao"
              :tabindex="pessoa.only_own === opcao ? 0 : -1"
              class="min-h-10 flex-1 whitespace-nowrap rounded-lg px-3 text-[0.9375rem] font-medium"
              :class="
                pessoa.only_own === opcao
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="atualizar(pessoa, { only_own: opcao })"
            >
              {{
                opcao
                  ? $t('CRM_CAIXAS.PESSOAS.SO_AS_QUE_ATENDE')
                  : $t('CRM_CAIXAS.PESSOAS.TODAS')
              }}
            </button>
          </div>
        </div>

        <div
          v-if="!pessoa.administrator"
          class="flex flex-wrap gap-2"
          role="group"
          :aria-label="$t('CRM_CAIXAS.PESSOAS.CUIDA_DE', { nome: pessoa.name })"
        >
          <button
            v-if="funis.length > 1"
            type="button"
            data-triagem
            :aria-pressed="pessoa.triage"
            class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-solid px-3 text-[0.9375rem] font-medium"
            :class="chipClasse(pessoa.triage)"
            @click="atualizar(pessoa, { triage: !pessoa.triage })"
          >
            <span
              :class="pessoa.triage ? 'i-lucide-check' : 'i-lucide-plus'"
              class="size-4"
              aria-hidden="true"
            />
            {{ $t('CRM_CAIXAS.PESSOAS.SEM_ASSUNTO') }}
          </button>
          <button
            v-for="funil in funis"
            :key="funil.id"
            type="button"
            :aria-pressed="cuida(pessoa, funil)"
            class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-solid px-3 text-[0.9375rem] font-medium"
            :class="chipClasse(cuida(pessoa, funil))"
            @click="alternarFunil(pessoa, funil)"
          >
            <span
              :class="cuida(pessoa, funil) ? 'i-lucide-check' : 'i-lucide-plus'"
              class="size-4"
              aria-hidden="true"
            />
            <span
              class="size-2.5 rounded-full"
              :class="corDoFunil(todosOsFunis, funil.id)"
              aria-hidden="true"
            />
            {{ funil.name }}
          </button>
        </div>
      </li>
    </ul>

    <div class="flex flex-col gap-2 text-[0.9375rem] text-n-slate-11">
      <p class="mb-0 flex items-start gap-2">
        <span
          class="i-lucide-repeat mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t('CRM_CAIXAS.PESSOAS.RODIZIO') }}
      </p>
      <p class="mb-0 flex items-start gap-2">
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ $t('CRM_CAIXAS.PESSOAS.SO_AS_QUE_ATENDE_EXPLICA') }}
      </p>
    </div>
  </div>
</template>

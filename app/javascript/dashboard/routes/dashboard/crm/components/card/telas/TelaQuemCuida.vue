<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { semDonosBarrados } from '../../../helpers/accessErrors';

// #1423 — quem cuida do cliente. Quem pode mexer no card troca o dono aqui
// mesmo (decisão do Rodrigo, DN-02/OB-07). A lista é a mesma da Lista do CRM:
// só aparece quem cuida do funil e da caixa deste card (owner_options, #1149);
// o servidor confere de novo (CardGuard) e a recusa vira aviso traduzido.
// Embaixo, quem responde a conversa agora e quem atende cada conversa.
const props = defineProps({
  card: { type: Object, required: true },
  conversas: { type: Array, default: () => [] },
  agentes: { type: Array, default: () => [] },
  podeGerenciar: { type: Boolean, default: false },
});
const dono = defineModel('dono', { type: [String, Number], default: '' });

const { t } = useI18n();
const D = 'CRM_CARD.DONO';
const campoId = useId();

const barrados = ref([]);
onMounted(async () => {
  if (!props.podeGerenciar || !props.card.id) return;
  try {
    const { data } = await CrmKanbanAPI.getOwnerOptions({
      cardIds: [props.card.id],
    });
    barrados.value = data?.payload?.cards?.[props.card.id] || [];
  } catch {
    // Sem a lista, o servidor ainda recusa o dono sem o funil e a tela avisa.
  }
});
const opcoes = computed(() => {
  const lista = semDonosBarrados(props.agentes, barrados.value).map(agente => ({
    value: agente.id,
    label: agente.name,
  }));
  // O dono de agora aparece sempre, mesmo que tenha saído do funil.
  const atual = props.card.owner;
  if (atual?.id && !lista.some(opcao => opcao.value === atual.id))
    lista.unshift({ value: atual.id, label: atual.name });
  return lista;
});

const responsavel = computed(() => {
  const quem = props.card.responsible;
  if (!quem || quem.type === 'none' || !quem.name) return t(`${D}.NINGUEM`);
  return quem.type === 'bot'
    ? t(`${D}.ASSISTENTE`, { nome: quem.name })
    : quem.name;
});
const atendentes = computed(() =>
  props.conversas
    .filter(conversa => conversa.assignee_name)
    .map(conversa => ({
      chave: conversa.id || conversa.display_id,
      numero: conversa.display_id,
      nome: conversa.assignee_name,
    }))
);
</script>

<template>
  <section class="flex flex-col gap-4" data-tela="dono">
    <article
      class="flex items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <span
        class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-teal-3 text-n-teal-11"
        aria-hidden="true"
      >
        <span class="i-lucide-user-check size-6" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-2">
        <template v-if="podeGerenciar">
          <label
            :for="campoId"
            class="mb-0 text-sm font-medium text-n-slate-11"
          >
            {{ t(`${D}.CUIDA`) }}
          </label>
          <ChoiceSelect
            v-model="dono"
            data-dono-escolha
            :trigger-id="campoId"
            :options="opcoes"
            :placeholder="t(`${D}.ESCOLHA`)"
            :aria-label="t(`${D}.CUIDA`)"
            class="w-full sm:max-w-sm"
          />
          <p class="mb-0 text-sm text-n-slate-11">{{ t(`${D}.SO_FUNIL`) }}</p>
        </template>
        <template v-else>
          <h3 class="mb-0 text-sm font-medium text-n-slate-11">
            {{ t(`${D}.CUIDA`) }}
          </h3>
          <p class="mb-0 text-lg font-semibold text-n-slate-12">
            {{ card.owner?.name || t(`${D}.NINGUEM`) }}
          </p>
        </template>
      </div>
    </article>
    <article
      class="flex items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <span
        class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span
          class="size-6"
          :class="
            card.responsible?.type === 'bot'
              ? 'i-lucide-bot'
              : 'i-lucide-headset'
          "
        />
      </span>
      <div class="flex min-w-0 flex-col gap-1">
        <h3 class="mb-0 text-sm font-medium text-n-slate-11">
          {{ t(`${D}.RESPONDE`) }}
        </h3>
        <p class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ responsavel }}
        </p>
        <ul
          v-if="atendentes.length"
          class="m-0 mt-1 flex list-none flex-col gap-1 p-0"
        >
          <li
            v-for="item in atendentes"
            :key="item.chave"
            class="text-sm text-n-slate-11"
          >
            {{
              t(`${D}.CONVERSA_DE`, { numero: item.numero, nome: item.nome })
            }}
          </li>
        </ul>
      </div>
    </article>
  </section>
</template>

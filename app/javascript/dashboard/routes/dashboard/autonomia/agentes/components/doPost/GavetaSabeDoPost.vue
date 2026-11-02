<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';
import AgenteGaveta from '../AgenteGaveta.vue';
import MaterialLinha from '../pagina/MaterialLinha.vue';
import { agentesDasPortas } from '../../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436) — "O que sabe" do cartão do post: a base do agente da porta (a mesma do atendimento; mudar
// lá muda aqui), uma por agente quando o anúncio tem uma porta em cada rede, e o que é só deste post ou anúncio: o que
// a IA viu na foto e o "algo a mais" do dono, gravados no cuidado (mudar é no próprio cuidado). Sem agente na porta,
// diz que ficam as frases fixas. O material anexado só para o post entra no 3b.
const props = defineProps({
  detalhe: { type: Object, required: true },
  // A tela do cuidado (os passos), para "Mudar no cuidado"; null para quem só vê.
  rotaDoCuidado: { type: Object, default: null },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.SABE';

const agentes = computed(() => agentesDasPortas(props.detalhe.portas));
// { agentId: [fontes] }, do mais novo para o mais antigo. Sem leitura, a lista fica vazia (o link continua).
const fontes = ref({});
onMounted(() => {
  agentes.value.forEach(async agente => {
    try {
      const { data } = await AutonomiaSourcesAPI.get(agente.id);
      const lista = [...(data.payload || data || [])];
      fontes.value = {
        ...fontes.value,
        [agente.id]: lista.sort((uma, outra) => outra.id - uma.id),
      };
    } catch {
      fontes.value = { ...fontes.value, [agente.id]: [] };
    }
  });
});
</script>

<template>
  <AgenteGaveta :titulo="t(`${KEY}.TITULO`)" @fechar="emit('fechar')">
    <div data-gaveta-sabe class="flex flex-col gap-4">
      <section
        v-for="agente in agentes"
        :key="agente.id"
        data-materiais
        class="flex flex-col gap-3"
      >
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${KEY}.MATERIAIS`, { nome: agente.name }) }}
        </h3>
        <ul
          v-if="fontes[agente.id]?.length"
          class="flex flex-col gap-2 p-0 m-0 list-none"
        >
          <MaterialLinha
            v-for="fonte in fontes[agente.id]"
            :key="fonte.id"
            :fonte="fonte"
            :nome-agente="agente.name"
          />
        </ul>
        <p v-else-if="fontes[agente.id]" class="m-0 text-sm text-n-slate-11">
          {{ t(`${KEY}.SEM_MATERIAL`, { nome: agente.name }) }}
        </p>
        <p
          class="flex flex-wrap items-center m-0 text-sm gap-x-3 text-n-slate-11"
        >
          <router-link
            :to="{
              name: 'autonomia_agent_panel',
              params: { agentId: agente.id, tab: 'knowledge' },
            }"
            class="inline-flex items-center font-semibold underline min-h-11 w-fit text-n-blue-11"
          >
            {{ t(`${KEY}.MUDAR`, { nome: agente.name }) }}
          </router-link>
          <span data-aviso-mudar class="inline-flex items-center gap-1.5">
            <span
              class="i-lucide-info size-4 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ t(`${KEY}.AVISO`) }}
          </span>
        </p>
      </section>
      <div
        v-if="!agentes.length"
        data-sem-porta
        class="flex flex-col gap-3 p-4 rounded-2xl bg-n-alpha-1"
      >
        <p class="m-0 text-sm leading-6 text-n-slate-12">
          {{ t(`${KEY}.SEM_PORTA`) }}
        </p>
        <router-link
          :to="{ name: 'autonomia_agents_builder' }"
          class="inline-flex items-center justify-center px-4 text-sm font-semibold text-white rounded-xl min-h-11 w-fit bg-n-brand"
        >
          {{ t(`${KEY}.ENSINAR`) }}
        </router-link>
      </div>
      <section
        data-so-do-post
        class="flex flex-col gap-3 pt-4 border-0 border-t border-solid border-n-weak"
      >
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${KEY}.SO_DO_POST`) }}
        </h3>
        <div
          data-o-que-vi
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
        >
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t(`${KEY}.FOTO`) }}
          </span>
          <p class="m-0 text-sm leading-6 text-n-slate-12">
            {{ detalhe.foto || t(`${KEY}.SEM_FOTO`) }}
          </p>
        </div>
        <div
          v-if="detalhe.nota"
          data-nota
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
        >
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t(`${KEY}.NOTA`) }}
          </span>
          <p class="m-0 text-sm leading-6 text-n-slate-12">
            {{ detalhe.nota }}
          </p>
        </div>
        <router-link
          v-if="rotaDoCuidado"
          data-mudar-no-cuidado
          :to="rotaDoCuidado"
          class="inline-flex items-center font-semibold underline text-sm min-h-11 w-fit text-n-blue-11"
        >
          {{ t(`${KEY}.MUDAR_NO_CUIDADO`) }}
        </router-link>
      </section>
    </div>
  </AgenteGaveta>
</template>

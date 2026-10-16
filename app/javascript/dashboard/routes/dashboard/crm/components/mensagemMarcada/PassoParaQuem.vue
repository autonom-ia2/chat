<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #1590 — "Para quem?": uma busca grande pelo nome do cliente ou do negócio.
// Sem nada digitado, os negócios mexidos por último, para um clique só. Quem
// ainda não conversou pelo WhatsApp (ou só por uma caixa desconectada) aparece
// apagado, com o motivo numa frase: não há para onde a mensagem ir. Quem
// conversa por outra caixa de WhatsApp (Twilio, caixa API) é marcado pelo
// retorno do card: a linha diz isso e abre o negócio.
const props = defineProps({
  paraAlvo: { type: Function, required: true },
});
const emit = defineEmits(['escolher', 'abrirNegocio']);

const { t } = useI18n();
const M = 'CRM_MENSAGEM_MARCADA.PARA_QUEM';
const MINIMO = 2;
const POR_BUSCA = 6;
const ESPERA = 300;
const SEPARADOR = ' · ';

const termo = ref('');
const achados = ref([]);
const buscando = ref(false);
const falhou = ref(false);
const curto = computed(() => termo.value.trim().length < MINIMO);

let pedido = 0;
let espera = null;
const buscar = async texto => {
  pedido += 1;
  const meu = pedido;
  falhou.value = false;
  buscando.value = true;
  try {
    const { data } = await CrmKanbanAPI.getCards({
      search: texto.trim().length >= MINIMO ? texto.trim() : undefined,
      per_page: POR_BUSCA,
    });
    if (meu !== pedido) return;
    achados.value = (data?.payload || []).map(card => ({
      card,
      ...props.paraAlvo(card),
    }));
  } catch {
    if (meu === pedido) {
      achados.value = [];
      falhou.value = true;
    }
  } finally {
    if (meu === pedido) buscando.value = false;
  }
};
watch(termo, texto => {
  clearTimeout(espera);
  espera = setTimeout(() => buscar(texto), ESPERA);
});
onMounted(() => buscar(''));

const clicar = achado => {
  if (achado.oficial) emit('escolher', achado.card);
  else if (achado.conectada) emit('abrirNegocio', achado.cardId);
};
const linha = achado => {
  if (!achado.conectada) return t(`${M}.SEM_WHATSAPP`);
  if (!achado.oficial) return t(`${M}.PELO_NEGOCIO`);
  return [achado.negocio, achado.telefone].filter(Boolean).join(SEPARADOR);
};
onBeforeUnmount(() => clearTimeout(espera));
</script>

<template>
  <section data-passo="para-quem" class="flex flex-col gap-4">
    <label class="flex flex-col gap-2">
      <span class="text-base font-semibold text-n-slate-12">
        {{ t(`${M}.ROTULO`) }}
      </span>
      <span class="relative flex items-center">
        <span
          class="i-lucide-search pointer-events-none absolute start-4 size-5 text-n-slate-10"
          aria-hidden="true"
        />
        <input
          v-model="termo"
          data-para-quem-busca
          data-foco
          type="search"
          autocomplete="off"
          :placeholder="t(`${M}.EXEMPLO`)"
          class="reset-base !mb-0 min-h-12 w-full rounded-2xl border border-n-weak bg-n-solid-1 pe-4 ps-12 text-base text-n-slate-12 shadow-sm outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8"
        />
      </span>
    </label>

    <p class="mb-0 text-sm font-medium text-n-slate-11">
      {{ curto ? t(`${M}.RECENTES`) : t(`${M}.ACHADOS`) }}
    </p>
    <p v-if="buscando && !achados.length" class="mb-0 text-sm text-n-slate-10">
      {{ t(`${M}.BUSCANDO`) }}
    </p>
    <p v-else-if="falhou" class="mb-0 text-sm text-n-ruby-11">
      {{ t(`${M}.FALHOU`) }}
    </p>
    <p
      v-else-if="!achados.length"
      data-para-quem-vazio
      class="mb-0 text-sm text-n-slate-11"
    >
      {{ t(`${M}.VAZIO`) }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-2 p-0">
      <li v-for="achado in achados" :key="achado.cardId">
        <button
          type="button"
          :data-para-quem="achado.cardId"
          :data-conectada="achado.conectada"
          :aria-disabled="!achado.conectada"
          class="flex min-h-16 w-full items-center gap-3 rounded-2xl border px-4 py-3 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            achado.conectada
              ? 'border-n-weak bg-n-solid-1 hover:border-n-blue-8 hover:shadow-sm'
              : 'cursor-not-allowed border-dashed border-n-slate-6 bg-n-alpha-1'
          "
          @click="clicar(achado)"
        >
          <span
            class="grid size-11 shrink-0 place-items-center rounded-full"
            :class="
              achado.conectada
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-10'
            "
            aria-hidden="true"
          >
            <span class="i-lucide-user-round size-5" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span
              class="truncate text-base font-semibold"
              :class="achado.conectada ? 'text-n-slate-12' : 'text-n-slate-11'"
            >
              {{ achado.nome }}
            </span>
            <span class="truncate text-sm text-n-slate-11">
              {{ linha(achado) }}
            </span>
          </span>
          <span
            v-if="achado.conectada"
            class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-9 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
  </section>
</template>

<script setup>
// Calendário Ouro — "Novo": o que marcar, em cartões grandes, uma frase cada.
// Lembrete sempre; reunião só com as reuniões ligadas; mensagem marcada só com
// uma caixa de WhatsApp conectada. A reunião vai pelo agendamento novo, que
// marca no negócio do cliente: antes, "Com quem é a reunião?" (busca pelo nome
// do cliente ou do negócio). Cliente sem negócio: uma frase e o lembrete. Sem
// página de agendamento nem agenda do Google/Microsoft, o cartão diz o que
// falta e leva às Páginas. Lembrete e mensagem abrem o fluxo que já existe.
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ContactAPI from 'dashboard/api/contacts';

const props = defineProps({
  opcoes: { type: Array, required: true },
  // Como a conta marca reunião (useJeitoDeMarcar): pagina, externa, falta, carregando.
  jeitoReuniao: { type: String, default: 'carregando' },
  podeCriarPagina: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher', 'criarPagina']);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.NOVO';
const MINIMO_PARA_BUSCAR = 2;
const POR_BUSCA = 8;
const ESPERA_DA_BUSCA = 300;

const OPCAO = {
  lembrete: {
    chave: 'LEMBRETE',
    icone: 'i-lucide-bell',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  reuniao: {
    chave: 'REUNIAO',
    icone: 'i-lucide-video',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  mensagem: {
    chave: 'MENSAGEM',
    icone: 'i-lucide-send',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
};

const dialogo = ref(null);
const passo = ref('o-que');
const termo = ref('');
const achados = ref([]);
const buscando = ref(false);
const falhou = ref(false);
const semNegocio = ref('');
const faltaPagina = computed(() => props.jeitoReuniao === 'falta');

const comecar = () => {
  passo.value = 'o-que';
  semNegocio.value = '';
  termo.value = '';
  achados.value = [];
  falhou.value = false;
};
const fechar = () => dialogo.value?.close();
const escolher = (opcao, extra = {}) => {
  fechar();
  emit('escolher', opcao, extra);
};
const clicarOpcao = opcao => {
  if (opcao !== 'reuniao') escolher(opcao);
  else if (!faltaPagina.value) passo.value = 'com-quem';
};
const criarPagina = () => {
  fechar();
  emit('criarPagina');
};

// Uma linha por cliente: com negócio, o negócio mais recente dele (a lista
// já vem do mais mexido para o menos); sem negócio, só o cliente.
const juntar = (cards, contatos) => {
  const porCliente = new Map();
  cards.forEach(card => {
    const chave = card.contact?.id ? `c${card.contact.id}` : `n${card.id}`;
    if (!porCliente.has(chave))
      porCliente.set(chave, {
        chave,
        nome: card.contact?.name || card.title,
        negocio: card.contact?.name ? card.title : '',
        cardId: card.id,
      });
  });
  contatos.forEach(contato => {
    const chave = `c${contato.id}`;
    if (!porCliente.has(chave))
      porCliente.set(chave, {
        chave,
        nome: contato.name,
        negocio: '',
        cardId: null,
      });
  });
  return [...porCliente.values()].slice(0, POR_BUSCA);
};
const escolherAchado = achado => {
  if (achado.cardId) escolher('reuniao', { cardId: achado.cardId });
  else {
    semNegocio.value = achado.nome;
    passo.value = 'sem-negocio';
  }
};

let pedido = 0;
let espera = null;
const buscar = async texto => {
  pedido += 1;
  const meu = pedido;
  falhou.value = false;
  if (texto.trim().length < MINIMO_PARA_BUSCAR) {
    achados.value = [];
    buscando.value = false;
    return;
  }
  buscando.value = true;
  try {
    const [cards, contatos] = await Promise.all([
      CrmKanbanAPI.getCards({ search: texto.trim(), per_page: POR_BUSCA }),
      ContactAPI.search(texto.trim()),
    ]);
    if (meu !== pedido) return;
    achados.value = juntar(
      cards.data?.payload || [],
      contatos.data?.payload || []
    );
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
  espera = setTimeout(() => buscar(texto), ESPERA_DA_BUSCA);
});
onBeforeUnmount(() => clearTimeout(espera));

const TITULOS = {
  'o-que': 'TITULO',
  'com-quem': 'COM_QUEM',
  'sem-negocio': 'SEM_NEGOCIO',
};
const curto = computed(() => termo.value.trim().length < MINIMO_PARA_BUSCAR);
const vazio = computed(
  () =>
    !curto.value && !buscando.value && !falhou.value && !achados.value.length
);

defineExpose({
  open: () => {
    comecar();
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog
    ref="dialogo"
    :title="t(`${N}.${TITULOS[passo]}`)"
    :description="t(`${N}.${TITULOS[passo]}_TEXTO`, { nome: semNegocio })"
    :show-confirm-button="false"
    width="md"
  >
    <div
      v-if="passo === 'o-que'"
      data-calendario-escolha
      class="flex flex-col gap-2"
    >
      <template v-for="opcao in opcoes" :key="opcao">
        <div
          v-if="opcao === 'reuniao' && faltaPagina"
          data-escolha="reuniao"
          data-escolha-falta
          class="flex w-full flex-col gap-3 rounded-2xl border border-dashed border-n-slate-7 bg-n-solid-1 p-4"
        >
          <span class="flex items-center gap-4">
            <span
              class="grid size-11 shrink-0 place-items-center rounded-xl"
              :class="OPCAO.reuniao.tom"
              aria-hidden="true"
            >
              <span class="size-5" :class="OPCAO.reuniao.icone" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block text-base font-semibold text-n-slate-12">
                {{ t(`${N}.REUNIAO`) }}
              </span>
              <span class="block text-sm text-n-slate-11">
                {{
                  podeCriarPagina
                    ? t(`${N}.FALTA_PAGINA`)
                    : t(`${N}.FALTA_PAGINA_SEM_PERMISSAO`)
                }}
              </span>
            </span>
          </span>
          <button
            v-if="podeCriarPagina"
            type="button"
            data-criar-pagina
            class="min-h-11 self-start rounded-xl bg-n-blue-9 px-4 text-sm font-semibold text-white hover:bg-n-blue-10"
            @click="criarPagina"
          >
            {{ t(`${N}.CRIAR_PAGINA`) }}
          </button>
        </div>
        <button
          v-else
          type="button"
          :data-escolha="opcao"
          class="flex min-h-16 w-full items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-start shadow-sm transition hover:border-n-blue-8 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="clicarOpcao(opcao)"
        >
          <span
            class="grid size-11 shrink-0 place-items-center rounded-xl"
            :class="OPCAO[opcao].tom"
            aria-hidden="true"
          >
            <span class="size-5" :class="OPCAO[opcao].icone" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block text-base font-semibold text-n-slate-12">
              {{ t(`${N}.${OPCAO[opcao].chave}`) }}
            </span>
            <span class="block text-sm text-n-slate-11">
              {{ t(`${N}.${OPCAO[opcao].chave}_TEXTO`) }}
            </span>
          </span>
          <span
            class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-9 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </template>
    </div>

    <div
      v-else-if="passo === 'com-quem'"
      data-calendario-com-quem
      class="flex flex-col gap-3"
    >
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${N}.BUSCA_ROTULO`) }}
        </span>
        <input
          v-model="termo"
          data-com-quem-busca
          type="search"
          autocomplete="off"
          :placeholder="t(`${N}.BUSCA_EXEMPLO`)"
          class="min-h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 text-base text-n-slate-12 outline-none focus:border-n-blue-8"
        />
      </label>
      <p v-if="curto" class="mb-0 text-sm text-n-slate-10">
        {{ t(`${N}.BUSCA_DICA`) }}
      </p>
      <p v-else-if="buscando" class="mb-0 text-sm text-n-slate-10">
        {{ t(`${N}.BUSCANDO`) }}
      </p>
      <p v-else-if="falhou" class="mb-0 text-sm text-n-ruby-11">
        {{ t(`${N}.BUSCA_FALHOU`) }}
      </p>
      <p v-else-if="vazio" class="mb-0 text-sm text-n-slate-11">
        {{ t(`${N}.BUSCA_VAZIA`) }}
      </p>
      <ul v-else class="m-0 flex list-none flex-col gap-2 p-0">
        <li v-for="achado in achados" :key="achado.chave">
          <button
            type="button"
            :data-com-quem="achado.chave"
            class="flex min-h-14 w-full items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-2 text-start transition hover:border-n-blue-8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="escolherAchado(achado)"
          >
            <span
              class="grid size-10 shrink-0 place-items-center rounded-full bg-n-iris-3 text-n-iris-11"
              aria-hidden="true"
            >
              <span class="i-lucide-user-round size-5" />
            </span>
            <span class="min-w-0 flex-1">
              <span
                class="block truncate text-base font-semibold text-n-slate-12"
              >
                {{ achado.nome }}
              </span>
              <span class="block truncate text-sm text-n-slate-11">
                {{ achado.negocio || t(`${N}.SEM_NEGOCIO_CURTO`) }}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </div>

    <div v-else data-calendario-sem-negocio class="flex flex-col gap-3">
      <button
        type="button"
        data-sem-negocio-lembrete
        class="min-h-11 rounded-xl bg-n-blue-9 px-4 text-sm font-semibold text-white hover:bg-n-blue-10"
        @click="escolher('lembrete')"
      >
        {{ t(`${N}.MARCAR_LEMBRETE`) }}
      </button>
    </div>

    <template #footer>
      <div class="flex w-full gap-2">
        <button
          v-if="passo !== 'o-que'"
          type="button"
          data-com-quem-voltar
          class="min-h-11 flex-1 rounded-xl bg-n-alpha-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-3"
          @click="passo === 'sem-negocio' ? (passo = 'com-quem') : comecar()"
        >
          {{ t(`${N}.VOLTAR`) }}
        </button>
        <button
          type="button"
          data-escolha-cancelar
          class="min-h-11 flex-1 rounded-xl bg-n-alpha-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-3"
          @click="fechar"
        >
          {{ t(`${N}.CANCELAR`) }}
        </button>
      </div>
    </template>
  </Dialog>
</template>

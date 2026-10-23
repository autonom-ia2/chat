<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';
import PainelLateral from './PainelLateral.vue';
import ArquivadoLinha from './ArquivadoLinha.vue';
import ConflitosDoLote from './ConflitosDoLote.vue';
import { useFormato } from '../card/useFormato';
import { motivoDoErro } from './motivoDoErro';
import { avisar } from './useAvisoCrm';
import { outcomeGroup } from '../../helpers/cardOutcome';

// Arquivados (#2095): os cards que saíram do quadro do funil, com quem arquivou, Restaurar (um ou vários) e
// "Procurar em todos os funis". Quem não tem "Arquivar cards" vê só para ler, com a frase de quem pedir.
// Restaurar um card passa pela página (`restaurar`), que cuida do cliente que já voltou e do aviso; restaurar
// vários é daqui, tudo ou nada no servidor, e os pulados aparecem no fim (ConflitosDoLote).
const props = defineProps({
  show: { type: Boolean, default: false },
  funil: { type: Object, default: null },
  funis: { type: Array, default: () => [] },
  podeArquivar: { type: Boolean, default: false },
  // async (linha) => { restaurado: boolean, erro?: string }
  restaurar: { type: Function, required: true },
});
const emit = defineEmits(['close', 'abrirCard', 'verFunisArquivados', 'mudou']);

const POR_PAGINA = 25;
const { t, locale } = useI18n();
const formato = useFormato({ t, locale });

const busca = ref('');
const todos = ref(false);
const linhas = ref([]);
const total = ref(0);
const carregando = ref(false);
const erroCarga = ref('');
const selecionados = ref([]);
const ocupados = ref({});
const erros = ref({});
const loteOcupado = ref(false);
const loteErro = ref('');
const pulados = ref([]);
const forcando = ref({});
const errosForcar = ref({});
const forcandoTodos = ref(false);
let pedido = 0;

const funilDe = linha => props.funis.find(f => f.id === linha.pipeline?.id);
const selecionavel = linha =>
  props.podeArquivar &&
  linha.status === 'archived' &&
  linha.pipeline?.status !== 'archived' &&
  linha.can_restore !== false;
const selecionaveis = computed(() => linhas.value.filter(selecionavel));
const temMais = computed(() => linhas.value.length < total.value);
const termo = computed(() => busca.value.trim());

const subtitulo = computed(() => {
  const cards = t('CRM_ARQUIVADOS.CARDS', { count: total.value }, total.value);
  if (todos.value) return t('CRM_ARQUIVADOS.SUB_TODOS', { cards });
  return t('CRM_ARQUIVADOS.SUB_FUNIL', {
    funil: props.funil?.name || '',
    cards,
  });
});

const carregar = async (proxima = 1) => {
  pedido += 1;
  const este = pedido;
  carregando.value = true;
  erroCarga.value = '';
  try {
    const { data } = await CrmArquivadosAPI.listar({
      pipeline_id: todos.value ? undefined : props.funil?.id,
      search: termo.value || undefined,
      page: proxima,
      per_page: POR_PAGINA,
    });
    if (este !== pedido) return;
    const vistas = new Set(linhas.value.map(linha => linha.id));
    linhas.value =
      proxima === 1
        ? data.payload
        : [...linhas.value, ...data.payload.filter(l => !vistas.has(l.id))];
    total.value = data.meta?.count ?? linhas.value.length;
  } catch (error) {
    if (este === pedido)
      erroCarga.value = t('CRM_ARQUIVADOS.ERRO_CARREGAR', {
        motivo: motivoDoErro(t, error),
      });
  } finally {
    if (este === pedido) carregando.value = false;
  }
};

// "Ver mais" pela quantidade já na tela, não pelo número da página: depois de restaurar k cards, a lista do servidor
// andou k posições, e a página seguinte pularia k arquivados. Pede a página onde a lista parou e tira os repetidos.
const carregarMais = () =>
  carregar(Math.floor(linhas.value.length / POR_PAGINA) + 1);

const recomecar = () => {
  selecionados.value = [];
  pulados.value = [];
  loteErro.value = '';
  erros.value = {};
  carregar(1);
};
const buscarDepois = useDebounceFn(recomecar, 300);

watch(
  () => [props.show, props.funil?.id],
  ([aberto]) => {
    if (!aberto) return;
    busca.value = '';
    todos.value = false;
    linhas.value = [];
    total.value = 0;
    recomecar();
  },
  { immediate: true }
);
watch(busca, () => {
  if (props.show) buscarDepois();
});

const alternarTodos = () => {
  todos.value = !todos.value;
  recomecar();
};
const limparBusca = () => {
  busca.value = '';
  recomecar();
};

const tirar = ids => {
  linhas.value = linhas.value.filter(linha => !ids.includes(linha.id));
  total.value = Math.max(0, total.value - ids.length);
  selecionados.value = selecionados.value.filter(id => !ids.includes(id));
};

const restaurarUm = async linha => {
  ocupados.value = { ...ocupados.value, [linha.id]: true };
  erros.value = { ...erros.value, [linha.id]: '' };
  const resultado = await props.restaurar(linha);
  ocupados.value = { ...ocupados.value, [linha.id]: false };
  if (resultado?.erro)
    erros.value = { ...erros.value, [linha.id]: resultado.erro };
  if (resultado?.restaurado) {
    tirar([linha.id]);
    emit('mudou');
  }
};

// ——— Vários ———
const marcado = id => selecionados.value.includes(id);
const selecionar = id => {
  selecionados.value = marcado(id)
    ? selecionados.value.filter(item => item !== id)
    : [...selecionados.value, id];
  loteErro.value = '';
};
const estadoTodos = computed(() => {
  if (!selecionados.value.length) return 'nenhum';
  return selecionaveis.value.every(linha => marcado(linha.id))
    ? 'todos'
    : 'alguns';
});
const selecionarTodos = () => {
  selecionados.value =
    estadoTodos.value === 'todos'
      ? []
      : selecionaveis.value.map(linha => linha.id);
  loteErro.value = '';
};

const comArquivado = item => {
  const linha = linhas.value.find(l => l.id === item.id);
  return {
    ...item,
    arquivado: linha && {
      title: linha.title,
      stage_name: linha.stage?.name || '',
    },
  };
};

const CONFLITO = 'crm.card_restore_conflict';

// Nenhum voltou e todos os pulados são do cliente que já voltou: uma frase só, sem "0 cards restaurados".
const avisoDoLote = (restaurados, puladosAgora) => {
  const conflitos = puladosAgora.filter(item => item.error === CONFLITO).length;
  if (!restaurados.length && conflitos && conflitos === puladosAgora.length)
    return t(
      'CRM_ARQUIVADOS.LOTE.NENHUM_VOLTOU_CONFLITOS',
      { count: conflitos },
      conflitos
    );
  const fechados = linhas.value.filter(
    linha => restaurados.includes(linha.id) && outcomeGroup(linha.desfecho)
  ).length;
  const partes = [
    t(
      'CRM_ARQUIVADOS.LOTE.RESTAURADOS',
      { count: restaurados.length },
      restaurados.length
    ),
  ];
  if (fechados)
    partes.push(
      t('CRM_ARQUIVADOS.LOTE.FECHADOS', { count: fechados }, fechados)
    );
  if (puladosAgora.length)
    partes.push(
      t(
        'CRM_ARQUIVADOS.LOTE.NAO_VOLTARAM',
        { count: puladosAgora.length },
        puladosAgora.length
      )
    );
  return partes.join(' ');
};

const restaurarSelecionados = async () => {
  const ids = [...selecionados.value];
  if (!ids.length) return;
  loteOcupado.value = true;
  loteErro.value = '';
  try {
    const { data } = await CrmArquivadosAPI.restaurarVarios(ids);
    const { restored = [], skipped = [] } = data.payload || {};
    pulados.value = skipped.map(comArquivado);
    avisar(avisoDoLote(restored, skipped));
    tirar(restored);
    selecionados.value = [];
    if (restored.length) emit('mudou');
  } catch (error) {
    loteErro.value = t('CRM_ARQUIVADOS.LOTE.ERRO', {
      motivo: motivoDoErro(t, error),
    });
  } finally {
    loteOcupado.value = false;
  }
};

const tirarPulados = ids => {
  pulados.value = pulados.value.filter(item => !ids.includes(item.id));
};

const forcar = async id => {
  forcando.value = { ...forcando.value, [id]: true };
  errosForcar.value = { ...errosForcar.value, [id]: '' };
  try {
    await CrmArquivadosAPI.restaurar(id, { force: true });
    tirarPulados([id]);
    tirar([id]);
    avisar(t('CRM_ARQUIVADOS.LOTE.RESTAURADOS', { count: 1 }, 1));
    emit('mudou');
  } catch (error) {
    errosForcar.value = {
      ...errosForcar.value,
      [id]: t('CRM_ARQUIVADOS.ERRO_RESTAURAR', {
        motivo: motivoDoErro(t, error),
      }),
    };
  } finally {
    forcando.value = { ...forcando.value, [id]: false };
  }
};

const forcarTodos = async ids => {
  forcandoTodos.value = true;
  loteErro.value = '';
  try {
    const { data } = await CrmArquivadosAPI.restaurarVarios(ids, {
      force: true,
    });
    const { restored = [], skipped = [] } = data.payload || {};
    tirarPulados(restored);
    tirar(restored);
    pulados.value = [
      ...pulados.value.filter(item => !ids.includes(item.id)),
      ...skipped.map(comArquivado),
    ];
    avisar(avisoDoLote(restored, skipped));
    if (restored.length) emit('mudou');
  } catch (error) {
    loteErro.value = t('CRM_ARQUIVADOS.LOTE.ERRO', {
      motivo: motivoDoErro(t, error),
    });
  } finally {
    forcandoTodos.value = false;
  }
};

defineExpose({ recarregar: recomecar });
</script>

<template>
  <PainelLateral
    :show="show"
    :titulo="t('CRM_ARQUIVADOS.TITULO')"
    :subtitulo="carregando && !linhas.length ? '' : subtitulo"
    data-painel-arquivados
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <p
        v-if="!podeArquivar"
        data-so-leitura
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
      >
        <span class="i-lucide-lock mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t('CRM_ARQUIVADOS.SEM_PERMISSAO') }}
      </p>

      <div class="flex flex-wrap items-center gap-3">
        <div class="min-w-0 flex-1 basis-56">
          <Input
            id="crm-arquivados-busca"
            v-model="busca"
            custom-input-class="!min-h-11 !rounded-lg"
            :placeholder="t('CRM_ARQUIVADOS.BUSCA')"
            :aria-label="t('CRM_ARQUIVADOS.BUSCA_ROTULO')"
          />
        </div>
        <button
          type="button"
          role="switch"
          data-arquivados-todos
          :aria-checked="todos ? 'true' : 'false'"
          class="inline-flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="alternarTodos"
        >
          <span
            aria-hidden="true"
            class="relative h-5 w-9 shrink-0 rounded-full transition-colors"
            :class="todos ? 'bg-n-brand' : 'bg-n-slate-6'"
          >
            <span
              class="absolute top-0.5 size-4 rounded-full bg-n-background shadow transition-all ltr:left-0.5 rtl:right-0.5"
              :class="todos ? 'ltr:translate-x-4 rtl:-translate-x-4' : ''"
            />
          </span>
          {{ t('CRM_ARQUIVADOS.TODOS_OS_FUNIS') }}
        </button>
      </div>

      <div aria-live="polite">
        <div
          v-if="carregando && !linhas.length"
          aria-busy="true"
          class="flex flex-col gap-3"
        >
          <span class="sr-only">{{ t('CRM_ARQUIVADOS.CARREGANDO') }}</span>
          <div
            v-for="n in 3"
            :key="n"
            class="h-16 animate-pulse rounded-xl bg-n-alpha-2"
          />
        </div>

        <div
          v-else-if="erroCarga"
          role="alert"
          class="flex flex-col items-start gap-2 rounded-xl bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
        >
          <p class="mb-0">{{ erroCarga }}</p>
          <Button
            :label="t('CRM_ARQUIVADOS.TENTAR_DE_NOVO')"
            slate
            faded
            class="!min-h-11"
            @click="carregar(1)"
          />
        </div>

        <div
          v-else-if="!linhas.length && termo"
          data-arquivados-busca-vazia
          class="flex flex-col items-center gap-3 py-8 text-center"
        >
          <p class="mb-0 text-sm text-n-slate-11">
            {{
              todos
                ? t('CRM_ARQUIVADOS.NADA_ACHADO_TODOS', { termo })
                : t('CRM_ARQUIVADOS.NADA_ACHADO', { termo })
            }}
          </p>
          <div class="flex flex-wrap justify-center gap-2">
            <Button
              :label="t('CRM_ARQUIVADOS.LIMPAR_BUSCA')"
              slate
              faded
              class="!min-h-11"
              @click="limparBusca"
            />
            <Button
              v-if="!todos"
              :label="t('CRM_ARQUIVADOS.TODOS_OS_FUNIS')"
              icon="i-lucide-search"
              slate
              outline
              class="!min-h-11"
              @click="alternarTodos"
            />
          </div>
        </div>

        <div
          v-else-if="!linhas.length"
          data-arquivados-vazio
          class="flex flex-col items-center gap-3 py-8 text-center"
        >
          <span
            class="i-lucide-archive size-8 text-n-slate-9"
            aria-hidden="true"
          />
          <p class="mb-0 text-sm text-n-slate-11">
            {{
              todos
                ? t('CRM_ARQUIVADOS.VAZIO_TODOS')
                : t('CRM_ARQUIVADOS.VAZIO')
            }}
          </p>
          <div class="flex flex-wrap justify-center gap-2">
            <Button
              :label="t('CRM_ARQUIVADOS.VOLTAR_AO_QUADRO')"
              slate
              faded
              class="!min-h-11"
              @click="emit('close')"
            />
            <Button
              v-if="!todos"
              :label="t('CRM_ARQUIVADOS.TODOS_OS_FUNIS')"
              icon="i-lucide-search"
              slate
              outline
              class="!min-h-11"
              @click="alternarTodos"
            />
          </div>
        </div>

        <template v-else>
          <ConflitosDoLote
            v-if="pulados.length"
            class="mb-3"
            :pulados="pulados"
            :ocupados="forcando"
            :erros="errosForcar"
            :ocupado-todos="forcandoTodos"
            @forcar="forcar"
            @forcar-todos="forcarTodos"
            @abrir-card="id => emit('abrirCard', { id })"
            @fechar="pulados = []"
          />

          <div
            v-if="selecionaveis.length"
            data-arquivados-selecao
            class="flex flex-wrap items-center gap-2 border-b border-n-weak pb-2"
          >
            <label
              class="inline-flex min-h-11 cursor-pointer items-center gap-3 rounded-lg px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
            >
              <Checkbox
                :model-value="estadoTodos === 'todos'"
                :indeterminate="estadoTodos === 'alguns'"
                data-arquivados-selecionar-todos
                @change="selecionarTodos"
              />
              {{
                selecionados.length
                  ? t(
                      'CRM_ARQUIVADOS.SELECIONADOS',
                      { count: selecionados.length },
                      selecionados.length
                    )
                  : t('CRM_ARQUIVADOS.SELECIONAR_VARIOS')
              }}
            </label>
            <div
              v-if="selecionados.length"
              class="ms-auto flex flex-wrap gap-2"
            >
              <Button
                data-arquivados-restaurar-varios
                :label="
                  t('CRM_ARQUIVADOS.RESTAURAR_N', {
                    count: selecionados.length,
                  })
                "
                icon="i-lucide-rotate-ccw"
                slate
                faded
                class="!min-h-11"
                :is-loading="loteOcupado"
                :disabled="loteOcupado"
                @click="restaurarSelecionados"
              />
              <slot
                name="acoesDoLote"
                :ids="selecionados"
                :linhas="linhas.filter(linha => marcado(linha.id))"
                :ocupado="loteOcupado"
              />
            </div>
            <p
              v-if="loteErro"
              role="alert"
              class="mb-0 basis-full rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
            >
              {{ loteErro }}
            </p>
          </div>

          <ul class="m-0 list-none p-0" :aria-busy="carregando">
            <ArquivadoLinha
              v-for="linha in linhas"
              :key="linha.id"
              :linha="linha"
              :funil="funilDe(linha)"
              :formato="formato"
              :pode-arquivar="podeArquivar"
              :mostra-funil="todos"
              :selecionavel="selecionavel(linha)"
              :selecionado="marcado(linha.id)"
              :ocupado="Boolean(ocupados[linha.id])"
              :erro="erros[linha.id] || ''"
              @abrir="emit('abrirCard', linha)"
              @restaurar="restaurarUm"
              @selecionar="selecionar"
              @ver-funis-arquivados="emit('verFunisArquivados')"
            >
              <template #acoes="escopo">
                <slot name="acoesDaLinha" v-bind="escopo" />
              </template>
            </ArquivadoLinha>
          </ul>
          <div v-if="temMais" class="flex justify-center pt-3">
            <Button
              :label="t('CRM_ARQUIVADOS.VER_MAIS')"
              slate
              faded
              class="!min-h-11"
              :is-loading="carregando"
              :disabled="carregando"
              @click="carregarMais"
            />
          </div>
        </template>
      </div>
    </div>
  </PainelLateral>
</template>

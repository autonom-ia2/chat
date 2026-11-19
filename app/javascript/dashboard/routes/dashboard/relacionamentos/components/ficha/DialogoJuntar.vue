<script setup>
import { computed, nextTick, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { SEPARADOR } from '../comum/ponto';
import CampoDeBusca from '../lista/CampoDeBusca.vue';
import { formatarTelefone } from '../../lista/telefone';

// #3071 — "Juntar com outra pessoa", em dois passos no mesmo diálogo:
//  1. a busca da outra ficha (nome, telefone ou e-mail, pela busca da lista
//     nova) e a escolha numa lista de botões de rádio. Abre já procurando pelo
//     nome da pessoa (a outra ficha costuma ter o mesmo nome) e diz qual ficha
//     fica. Uma busca nova que não traz a escolhida desfaz a escolha.
//     "Continuar" está sempre ligado: sem escolha, diz o que falta e leva o
//     foco à busca;
//  2. a confirmação, com as duas fichas (nome, telefone e e-mail), qual fica (a
//     que está aberta) e qual deixa de existir, e o que acontece: tudo passa
//     para a que fica; o nome, o telefone e o e-mail dela continuam. Quando o
//     telefone ou o e-mail de quem sai é outro, uma linha avisa que ele se perde
//     (ContactMergeAction: o que a ficha que fica já tem vale). "Voltar" leva de
//     novo à busca, com a escolha guardada.
// "Juntar fichas" emite `juntar` com a outra pessoa; quem usa fecha (`fechar`)
// quando deu certo, ou passa a frase em `alerta` e o diálogo fica aberto.
// Tocar fora não fecha (Esc e Cancelar fecham).
const props = defineProps({
  pessoa: { type: Object, required: true },
  // (termo) => Promise<[pessoa]>: as outras pessoas que batem com o termo.
  buscar: { type: Function, required: true },
  juntando: { type: Boolean, default: false },
  alerta: { type: String, default: '' },
  // A conta tem a carteira: os seguros também passam.
  comSeguros: { type: Boolean, default: false },
});
const emit = defineEmits(['juntar']);

const MINIMO_PARA_BUSCAR = 2;
const BUSCA = 'busca';
const CONFIRMAR = 'confirmar';
const JT = 'RELACIONAMENTOS_FICHA.JUNTAR';

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const raiz = useTemplateRef('raiz');
const idDoGrupo = useId();
const idDoAviso = useId();

const etapa = ref(BUSCA);
const termo = ref('');
const resultados = ref([]);
const procurando = ref(false);
const falhouBusca = ref(false);
const escolhida = ref(null);
const faltaEscolher = ref(false);
let pedido = 0;

const fica = computed(() => props.pessoa.name);
const sai = computed(() => escolhida.value?.name ?? '');
const termoCurto = computed(
  () => termo.value.trim().length < MINIMO_PARA_BUSCAR
);

const contatoDe = pessoa =>
  [
    pessoa.phone_number ? formatarTelefone(pessoa.phone_number) : '',
    pessoa.email,
  ]
    .filter(Boolean)
    .join(SEPARADOR) || t(`${JT}.SEM_CONTATO`);

const mesmoEmail = (um, outro) =>
  String(um).toLowerCase() === String(outro).toLowerCase();

// O que a ficha que fica já tem vale: o telefone e o e-mail de quem sai só
// passam quando ela não tem. Sendo outros, a pessoa precisa saber que somem.
const perdas = computed(() => {
  const saindo = escolhida.value;
  if (!saindo) return [];
  const ficando = props.pessoa;
  return [
    saindo.phone_number &&
      ficando.phone_number &&
      saindo.phone_number !== ficando.phone_number && {
        marca: 'telefone',
        texto: t(`${JT}.PERDE_TELEFONE`, {
          telefone: formatarTelefone(saindo.phone_number),
          sai: saindo.name,
        }),
      },
    saindo.email &&
      ficando.email &&
      !mesmoEmail(saindo.email, ficando.email) && {
        marca: 'email',
        texto: t(`${JT}.PERDE_EMAIL`, {
          email: saindo.email,
          sai: saindo.name,
        }),
      },
  ].filter(Boolean);
});

const procurar = async () => {
  pedido += 1;
  const meu = pedido;
  falhouBusca.value = false;
  if (termoCurto.value) {
    resultados.value = [];
    procurando.value = false;
    return;
  }
  procurando.value = true;
  try {
    const achadas = await props.buscar(termo.value.trim());
    if (meu !== pedido) return;
    resultados.value = achadas;
    if (!achadas.some(item => item.id === escolhida.value?.id)) {
      escolhida.value = null;
    }
  } catch {
    if (meu === pedido) {
      resultados.value = [];
      falhouBusca.value = true;
    }
  } finally {
    if (meu === pedido) procurando.value = false;
  }
};

const aoBuscar = valor => {
  termo.value = valor;
  procurar();
};

const escolher = pessoa => {
  escolhida.value = pessoa;
  faltaEscolher.value = false;
};

const focar = seletor => raiz.value?.querySelector(seletor)?.focus();

const avancar = async () => {
  if (!escolhida.value) {
    faltaEscolher.value = true;
    focar('[data-relacionamentos="busca"]');
    return;
  }
  etapa.value = CONFIRMAR;
  await nextTick();
  focar('[data-relacionamentos="titulo-da-confirmacao"]');
};

const voltar = async () => {
  etapa.value = BUSCA;
  await nextTick();
  focar('[data-relacionamentos="busca"]');
};

const aoConfirmar = () => {
  if (etapa.value === BUSCA) {
    avancar();
    return;
  }
  if (!props.juntando) emit('juntar', escolhida.value);
};

const abrir = () => {
  etapa.value = BUSCA;
  termo.value = props.pessoa.name ?? '';
  resultados.value = [];
  falhouBusca.value = false;
  escolhida.value = null;
  faltaEscolher.value = false;
  dialogo.value?.open();
  procurar();
};

defineExpose({ abrir, fechar: () => dialogo.value?.close() });
</script>

<template>
  <Dialog
    ref="dialogo"
    :type="etapa === CONFIRMAR ? 'alert' : 'edit'"
    width="md"
    :close-on-outside-click="false"
    @confirm="aoConfirmar"
  >
    <div ref="raiz" data-relacionamentos="dialogo-juntar">
      <div v-if="etapa === BUSCA" class="flex flex-col gap-4">
        <TituloDoDialogo
          :titulo="t(`${JT}.TITULO`, { nome: fica })"
          :aviso="t(`${JT}.AVISO`, { nome: fica })"
        />
        <CampoDeBusca
          :model-value="termo"
          :placeholder="t(`${JT}.PLACEHOLDER`)"
          :rotulo="t(`${JT}.BUSCA`)"
          @update:model-value="aoBuscar"
        />
        <div role="status" aria-live="polite" class="text-base text-n-slate-11">
          <p v-if="procurando" class="m-0">{{ t(`${JT}.PROCURANDO`) }}</p>
          <div
            v-else-if="falhouBusca"
            class="flex flex-wrap items-center gap-3"
          >
            <p class="m-0 text-n-ruby-11">{{ t(`${JT}.ERRO_BUSCA`) }}</p>
            <Button
              slate
              faded
              type="button"
              class="!h-11"
              :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
              @click="procurar"
            />
          </div>
          <p v-else-if="termoCurto" class="m-0">{{ t(`${JT}.DIGITE`) }}</p>
          <p
            v-else-if="!resultados.length"
            data-relacionamentos="ninguem"
            class="m-0"
          >
            {{ t(`${JT}.NINGUEM`, { termo: termo.trim() }) }}
          </p>
        </div>
        <fieldset
          v-if="resultados.length && !procurando"
          class="min-w-0 p-0 m-0 border-0"
          :aria-describedby="idDoAviso"
        >
          <legend class="sr-only">{{ t(`${JT}.RESULTADOS`) }}</legend>
          <ul
            data-relacionamentos="resultados-do-juntar"
            class="flex flex-col gap-1 p-1 m-0 overflow-y-auto list-none border rounded-xl max-h-72 border-n-weak"
          >
            <li v-for="item in resultados" :key="item.id">
              <label
                class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer min-h-14 hover:bg-n-alpha-1 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
                :class="{
                  'bg-n-blue-3 ring-1 ring-inset ring-n-blue-8':
                    escolhida?.id === item.id,
                }"
              >
                <input
                  type="radio"
                  class="sr-only"
                  :name="idDoGrupo"
                  :value="item.id"
                  :checked="escolhida?.id === item.id"
                  :data-pessoa="item.id"
                  @change="escolher(item)"
                />
                <Avatar
                  :name="item.name"
                  :src="item.thumbnail"
                  :size="36"
                  rounded-full
                />
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-base font-medium truncate text-n-slate-12">
                    {{ item.name }}
                  </span>
                  <span class="text-sm truncate text-n-slate-11">{{
                    contatoDe(item)
                  }}</span>
                </span>
                <span
                  v-if="escolhida?.id === item.id"
                  class="i-lucide-check-circle-2 size-5 shrink-0 text-n-blue-11"
                  aria-hidden="true"
                />
              </label>
            </li>
          </ul>
        </fieldset>
        <p
          :id="idDoAviso"
          role="alert"
          data-relacionamentos="juntar-falta"
          class="m-0 text-sm text-n-ruby-11"
          :class="{ hidden: !faltaEscolher }"
        >
          {{ faltaEscolher ? t(`${JT}.ESCOLHA`) : '' }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-4">
        <h3
          data-relacionamentos="titulo-da-confirmacao"
          tabindex="-1"
          class="m-0 text-lg font-semibold leading-7 text-n-slate-12 focus:outline-none"
        >
          {{ t(`${JT}.CONFIRMA_TITULO`) }}
        </h3>
        <div class="grid grid-cols-1 gap-3">
          <div
            v-for="lado in [
              { marca: 'fica', pessoa, rotulo: 'FICA', tom: 'teal' },
              { marca: 'sai', pessoa: escolhida, rotulo: 'SAI', tom: 'ruby' },
            ]"
            :key="lado.marca"
            :data-relacionamentos="`juntar-${lado.marca}`"
            class="flex items-center min-w-0 gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <Avatar
              :name="lado.pessoa.name"
              :src="lado.pessoa.thumbnail"
              :size="40"
              rounded-full
            />
            <span class="flex flex-col min-w-0">
              <span
                class="text-sm font-semibold"
                :class="
                  lado.tom === 'teal' ? 'text-n-teal-11' : 'text-n-ruby-11'
                "
              >
                {{ t(`${JT}.${lado.rotulo}`) }}
              </span>
              <span class="text-base font-medium break-words text-n-slate-12">
                {{ lado.pessoa.name }}
              </span>
              <span
                v-if="lado.pessoa.phone_number"
                :data-juntar-telefone="lado.marca"
                class="text-sm tabular-nums text-n-slate-11"
              >
                {{ formatarTelefone(lado.pessoa.phone_number) }}
              </span>
              <span
                v-if="lado.pessoa.email"
                :data-juntar-email="lado.marca"
                class="text-sm break-all text-n-slate-11"
              >
                {{ lado.pessoa.email }}
              </span>
            </span>
          </div>
        </div>
        <ul class="flex flex-col gap-3 p-0 m-0 list-none text-base">
          <li class="flex items-start gap-3 text-n-slate-12">
            <span
              class="mt-1 i-lucide-combine size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{
              comSeguros
                ? t(`${JT}.O_QUE_PASSA_COM_SEGUROS`, { sai, fica })
                : t(`${JT}.O_QUE_PASSA`, { sai, fica })
            }}
          </li>
          <li class="flex items-start gap-3 text-n-slate-12">
            <span
              class="mt-1 i-lucide-user-check size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{ t(`${JT}.O_QUE_FICA`, { sai, fica }) }}
          </li>
          <li
            v-for="perda in perdas"
            :key="perda.marca"
            :data-juntar-perde="perda.marca"
            class="flex items-start gap-3 text-n-amber-11"
          >
            <span
              class="mt-1 i-lucide-circle-alert size-4 shrink-0"
              aria-hidden="true"
            />
            {{ perda.texto }}
          </li>
          <li class="flex items-start gap-3 font-medium text-n-ruby-11">
            <span
              class="mt-1 i-lucide-triangle-alert size-4 shrink-0"
              aria-hidden="true"
            />
            {{ t(`${JT}.NAO_VOLTA`, { sai }) }}
          </li>
        </ul>
        <p
          v-if="alerta"
          role="alert"
          data-relacionamentos="alerta-do-juntar"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ alerta }}
        </p>
      </div>
    </div>
    <template #footer>
      <div class="flex flex-col-reverse w-full gap-3 sm:flex-row">
        <Button
          slate
          faded
          size="lg"
          type="button"
          class="w-full"
          data-relacionamentos="juntar-voltar"
          :label="
            etapa === CONFIRMAR
              ? t(`${JT}.VOLTAR`)
              : t('RELACIONAMENTOS.COMUM.CANCELAR')
          "
          @click="etapa === CONFIRMAR ? voltar() : dialogo?.close()"
        />
        <Button
          :color="etapa === CONFIRMAR ? 'ruby' : 'blue'"
          size="lg"
          type="submit"
          class="w-full"
          data-relacionamentos="juntar-confirmar"
          :label="
            etapa === CONFIRMAR ? t(`${JT}.CONFIRMAR`) : t(`${JT}.CONTINUAR`)
          "
          :is-loading="juntando"
          :disabled="juntando"
        />
      </div>
    </template>
  </Dialog>
</template>

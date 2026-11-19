<script setup>
import { computed, nextTick, onBeforeUnmount, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { normalizado } from '../../fonte/texto';

// #3075 — a empresa da pessoa, ligada à empresa cadastrada da conta (a chave
// `companies`), como o CompanySelector da ficha antiga:
//  - com empresa: o nome, e "Trocar" e "Tirar". A empresa nova (ainda sem
//    cadastro) e a ficha antiga que só tem o nome escrito dizem o que são;
//  - sem empresa (ou em "Trocar"): a busca pelo nome entre as empresas da conta
//    e a lista do que achou. Quando o nome escrito não está na lista, a última
//    opção é cadastrar uma empresa nova com ele: o cadastro acontece no
//    "Salvar" da gaveta (fonte/gravarPessoa.js), e "Cancelar" não deixa
//    empresa solta para trás.
// Nada é alterado aqui: cada escolha sobe por `mudar` como { id, nome, nova }.
const props = defineProps({
  // { id, nome, nova }: a do formulário agora.
  empresa: { type: Object, required: true },
  // O nome da empresa de quando a gaveta abriu ('' sem empresa).
  nomeInicial: { type: String, default: '' },
  // (termo) => Promise<[{ id, nome }]>.
  buscar: { type: Function, required: true },
});
const emit = defineEmits(['mudar']);

const ESPERA_AO_DIGITAR_MS = 300;

const { t } = useI18n();
const ea = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.GAVETA.EMPRESA_ESCOLHA.${chave}`, valores);
const id = useId();
const raiz = ref(null);

const trocando = ref(false);
const termo = ref('');
const achadas = ref([]);
const procurando = ref(false);
const falhou = ref(false);
let relogio = null;
let pedido = 0;

const temEmpresa = computed(() => Boolean(props.empresa.nome));
const procurandoAgora = computed(() => !temEmpresa.value || trocando.value);
const soNome = computed(
  () => temEmpresa.value && !props.empresa.id && !props.empresa.nova
);
const nomeDigitado = computed(() => termo.value.trim());
const podeCadastrar = computed(
  () =>
    nomeDigitado.value !== '' &&
    !procurando.value &&
    !achadas.value.some(
      item => normalizado(item.nome) === normalizado(nomeDigitado.value)
    )
);
const vaiSair = computed(
  () => !temEmpresa.value && props.nomeInicial !== '' && !trocando.value
);

const procurar = async () => {
  pedido += 1;
  const meu = pedido;
  falhou.value = false;
  if (!nomeDigitado.value) {
    achadas.value = [];
    procurando.value = false;
    return;
  }
  procurando.value = true;
  try {
    const lista = await props.buscar(nomeDigitado.value);
    if (meu === pedido) achadas.value = lista;
  } catch {
    if (meu === pedido) {
      achadas.value = [];
      falhou.value = true;
    }
  } finally {
    if (meu === pedido) procurando.value = false;
  }
};

const aoDigitar = evento => {
  termo.value = evento.target.value;
  clearTimeout(relogio);
  relogio = setTimeout(procurar, ESPERA_AO_DIGITAR_MS);
};
onBeforeUnmount(() => clearTimeout(relogio));

const focarBusca = async () => {
  await nextTick();
  raiz.value
    ?.querySelector('[data-relacionamentos="busca-da-empresa"]')
    ?.focus();
};

const focarTrocar = async () => {
  await nextTick();
  raiz.value?.querySelector('[data-relacionamentos="trocar-empresa"]')?.focus();
};

const trocar = () => {
  trocando.value = true;
  // Na ficha que só tem o nome, a busca já começa por ele.
  termo.value = soNome.value ? props.empresa.nome : '';
  achadas.value = [];
  procurar();
  focarBusca();
};

const escolher = escolhida => {
  trocando.value = false;
  termo.value = '';
  achadas.value = [];
  emit('mudar', escolhida);
  focarTrocar();
};

const cancelar = () => {
  trocando.value = false;
  termo.value = '';
  focarTrocar();
};

const tirar = () => {
  emit('mudar', { id: null, nome: '', nova: false });
  focarBusca();
};
</script>

<template>
  <div
    ref="raiz"
    data-relacionamentos="escolha-da-empresa"
    class="flex flex-col min-w-0"
  >
    <label
      v-if="procurandoAgora"
      :for="`${id}-busca`"
      class="mb-1.5 text-heading-3 text-n-slate-12"
    >
      {{ ea('ROTULO') }}
    </label>
    <p v-else class="m-0 mb-1.5 text-heading-3 text-n-slate-12">
      {{ ea('ROTULO') }}
    </p>

    <div
      v-if="!procurandoAgora"
      data-relacionamentos="empresa-escolhida"
      class="flex flex-col min-w-0 gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-2"
    >
      <div class="flex items-start min-w-0 gap-3">
        <span
          class="mt-1 i-lucide-building-2 size-5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <span class="text-base font-medium break-words text-n-slate-12">
            {{ empresa.nome }}
          </span>
          <span v-if="empresa.nova" class="text-sm text-n-slate-11">
            {{ ea('NOVA') }}
          </span>
          <span v-else-if="soNome" class="text-sm text-n-slate-11">
            {{ ea('SO_NOME') }}
          </span>
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          data-relacionamentos="trocar-empresa"
          slate
          faded
          type="button"
          class="!h-11"
          :label="ea(soNome ? 'LIGAR' : 'TROCAR')"
          @click="trocar"
        />
        <Button
          data-relacionamentos="tirar-empresa"
          slate
          ghost
          type="button"
          class="!h-11"
          :label="ea('TIRAR')"
          @click="tirar"
        />
      </div>
    </div>

    <template v-else>
      <div class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-5 text-n-slate-10 top-1/2 ltr:left-3 rtl:right-3"
          aria-hidden="true"
        />
        <input
          :id="`${id}-busca`"
          type="search"
          autocomplete="off"
          data-relacionamentos="busca-da-empresa"
          :value="termo"
          :placeholder="ea('PLACEHOLDER')"
          :aria-describedby="`${id}-estado`"
          class="block w-full h-11 !mb-0 text-sm border-0 rounded-lg reset-base outline outline-1 outline-offset-[-1px] outline-n-weak hover:outline-n-slate-6 bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand ltr:!pl-10 rtl:!pr-10 [&::-webkit-search-cancel-button]:hidden"
          @input="aoDigitar"
          @keydown.enter.prevent="procurar"
        />
      </div>
      <div
        :id="`${id}-estado`"
        role="status"
        aria-live="polite"
        class="mt-2 text-sm text-n-slate-11"
      >
        <p v-if="procurando" class="m-0">{{ ea('PROCURANDO') }}</p>
        <div v-else-if="falhou" class="flex flex-wrap items-center gap-2">
          <p class="m-0 text-n-ruby-11">{{ ea('ERRO') }}</p>
          <Button
            slate
            faded
            type="button"
            class="!h-11"
            :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
            @click="procurar"
          />
        </div>
        <p v-else-if="!nomeDigitado" class="m-0">
          {{
            vaiSair ? ea('VAI_SAIR', { empresa: nomeInicial }) : ea('DIGITE')
          }}
        </p>
        <p v-else-if="!achadas.length" class="m-0">
          {{ ea('NENHUMA', { termo: nomeDigitado }) }}
        </p>
      </div>
      <ul
        v-if="
          nomeDigitado &&
          !procurando &&
          !falhou &&
          (achadas.length || podeCadastrar)
        "
        data-relacionamentos="empresas-achadas"
        :aria-label="ea('ACHADAS')"
        class="flex flex-col gap-1 p-1 m-0 mt-2 overflow-y-auto list-none border rounded-xl max-h-72 border-n-weak"
      >
        <li v-for="item in achadas" :key="item.id">
          <button
            type="button"
            :data-empresa="item.id"
            class="flex items-center w-full gap-3 px-3 py-2 text-base bg-transparent border-0 rounded-lg text-start min-h-11 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="escolher({ id: item.id, nome: item.nome, nova: false })"
          >
            <span
              class="i-lucide-building-2 size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="min-w-0 break-words">{{ item.nome }}</span>
          </button>
        </li>
        <li v-if="podeCadastrar">
          <button
            type="button"
            data-relacionamentos="cadastrar-empresa"
            class="flex items-center w-full gap-3 px-3 py-2 text-base font-medium bg-transparent border-0 rounded-lg text-start min-h-11 text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="escolher({ id: null, nome: nomeDigitado, nova: true })"
          >
            <span class="i-lucide-plus size-4 shrink-0" aria-hidden="true" />
            <span class="min-w-0 break-words">
              {{ ea('CADASTRAR', { nome: nomeDigitado }) }}
            </span>
          </button>
        </li>
      </ul>
      <Button
        v-if="trocando"
        data-relacionamentos="cancelar-troca-de-empresa"
        slate
        ghost
        type="button"
        class="!h-11 mt-2 self-start"
        :label="ea('MANTER', { empresa: empresa.nome })"
        @click="cancelar"
      />
    </template>
  </div>
</template>

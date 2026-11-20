<script setup>
import { computed, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { SEPARADOR } from '../comum/ponto';
import CampoDeBusca from '../lista/CampoDeBusca.vue';
import { formatarTelefone } from '../../lista/telefone';

// #3078 — "Pôr pessoa" na ficha da empresa (a ficha antiga fazia na aba
// Pessoas): procurar quem ainda não está nesta empresa pelo nome, telefone ou
// e-mail e escolher numa lista de botões de rádio. Cada pessoa diz em que
// empresa está hoje; escolhida uma que está em outra, a linha de baixo avisa
// que ela sai de lá e entra nesta (uma pessoa fica numa empresa só). "Pôr na
// empresa" está sempre ligado: sem escolha, diz o que falta e leva o foco à
// busca. Emite `por` com a pessoa; quem usa fecha (`fechar`) quando deu certo,
// ou passa a frase em `alerta` e o diálogo fica aberto. Tocar fora não fecha.
const props = defineProps({
  empresa: { type: Object, required: true },
  // (termo) => Promise<[pessoa]>: quem bate com o termo e não está aqui.
  buscar: { type: Function, required: true },
  pondo: { type: Boolean, default: false },
  alerta: { type: String, default: '' },
});
const emit = defineEmits(['por']);

const MINIMO_PARA_BUSCAR = 2;
const PO = 'RELACIONAMENTOS_FICHA.EMPRESA.POR';

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const raiz = useTemplateRef('raiz');
const idDoGrupo = useId();
const idDoAviso = useId();

const termo = ref('');
const resultados = ref([]);
const procurando = ref(false);
const falhouBusca = ref(false);
const escolhida = ref(null);
const faltaEscolher = ref(false);
let pedido = 0;

const termoCurto = computed(
  () => termo.value.trim().length < MINIMO_PARA_BUSCAR
);

const contatoDe = pessoa =>
  [
    pessoa.phone_number ? formatarTelefone(pessoa.phone_number) : '',
    pessoa.email,
  ]
    .filter(Boolean)
    .join(SEPARADOR) || t(`${PO}.SEM_CONTATO`);

const ondeEsta = pessoa =>
  pessoa.empresa
    ? t(`${PO}.ESTA_EM`, { empresa: pessoa.empresa.nome })
    : t(`${PO}.SEM_EMPRESA`);

const mudaDeEmpresa = computed(() =>
  escolhida.value?.empresa
    ? t(`${PO}.MUDA`, {
        nome: escolhida.value.name,
        de: escolhida.value.empresa.nome,
        para: props.empresa.name,
      })
    : ''
);

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

const aoConfirmar = () => {
  if (props.pondo) return;
  if (!escolhida.value) {
    faltaEscolher.value = true;
    raiz.value?.querySelector('[data-relacionamentos="busca"]')?.focus();
    return;
  }
  emit('por', escolhida.value);
};

const abrir = () => {
  termo.value = '';
  resultados.value = [];
  falhouBusca.value = false;
  escolhida.value = null;
  faltaEscolher.value = false;
  dialogo.value?.open();
};

defineExpose({ abrir, fechar: () => dialogo.value?.close() });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :close-on-outside-click="false"
    @confirm="aoConfirmar"
  >
    <div
      ref="raiz"
      data-relacionamentos="dialogo-por-pessoa"
      class="flex flex-col gap-4"
    >
      <TituloDoDialogo
        :titulo="t(`${PO}.TITULO`, { empresa: empresa.name })"
        :aviso="t(`${PO}.AVISO`)"
      />
      <CampoDeBusca
        :model-value="termo"
        :placeholder="t(`${PO}.PLACEHOLDER`)"
        :rotulo="t(`${PO}.BUSCA`)"
        @update:model-value="aoBuscar"
      />
      <div role="status" aria-live="polite" class="text-base text-n-slate-11">
        <p v-if="procurando" class="m-0">{{ t(`${PO}.PROCURANDO`) }}</p>
        <div v-else-if="falhouBusca" class="flex flex-wrap items-center gap-3">
          <p class="m-0 text-n-ruby-11">{{ t(`${PO}.ERRO_BUSCA`) }}</p>
          <Button
            slate
            faded
            type="button"
            class="!h-11"
            :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
            @click="procurar"
          />
        </div>
        <p v-else-if="termoCurto" class="m-0">{{ t(`${PO}.DIGITE`) }}</p>
        <p
          v-else-if="!resultados.length"
          data-relacionamentos="ninguem"
          class="m-0"
        >
          {{ t(`${PO}.NINGUEM`, { termo: termo.trim() }) }}
        </p>
      </div>
      <fieldset
        v-if="resultados.length && !procurando"
        class="min-w-0 p-0 m-0 border-0"
        :aria-describedby="idDoAviso"
      >
        <legend class="sr-only">{{ t(`${PO}.RESULTADOS`) }}</legend>
        <ul
          data-relacionamentos="resultados-do-por"
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
                <span class="text-sm truncate text-n-slate-11">
                  {{ contatoDe(item) }}
                </span>
                <span
                  class="text-sm truncate"
                  :class="item.empresa ? 'text-n-amber-11' : 'text-n-slate-11'"
                >
                  {{ ondeEsta(item) }}
                </span>
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
        v-if="mudaDeEmpresa"
        data-relacionamentos="muda-de-empresa"
        class="flex items-start gap-2 m-0 text-base text-n-amber-11"
      >
        <span
          class="mt-1 i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ mudaDeEmpresa }}
      </p>
      <p
        :id="idDoAviso"
        role="alert"
        data-relacionamentos="por-falta"
        class="m-0 text-sm text-n-ruby-11"
        :class="{ hidden: !faltaEscolher && !alerta }"
      >
        {{ faltaEscolher ? t(`${PO}.ESCOLHA`) : alerta }}
      </p>
    </div>
    <template #footer>
      <div class="flex flex-col-reverse w-full gap-3 sm:flex-row">
        <Button
          slate
          faded
          size="lg"
          type="button"
          class="w-full"
          :label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
          @click="dialogo?.close()"
        />
        <Button
          color="blue"
          size="lg"
          type="submit"
          class="w-full"
          data-relacionamentos="confirmar-por"
          :label="t(`${PO}.CONFIRMAR`)"
          :is-loading="pondo"
          :disabled="pondo"
        />
      </div>
    </template>
  </Dialog>
</template>

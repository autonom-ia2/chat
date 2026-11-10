<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import { chaveDoTexto } from '../catalogo';
import { linhasDoResultado } from '../resultado';
import { idiomaDoNavegador } from '../../utils/pagina';
import { useVitrine } from '../useVitrine';

// #2858 F2 — testar antes de incluir: um valor de exemplo já preenchido, um botão, e o resultado em linhas legíveis,
// como o agente recebe. A consulta é de verdade (FerramentasProntasController#experimentar) e conta no limite do dia
// da conta. Fonte sem campo (Banco Central) só tem o botão. Cada situação sem resultado tem uma frase só.
const props = defineProps({
  ferramenta: { type: Object, required: true },
});

const NS = 'AGENTS.VITRINE';
const { t, te, locale } = useI18n();
const { experimentar } = useVitrine();
const campoId = `experimente-${useId()}`;

const base = computed(
  () => `${NS}.FERRAMENTAS.${chaveDoTexto(props.ferramenta.id)}`
);
const rotulo = computed(() => t(`${base.value}.ROTULO`));
const exemplo = () =>
  props.ferramenta.exemplo
    ? props.ferramenta.exemplo(new Date())
    : t(`${base.value}.EXEMPLO`);

const valor = ref(props.ferramenta.semCampo ? '' : exemplo());
const consultando = ref(false);
const resposta = ref(null);

watch(
  () => props.ferramenta.id,
  () => {
    valor.value = props.ferramenta.semCampo ? '' : exemplo();
    resposta.value = null;
  }
);

const SITUACOES = {
  nao_encontrado: 'NAO_ENCONTRADO',
  nao_consegui_consultar: 'NAO_CONSEGUI',
  pedido_invalido: 'PEDIDO_INVALIDO',
  desligada: 'DESLIGADA',
  sem_permissao: 'SEM_PERMISSAO',
};

const textosDoResultado = computed(() => ({
  rotulo: chave => {
    const caminho = `${NS}.CAMPOS.${chaveDoTexto(chave)}`;
    return te(caminho) ? t(caminho) : '';
  },
  maisN: ({ nomes, n }) => t(`${NS}.RESULTADO.E_MAIS`, { nomes, n }),
  sim: t(`${NS}.RESULTADO.SIM`),
  nao: t(`${NS}.RESULTADO.NAO`),
  zeroKm: t(`${NS}.RESULTADO.ZERO_KM`),
  idioma: idiomaDoNavegador(locale.value),
}));

const encontrado = computed(() => resposta.value?.situacao === 'encontrado');
const linhas = computed(() =>
  encontrado.value
    ? linhasDoResultado(resposta.value.dados, textosDoResultado.value)
    : []
);
const aviso = computed(() => {
  if (!resposta.value || encontrado.value) return '';
  const chave = SITUACOES[resposta.value.situacao] || 'NAO_CONSEGUI';
  return t(`${NS}.RESULTADO.${chave}`);
});

const rodar = async () => {
  const texto = valor.value.trim();
  if (consultando.value || (!props.ferramenta.semCampo && !texto)) return;
  consultando.value = true;
  resposta.value = null;
  resposta.value = await experimentar(props.ferramenta.id, texto);
  consultando.value = false;
};
</script>

<template>
  <section data-vitrine-experimente class="flex flex-col gap-3">
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.DETALHE.EXPERIMENTE`) }}
    </h3>
    <form class="flex flex-col gap-2 sm:flex-row" @submit.prevent="rodar">
      <p
        v-if="ferramenta.semCampo"
        class="flex-1 m-0 text-sm text-n-slate-11 sm:self-center"
      >
        {{ rotulo }}
      </p>
      <div v-else class="flex flex-col flex-1 gap-1">
        <label :for="campoId" class="text-sm text-n-slate-11">
          {{ rotulo }}
        </label>
        <input
          :id="campoId"
          v-model="valor"
          data-experimente-valor
          type="text"
          class="w-full px-3 !mb-0 text-base border-0 rounded-xl min-h-11 bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:ring-2 focus:ring-n-blue-11"
        />
      </div>
      <AgenteBotao
        type="submit"
        data-experimentar
        variante="contorno"
        icone="i-lucide-play"
        class="sm:self-end"
        :carregando="consultando"
      >
        {{
          consultando
            ? t(`${NS}.DETALHE.EXPERIMENTANDO`)
            : t(`${NS}.DETALHE.EXPERIMENTAR`)
        }}
      </AgenteBotao>
    </form>
    <div aria-live="polite">
      <div
        v-if="encontrado"
        data-experimente-resultado
        class="flex flex-col gap-2 p-4 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
      >
        <p
          class="flex items-center gap-2 m-0 text-sm font-semibold text-n-teal-11"
        >
          <span class="i-lucide-circle-check size-4" aria-hidden="true" />
          {{ t(`${NS}.DETALHE.DEU_CERTO`) }}
        </p>
        <dl
          v-if="linhas.length"
          class="grid gap-x-4 gap-y-1 m-0 grid-cols-[auto_1fr]"
        >
          <template v-for="([nome, dado], indice) in linhas" :key="indice">
            <dt class="text-sm text-n-slate-11">{{ nome }}</dt>
            <dd class="m-0 text-sm font-medium break-words text-n-slate-12">
              {{ dado }}
            </dd>
          </template>
        </dl>
      </div>
      <p
        v-else-if="aviso"
        data-experimente-aviso
        class="flex items-start gap-2 p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
      >
        <span
          class="i-lucide-info size-4 mt-0.5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        {{ aviso }}
      </p>
    </div>
  </section>
</template>

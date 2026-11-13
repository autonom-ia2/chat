<script setup>
import { computed, onMounted, ref } from 'vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import LivreConsultaPronta from './LivreConsultaPronta.vue';
import LivreConsultaEndereco from './LivreConsultaEndereco.vue';
import { ENDERECO, P, PRONTA } from './passosNovos';
import {
  carregarConsultasProntas,
  consultasProntasDaConta,
} from './dadosDaConta';

// #2934 — Buscar informação em outro sistema (decisão do Rodrigo, 12/11: "foco
// na jornada"). "Onde buscar" é uma lista de consultas prontas do dia a dia
// (Busca de CEP, Consulta de CNPJ…): a pessoa toca numa, diz de onde vem o que
// ela pede ("Pôr um dado") e já sabe o que volta, com o nome pronto. A
// consulta que a conta não pode usar aparece com o que falta, nunca some.
// "Outro endereço" fica por último, como avançado, só para quem cuida das
// integrações (como o webhook). Sem <select>: cada opção é um cartão com rádio.
const props = defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);
const C = `${P}.CONSULTAR`;
const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const podeIntegrar = usePermissionGranted('integration_manage');
const carregando = ref(true);
const consultas = computed(() => consultasProntasDaConta());
const fonte = computed(() => props.modelValue.fonte || {});
const escolhida = computed(() =>
  fonte.value.de === PRONTA
    ? consultas.value.find(consulta => consulta.id === fonte.value.consulta)
    : null
);
const ehEndereco = computed(() => fonte.value.de === ENDERECO);
// O "Outro endereço" de quem não tem a chave: aparece só se o passo já usa,
// para dizer por que não dá para mudar.
const mostraEndereco = computed(() => podeIntegrar.value || ehEndereco.value);
const valorEscolhido = computed(() =>
  ehEndereco.value ? ENDERECO : fonte.value.consulta || ''
);

// Escolher uma consulta já põe uma entrada para cada coisa que ela pede (o que
// já estava escrito fica) e guarda todos os dados que ela devolve, com o nome
// pronto. Trocar de consulta limpa o resto.
const escolherConsulta = consulta => {
  const antes = fonte.value.de === PRONTA ? fonte.value.entradas || {} : {};
  const mesma = fonte.value.consulta === consulta.id;
  mudar({
    fonte: {
      de: PRONTA,
      consulta: consulta.id,
      entradas: Object.fromEntries(
        consulta.entradas.map(({ nome }) => [
          nome,
          mesma ? antes[nome] || [] : [],
        ])
      ),
    },
    guardar: consulta.dados.map(({ caminho, rotulo }) => ({
      nome: rotulo,
      caminho,
    })),
  });
};
const escolherEndereco = () =>
  mudar({ fonte: { de: ENDERECO, url: '' }, guardar: [] });
const escolher = valor => {
  if (valor === ENDERECO) {
    escolherEndereco();
    return;
  }
  const consulta = consultas.value.find(item => item.id === valor);
  if (consulta?.disponivel) escolherConsulta(consulta);
};

// Começar pronto: a primeira consulta que a conta pode usar já vem escolhida.
onMounted(async () => {
  await carregarConsultasProntas();
  carregando.value = false;
  if (ehEndereco.value || escolhida.value) return;
  const primeira = consultas.value.find(consulta => consulta.disponivel);
  if (primeira) escolherConsulta(primeira);
});
</script>

<template>
  <div class="flex flex-col gap-6" data-passo-novo="consultar">
    <fieldset class="flex flex-col gap-2 p-0 m-0 border-0 min-w-0">
      <legend class="mb-2 text-sm font-medium text-n-slate-12">
        {{ $t(`${C}.FONTE`) }}
      </legend>
      <p
        v-if="carregando"
        class="mb-0 text-sm text-n-slate-11"
        data-consulta-carregando
      >
        {{ $t(`${C}.CARREGANDO`) }}
      </p>
      <label
        v-for="consulta in consultas"
        :key="consulta.id"
        :data-consulta-opcao="consulta.id"
        class="flex items-start gap-3 px-4 py-3 border rounded-xl min-h-11 transition-colors"
        :class="[
          !consulta.disponivel
            ? 'border-n-weak bg-n-alpha-1 cursor-not-allowed'
            : valorEscolhido === consulta.id
              ? 'border-n-teal-8 bg-n-teal-2 cursor-pointer'
              : 'border-n-weak bg-n-solid-1 hover:border-n-blue-7 cursor-pointer',
        ]"
      >
        <input
          type="radio"
          name="consulta-fonte"
          class="mt-1 size-4 shrink-0 accent-n-teal-9"
          :value="consulta.id"
          :checked="valorEscolhido === consulta.id"
          :disabled="!consulta.disponivel"
          @change="escolher(consulta.id)"
        />
        <span class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span class="flex flex-wrap items-center gap-2">
            <span
              class="text-[0.9375rem] font-medium"
              :class="
                consulta.disponivel ? 'text-n-slate-12' : 'text-n-slate-11'
              "
            >
              {{ consulta.nome }}
            </span>
            <span
              v-if="consulta.disponivel"
              class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ $t(`${C}.GRATIS`) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">{{ consulta.faz }}</span>
          <span
            v-if="!consulta.disponivel"
            data-consulta-falta
            class="text-sm text-n-amber-11"
          >
            {{ consulta.falta }}
          </span>
        </span>
      </label>
      <label
        v-if="mostraEndereco"
        data-consulta-opcao="endereco"
        class="flex items-start gap-3 px-4 py-3 border rounded-xl min-h-11 transition-colors"
        :class="[
          !podeIntegrar
            ? 'border-n-weak bg-n-alpha-1 cursor-not-allowed'
            : ehEndereco
              ? 'border-n-teal-8 bg-n-teal-2 cursor-pointer'
              : 'border-n-weak bg-n-solid-1 hover:border-n-blue-7 cursor-pointer',
        ]"
      >
        <input
          type="radio"
          name="consulta-fonte"
          class="mt-1 size-4 shrink-0 accent-n-teal-9"
          :value="ENDERECO"
          :checked="ehEndereco"
          :disabled="!podeIntegrar"
          @change="escolher(ENDERECO)"
        />
        <span class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span class="flex flex-wrap items-center gap-2">
            <span class="text-[0.9375rem] font-medium text-n-slate-12">
              {{ $t(`${C}.OUTRO_ENDERECO`) }}
            </span>
            <span
              class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ $t(`${C}.AVANCADO`) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`${C}.OUTRO_ENDERECO_FAZ`) }}
          </span>
          <span v-if="!podeIntegrar" class="text-sm text-n-amber-11">
            {{ $t(`${C}.ENDERECO_SEM_CHAVE`) }}
          </span>
        </span>
      </label>
      <p
        v-if="
          !carregando &&
          !consultas.some(item => item.disponivel) &&
          !podeIntegrar
        "
        data-consulta-nenhuma
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ $t(`${C}.NENHUMA`) }}
      </p>
    </fieldset>

    <LivreConsultaPronta
      v-if="escolhida"
      :model-value="modelValue"
      :consulta="escolhida"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="novo => emit('update:modelValue', novo)"
    />
    <LivreConsultaEndereco
      v-else-if="ehEndereco && podeIntegrar"
      :model-value="modelValue"
      @update:model-value="novo => emit('update:modelValue', novo)"
    />

    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.SE_FALHAR`) }}</p>
  </div>
</template>

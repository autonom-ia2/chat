<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LivreTexto from '../components/LivreTexto.vue';
import { dadoDoAlvo } from '../texto';
import { P } from './passosNovos';
import { testarConsulta } from './dadosDaConta';

// #2934 — a consulta pronta escolhida: o que ela precisa (cada coisa com
// "Pôr um dado", para vir do contato ou do card), o que volta (já com o nome
// do dia a dia, que aparece no "Pôr um dado" dos próximos passos) e um teste
// com um exemplo, que busca de verdade e gasta uma das buscas do dia da conta.
const props = defineProps({
  modelValue: { type: Object, required: true },
  // { id, nome, entradas: [{ nome, rotulo, exemplo }], dados, limite_do_dia }
  consulta: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const C = `${P}.CONSULTAR`;

const entradas = computed(() => props.modelValue.fonte?.entradas || {});
const mudarEntrada = (nome, partes) =>
  emit('update:modelValue', {
    ...props.modelValue,
    fonte: {
      ...props.modelValue.fonte,
      entradas: { ...entradas.value, [nome]: partes },
    },
  });
const porDadoEm = rotulo =>
  t(
    `AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO_EM.${dadoDoAlvo(props.catalogo)}`,
    {
      campo: rotulo,
    }
  );

// O teste: um exemplo para cada coisa que a consulta pede, já preenchido.
const exemplos = ref({});
const resposta = ref(null);
const erroDoTeste = ref('');
const testando = ref(false);
watch(
  () => props.consulta.id,
  () => {
    exemplos.value = Object.fromEntries(
      props.consulta.entradas.map(({ nome, exemplo }) => [nome, exemplo || ''])
    );
    resposta.value = null;
    erroDoTeste.value = '';
  },
  { immediate: true }
);
const podeTestar = computed(() =>
  props.consulta.entradas.every(({ nome }) =>
    (exemplos.value[nome] || '').trim()
  )
);
const testar = async () => {
  testando.value = true;
  erroDoTeste.value = '';
  try {
    const achou = await testarConsulta({
      de: 'pronta',
      consulta: props.consulta.id,
      exemplos: exemplos.value,
    });
    erroDoTeste.value = achou.ok
      ? ''
      : achou.error || t(`${C}.TESTE_FALHOU_PRONTA`);
    resposta.value = achou.ok ? achou.dados : null;
  } finally {
    testando.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6" data-consulta-pronta>
    <section class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ $t(`${C}.PRECISA`) }}
        </h4>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t(`${C}.PRECISA_DICA`) }}
        </p>
      </div>
      <LivreTexto
        v-for="entrada in consulta.entradas"
        :key="entrada.nome"
        :data-consulta-entrada="entrada.nome"
        uma-linha
        :rotulo="entrada.rotulo"
        :rotulo-do-dado="porDadoEm(entrada.rotulo)"
        :model-value="entradas[entrada.nome] || []"
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="partes => mudarEntrada(entrada.nome, partes)"
      />
    </section>

    <section class="flex flex-col gap-2" data-consulta-volta>
      <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ $t(`${C}.VOLTA`) }}
      </h4>
      <ul class="flex flex-wrap gap-2 p-0 m-0 list-none">
        <li
          v-for="dado in consulta.dados"
          :key="dado.caminho"
          class="px-3 py-1.5 text-sm rounded-full bg-n-alpha-2 text-n-slate-12"
        >
          {{ dado.rotulo }}
        </li>
      </ul>
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.VOLTA_DICA`) }}</p>
    </section>

    <section
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-alpha-1"
      data-consulta-teste
    >
      <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ $t(`${C}.TESTAR`) }}
      </h4>
      <Input
        v-for="entrada in consulta.entradas"
        :key="entrada.nome"
        :data-consulta-exemplo="entrada.nome"
        :model-value="exemplos[entrada.nome] || ''"
        :label="$t(`${C}.EXEMPLO_DE`, { rotulo: entrada.rotulo })"
        @update:model-value="
          valor => (exemplos = { ...exemplos, [entrada.nome]: valor })
        "
      />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t(`${C}.TESTE_PRONTA_DICA`, { limite: consulta.limite_do_dia }) }}
      </p>
      <Button
        data-consulta-testar
        :label="$t(`${C}.TESTAR`)"
        icon="i-lucide-play"
        faded
        class="self-start min-h-11"
        :is-loading="testando"
        :disabled="!podeTestar || testando"
        @click="testar"
      />
      <p
        v-if="erroDoTeste"
        data-consulta-erro
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ erroDoTeste }}
      </p>
      <dl
        v-if="resposta"
        data-consulta-resposta
        role="status"
        class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 m-0"
      >
        <template v-for="dado in resposta" :key="dado.caminho">
          <dt class="text-sm text-n-slate-11">{{ dado.rotulo }}</dt>
          <dd
            class="m-0 text-[0.9375rem] font-medium text-n-slate-12 break-words min-w-0"
          >
            {{ dado.valor }}
          </dd>
        </template>
      </dl>
    </section>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { ENDERECO, P, enderecoServe } from './passosNovos';
import { testarConsulta } from './dadosDaConta';

// #2934 — "Outro endereço" (avançado, só com a chave de integrações): um
// endereço https do sistema da empresa, um teste e o toque no dado que a pessoa
// quer guardar, com o nome que ela der. O teste busca de verdade (o servidor
// recusa endereço interno) e, com a IA da conta, sugere o nome do dia a dia de
// cada dado; esse uso é custo da conta, e a tela avisa antes. O endereço só
// aparece aqui; o Confira e o histórico nunca o mostram.
const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const C = `${P}.CONSULTAR`;

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });
const fonte = computed(() => props.modelValue.fonte || {});
const enderecoRuim = computed(
  () => fonte.value.url && !enderecoServe(fonte.value.url)
);

const resposta = ref(null);
const testando = ref(false);
const erroDoTeste = ref('');
const testar = async () => {
  testando.value = true;
  erroDoTeste.value = '';
  try {
    const achou = await testarConsulta(fonte.value);
    erroDoTeste.value = achou.ok ? '' : achou.error || t(`${C}.TESTE_FALHOU`);
    resposta.value = achou.ok
      ? achou.dados.map(dado => ({ ...dado, nome: dado.rotulo }))
      : null;
  } finally {
    testando.value = false;
  }
};

const guardados = computed(() => props.modelValue.guardar || []);
const guardado = caminho =>
  guardados.value.some(dado => dado.caminho === caminho);
const alternar = dado =>
  mudar({
    guardar: guardado(dado.caminho)
      ? guardados.value.filter(item => item.caminho !== dado.caminho)
      : [...guardados.value, { nome: dado.nome, caminho: dado.caminho }],
  });
const renomear = (caminho, nome) =>
  mudar({
    guardar: guardados.value.map(item =>
      item.caminho === caminho ? { ...item, nome } : item
    ),
  });
</script>

<template>
  <div class="flex flex-col gap-5" data-consulta-endereco-proprio>
    <Input
      data-consulta-endereco
      type="url"
      :model-value="fonte.url || ''"
      :label="$t(`${C}.ENDERECO`)"
      :placeholder="$t(`${C}.ENDERECO_EXEMPLO`)"
      :message="$t(enderecoRuim ? `${C}.ENDERECO_RUIM` : `${C}.ENDERECO_DICA`)"
      :message-type="enderecoRuim ? 'error' : 'info'"
      @update:model-value="
        url => mudar({ fonte: { de: ENDERECO, url: url.trim() } })
      "
    />

    <div class="flex flex-col gap-2">
      <p
        data-consulta-custo-ia
        role="note"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-12"
      >
        {{ $t(`${C}.IA_CUSTO`) }}
      </p>
      <Button
        data-consulta-testar
        :label="$t(`${C}.TESTAR`)"
        icon="i-lucide-play"
        faded
        class="self-start min-h-11"
        :is-loading="testando"
        :disabled="!enderecoServe(fonte.url) || testando"
        @click="testar"
      />
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.TESTAR_DICA`) }}</p>
      <p
        v-if="erroDoTeste"
        data-consulta-erro
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ erroDoTeste }}
      </p>
    </div>

    <div v-if="resposta" data-consulta-resposta class="flex flex-col gap-2">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${C}.TOQUE_NO_DADO`) }}
      </p>
      <p
        v-if="!resposta.length"
        class="mb-0 text-sm text-n-slate-11"
        data-consulta-sem-dado
      >
        {{ $t(`${C}.RESPOSTA_VAZIA`) }}
      </p>
      <ul v-else class="flex flex-col gap-1.5 p-0 m-0 list-none">
        <li v-for="dado in resposta" :key="dado.caminho">
          <button
            type="button"
            :data-consulta-dado="dado.caminho"
            :aria-pressed="guardado(dado.caminho)"
            class="flex items-center w-full gap-3 px-4 py-2 border text-start rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              guardado(dado.caminho)
                ? 'border-n-teal-8 bg-n-teal-2'
                : 'border-n-weak bg-n-solid-1 hover:border-n-blue-7'
            "
            @click="alternar(dado)"
          >
            <span
              class="size-4 shrink-0"
              :class="
                guardado(dado.caminho)
                  ? 'i-lucide-check text-n-teal-11'
                  : 'i-lucide-plus text-n-slate-10'
              "
              aria-hidden="true"
            />
            <span
              class="flex-1 min-w-0 text-sm text-n-slate-11 first-letter:uppercase"
            >
              {{ dado.nome }}
            </span>
            <span
              class="text-[0.9375rem] font-medium text-n-slate-12 break-words"
            >
              {{ dado.valor }}
            </span>
          </button>
        </li>
      </ul>
    </div>

    <div
      v-if="guardados.length"
      data-consulta-guardados
      class="flex flex-col gap-3"
    >
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${C}.GUARDADOS`) }}
      </p>
      <Input
        v-for="dado in guardados"
        :key="dado.caminho"
        :data-consulta-nome="dado.caminho"
        :model-value="dado.nome"
        :label="$t(`${C}.NOME_DO_DADO`)"
        :message="$t(`${C}.NOME_DICA`)"
        @update:model-value="nome => renomear(dado.caminho, nome)"
      />
    </div>
    <p v-else class="mb-0 text-sm text-n-slate-11" data-consulta-falta-dado>
      {{ $t(`${C}.FALTA_DADO`) }}
    </p>
  </div>
</template>

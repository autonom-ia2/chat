<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { P, enderecoServe } from './passosNovos';
import { integracoesDaConta, testarConsulta } from './adaptadorFalso';

// #2934 — Consultar outro sistema: de onde vem a informação (uma integração já
// conectada ou um endereço próprio), um teste e o toque no dado que a pessoa
// quer guardar, com o nome que ela der. O dado aparece no "Pôr um dado" dos
// passos seguintes. O endereço só aparece aqui, para quem tem a chave de
// integrações; o Confira e o histórico nunca o mostram.
const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const C = `${P}.CONSULTAR`;
const ENDERECO = 'endereco';

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const integracoes = computed(() => integracoesDaConta(t));
const fontes = computed(() => [
  ...integracoes.value,
  { value: ENDERECO, label: t(`${C}.OUTRO_ENDERECO`) },
]);
const fonte = computed(() => props.modelValue.fonte || {});
const valorDaFonte = computed(() =>
  fonte.value.de === ENDERECO ? ENDERECO : fonte.value.id || ''
);
// Trocar de onde vem a informação limpa o teste e os dados guardados.
const resposta = ref(null);
const escolherFonte = valor => {
  resposta.value = null;
  mudar({
    fonte:
      valor === ENDERECO
        ? { de: ENDERECO, url: '' }
        : { de: 'integracao', id: valor },
    guardar: [],
  });
};
const enderecoRuim = computed(
  () =>
    fonte.value.de === ENDERECO &&
    fonte.value.url &&
    !enderecoServe(fonte.value.url)
);
const podeTestar = computed(() =>
  fonte.value.de === ENDERECO
    ? enderecoServe(fonte.value.url)
    : Boolean(fonte.value.id)
);

const testando = ref(false);
const testar = async () => {
  testando.value = true;
  try {
    resposta.value = await testarConsulta(fonte.value, t);
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

// Começar pronto: a primeira integração conectada já vem escolhida.
onMounted(() => {
  if (
    !fonte.value.id &&
    fonte.value.de !== ENDERECO &&
    integracoes.value.length
  )
    escolherFonte(integracoes.value[0].value);
});
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="consultar">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${C}.FONTE`) }}
      </span>
      <ChoiceSelect
        data-consulta-fonte
        :model-value="valorDaFonte"
        :aria-label="$t(`${C}.FONTE`)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="fontes"
        @update:model-value="escolherFonte"
      />
    </div>

    <Input
      v-if="fonte.de === ENDERECO"
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
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.TESTAR_DICA`) }}</p>
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

    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${C}.SE_FALHAR`) }}</p>
  </div>
</template>

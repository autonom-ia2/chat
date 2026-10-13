<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import api from '../../api/modelosWhatsapp';
import CustoDoTipo from '../CustoDoTipo.vue';
import ModeloCelular from '../ModeloCelular.vue';

// Criar com IA: a pessoa diz o objetivo em uma frase e escolhe o tom; recebe 2
// ou 3 opções prontas, cada uma no celular, com o tipo previsto, o custo por
// envio e os campos. "Usar esta" leva para o texto; "Gerar outras" pede de novo.
const props = defineProps({
  numeros: { type: Array, default: () => [] },
  remetente: { type: String, default: '' },
});

const emit = defineEmits(['usar', 'voltar', 'meuJeito']);

const LIMITE_DO_OBJETIVO = 200;
const TONS = [
  { chave: 'curto', icone: 'i-lucide-zap' },
  { chave: 'simpatico', icone: 'i-lucide-smile' },
  { chave: 'formal', icone: 'i-lucide-briefcase' },
];

const objetivo = ref('');
const tom = ref('simpatico');
const estado = ref('pedindo');
const opcoes = ref([]);

const escrever = async () => {
  estado.value = 'escrevendo';
  try {
    const resposta = await api.criarComIA({
      objetivo: objetivo.value.trim(),
      tom: tom.value,
      numeros: props.numeros,
    });
    opcoes.value = resposta.opcoes;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

const camposDa = opcao => [
  ...new Set(
    opcao.conteudo.texto.filter(pedaco => pedaco.t === 'campo').map(p => p.v)
  ),
];
</script>

<template>
  <div data-criar-com-ia class="flex flex-col gap-6">
    <button
      type="button"
      class="inline-flex items-center self-start gap-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
      @click="emit('voltar')"
    >
      <span class="i-lucide-arrow-left size-4 rtl:rotate-180" aria-hidden="true" />
      {{ $t('MODELOS_WHATSAPP.IA.VOLTAR_AOS_PRONTOS') }}
    </button>

    <section
      class="flex flex-col gap-5 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <div class="flex items-start gap-3">
        <span class="grid place-items-center size-11 shrink-0 rounded-xl bg-n-iris-3 text-n-iris-11">
          <span class="i-lucide-sparkles size-6" aria-hidden="true" />
        </span>
        <div>
          <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.IA.CRIAR_TITULO') }}
          </h2>
          <p class="mb-0 mt-1 text-base text-n-slate-11">
            {{ $t('MODELOS_WHATSAPP.IA.CRIAR_TEXTO') }}
          </p>
        </div>
      </div>
      <TextArea
        v-model="objetivo"
        data-objetivo-ia
        :label="$t('MODELOS_WHATSAPP.IA.OBJETIVO')"
        :placeholder="$t('MODELOS_WHATSAPP.IA.OBJETIVO_EXEMPLO')"
        :max-length="LIMITE_DO_OBJETIVO"
        show-character-count
      />
      <div class="flex flex-col gap-2">
        <span id="tom-ia" class="text-sm font-medium text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.IA.TOM') }}
        </span>
        <div role="radiogroup" aria-labelledby="tom-ia" class="grid grid-cols-3 gap-3">
          <button
            v-for="item in TONS"
            :key="item.chave"
            type="button"
            role="radio"
            :data-tom="item.chave"
            :aria-checked="tom === item.chave"
            class="flex flex-col items-center justify-center gap-1.5 p-3 text-[0.9375rem] font-medium rounded-xl min-h-[4.5rem] ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              tom === item.chave
                ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
                : 'ring-n-weak bg-n-solid-1 text-n-slate-11 hover:ring-n-blue-6'
            "
            @click="tom = item.chave"
          >
            <span class="size-5" :class="item.icone" aria-hidden="true" />
            {{ $t(`MODELOS_WHATSAPP.IA.TONS.${item.chave}`) }}
          </button>
        </div>
      </div>
      <Button
        data-escrever-ia
        :label="
          estado === 'pronto'
            ? $t('MODELOS_WHATSAPP.IA.GERAR_OUTRAS')
            : $t('MODELOS_WHATSAPP.IA.ESCREVER_OPCOES')
        "
        :icon="estado === 'pronto' ? 'i-lucide-refresh-cw' : 'i-lucide-sparkles'"
        size="lg"
        class="self-start !min-h-12 !rounded-xl"
        :disabled="!objetivo.trim() || estado === 'escrevendo'"
        @click="escrever"
      />
    </section>

    <div
      v-if="estado === 'escrevendo'"
      data-ia-escrevendo
      role="status"
      aria-live="polite"
      class="flex flex-col gap-4"
    >
      <p class="flex items-center gap-2 mb-0 text-base font-medium text-n-slate-12">
        <span class="i-lucide-loader-circle size-5 animate-spin text-n-iris-11" aria-hidden="true" />
        {{ $t('MODELOS_WHATSAPP.IA.ESCREVENDO') }}
      </p>
      <div class="grid gap-4 md:grid-cols-3">
        <div v-for="n in 3" :key="n" class="h-80 rounded-2xl bg-n-alpha-2 animate-pulse" />
      </div>
    </div>

    <div
      v-else-if="estado === 'erro'"
      data-ia-erro
      role="alert"
      class="flex flex-col items-start gap-4 p-6 rounded-2xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
    >
      <p class="mb-0 text-base text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.IA.ERRO') }}
      </p>
      <div class="flex flex-wrap gap-3">
        <Button
          :label="$t('MODELOS_WHATSAPP.IA.TENTAR_DE_NOVO')"
          icon="i-lucide-refresh-cw"
          class="min-h-11"
          @click="escrever"
        />
        <Button
          data-meu-jeito-ia
          :label="$t('MODELOS_WHATSAPP.IA.MEU_JEITO')"
          color="slate"
          variant="faded"
          class="min-h-11"
          @click="emit('meuJeito')"
        />
      </div>
    </div>

    <ul
      v-else-if="estado === 'pronto'"
      data-ia-opcoes
      class="grid gap-4 p-0 m-0 list-none md:grid-cols-2 xl:grid-cols-3"
    >
      <li
        v-for="(opcao, indice) in opcoes"
        :key="opcao.id"
        :data-opcao-ia="indice + 1"
        class="flex flex-col gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <span class="text-sm font-semibold text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.IA.OPCAO', { n: indice + 1 }) }}
        </span>
        <ModeloCelular :conteudo="opcao.conteudo" :remetente="remetente" compacto />
        <CustoDoTipo :tipo="opcao.tipo" />
        <div v-if="camposDa(opcao).length" class="flex flex-wrap items-center gap-1.5">
          <span class="text-sm text-n-slate-11">{{ $t('MODELOS_WHATSAPP.IA.CAMPOS') }}</span>
          <span
            v-for="campo in camposDa(opcao)"
            :key="campo"
            class="px-1.5 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
          >
            {{ $t(`MODELOS_WHATSAPP.CAMPOS.${campo}.ROTULO`) }}
          </span>
        </div>
        <Button
          data-usar-opcao
          :label="$t('MODELOS_WHATSAPP.IA.USAR_ESTA')"
          icon="i-lucide-check"
          class="mt-auto !min-h-11 !rounded-xl"
          @click="emit('usar', opcao)"
        />
      </li>
    </ul>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import ModeloEditorTexto from '../../components/ModeloEditorTexto.vue';
import { rotuloDoCampo } from '../../helpers/campos';
import { numero } from '../../helpers/datas';
import { juntar, pedacos, previa } from '../textoComCampos';

// A ajuda para escrever a mensagem da conversa aberta (#1335). Uma coisa por
// vez: dizer o que quer → escolher uma opção → ajustar e "Pronto". "Alterar"
// abre direto no ajuste. Quem decide o texto é a pessoa; a ajuda só propõe.
const props = defineProps({
  quantos: { type: Number, required: true },
  texto: { type: String, default: '' },
  exemplos: { type: Object, default: () => ({}) },
  // (pedido) → { status, opcoes: [{ texto }], pergunta }
  escrever: { type: Function, required: true },
});

const emit = defineEmits(['usar', 'fechar']);

const NS = 'MODELOS_WHATSAPP.JANELA.GAVETA';
const CAMPOS_DO_TEXTO = ['cliente.primeiro_nome', 'minha_empresa.nome'];
const TONS = ['simpatico', 'curto', 'formal'];
const MELHORIAS = [
  { chave: 'mais_curta', icone: 'i-lucide-scissors' },
  { chave: 'mais_simpatica', icone: 'i-lucide-smile' },
  { chave: 'mais_clara', icone: 'i-lucide-lightbulb' },
];

const { t, locale } = useI18n();
const objetivo = ref('');
const resposta = ref('');
const tom = ref('simpatico');
const etapa = ref(props.texto ? 'ajustar' : 'pedir');
const pergunta = ref('');
const opcoes = ref([]);
const conteudo = ref(pedacos(props.texto));
const anterior = ref(null);
const melhorando = ref('');

const titulo = computed(() =>
  t(`${NS}.TITULO`, { n: numero(props.quantos, locale.value) }, props.quantos)
);
const textoAtual = computed(() => juntar(conteudo.value));
const vazio = computed(() => !textoAtual.value.trim());

const pedirOpcoes = async () => {
  etapa.value = 'escrevendo';
  try {
    const saida = await props.escrever({
      objetivo: objetivo.value,
      resposta: resposta.value,
      tom: tom.value,
      quantos: props.quantos,
    });
    if (saida.status === 'precisa_mais_info') {
      pergunta.value = saida.pergunta;
      etapa.value = 'pergunta';
      return;
    }
    opcoes.value = saida.opcoes;
    etapa.value = saida.opcoes.length ? 'escolher' : 'erro';
  } catch {
    etapa.value = 'erro';
  }
};

const escolher = opcao => {
  conteudo.value = pedacos(opcao.texto);
  etapa.value = 'ajustar';
};

const escreverSozinho = () => {
  conteudo.value = [];
  etapa.value = 'ajustar';
};

const melhorar = async chave => {
  melhorando.value = chave;
  try {
    const saida = await props.escrever({
      base: textoAtual.value,
      pedido: { melhoria: chave },
      tom: tom.value,
      quantos: props.quantos,
    });
    if (saida.opcoes?.length) {
      anterior.value = conteudo.value;
      conteudo.value = pedacos(saida.opcoes[0].texto);
    }
  } catch {
    etapa.value = 'erro';
  } finally {
    melhorando.value = '';
  }
};

const desfazer = () => {
  conteudo.value = anterior.value;
  anterior.value = null;
};
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <div data-escrever-conversa-aberta class="flex flex-col gap-5">
      <template v-if="etapa === 'pedir' || etapa === 'pergunta'">
        <label class="flex flex-col gap-2">
          <span class="text-base font-medium text-n-slate-12">
            {{ t(`${NS}.O_QUE`) }}
          </span>
          <textarea
            v-model="objetivo"
            data-objetivo
            rows="3"
            :placeholder="t(`${NS}.O_QUE_EXEMPLO`)"
            class="m-0 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-base text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </label>
        <label v-if="etapa === 'pergunta'" class="flex flex-col gap-2">
          <span
            data-pergunta
            class="p-3 text-[0.9375rem] rounded-xl bg-n-blue-2 text-n-slate-12"
          >
            {{ pergunta }}
          </span>
          <textarea
            v-model="resposta"
            data-resposta
            rows="2"
            class="m-0 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-base text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </label>
        <div
          role="radiogroup"
          :aria-label="t(`${NS}.JEITO`)"
          class="flex flex-col gap-2"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.JEITO`) }}
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="item in TONS"
              :key="item"
              type="button"
              role="radio"
              :data-tom="item"
              :aria-checked="tom === item"
              class="px-4 text-sm font-medium rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="
                tom === item
                  ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
                  : 'ring-n-weak bg-n-solid-1 text-n-slate-12'
              "
              @click="tom = item"
            >
              {{ t(`${NS}.TONS.${item}`) }}
            </button>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <Button
            data-escrever-para-mim
            :label="t(`${NS}.ESCREVER_PARA_MIM`)"
            icon="i-lucide-sparkles"
            class="!min-h-11 !rounded-xl"
            :disabled="!objetivo.trim()"
            @click="pedirOpcoes"
          />
          <Button
            data-sozinho
            :label="t(`${NS}.SOZINHO`)"
            variant="ghost"
            color="slate"
            class="!min-h-11"
            @click="escreverSozinho"
          />
        </div>
      </template>

      <p
        v-else-if="etapa === 'escrevendo'"
        role="status"
        class="flex items-center gap-2 m-0 text-base font-medium text-n-slate-12"
      >
        <span
          class="i-lucide-loader-circle size-5 animate-spin text-n-iris-11"
          aria-hidden="true"
        />
        {{ t(`${NS}.ESCREVENDO`) }}
      </p>

      <div v-else-if="etapa === 'erro'" class="flex flex-col gap-3">
        <p
          data-erro
          role="alert"
          class="p-4 m-0 text-[0.9375rem] rounded-xl bg-n-ruby-2 text-n-slate-12"
        >
          {{ t(`${NS}.ERRO`) }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            :label="t(`${NS}.TENTAR_DE_NOVO`)"
            variant="outline"
            color="slate"
            class="!min-h-11 !rounded-xl"
            @click="etapa = 'pedir'"
          />
          <Button
            :label="t(`${NS}.SOZINHO`)"
            class="!min-h-11 !rounded-xl"
            @click="escreverSozinho"
          />
        </div>
      </div>

      <template v-else-if="etapa === 'escolher'">
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{ t(`${NS}.ESCOLHA`) }}
        </p>
        <ul class="flex flex-col gap-3 p-0 m-0 list-none">
          <li
            v-for="(opcao, indice) in opcoes"
            :key="indice"
            :data-opcao="indice"
            class="flex flex-col gap-3 p-4 rounded-xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
          >
            <p
              class="m-0 text-[0.9375rem] leading-relaxed whitespace-pre-wrap break-words text-n-slate-12"
            >
              <template
                v-for="(pedaco, posicao) in pedacos(opcao.texto)"
                :key="posicao"
              >
                <span
                  v-if="pedaco.t === 'campo'"
                  class="px-1 text-sm font-medium rounded bg-n-blue-3 text-n-blue-11"
                >
                  {{ rotuloDoCampo(t, pedaco.v) }}
                </span>
                <span v-else>{{ pedaco.v }}</span>
              </template>
            </p>
            <Button
              :data-usar-opcao="indice"
              :label="t(`${NS}.USAR_ESTA`)"
              icon="i-lucide-check"
              variant="outline"
              class="self-start !min-h-11 !rounded-xl"
              @click="escolher(opcao)"
            />
          </li>
        </ul>
        <Button
          data-outras
          :label="t(`${NS}.OUTRAS`)"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          color="slate"
          class="self-start !min-h-11"
          @click="pedirOpcoes"
        />
      </template>

      <template v-else-if="etapa === 'ajustar'">
        <ModeloEditorTexto
          v-model="conteudo"
          :rotulo="t(`${NS}.SUA_MENSAGEM`)"
          :campos="CAMPOS_DO_TEXTO"
        />
        <div v-if="!vazio" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.MELHORAR`) }}
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="item in MELHORIAS"
              :key="item.chave"
              type="button"
              :data-melhoria="item.chave"
              :disabled="Boolean(melhorando)"
              class="inline-flex items-center gap-2 px-3 text-sm font-medium rounded-xl min-h-11 ring-1 ring-inset ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-blue-6 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="melhorar(item.chave)"
            >
              <span
                class="size-4"
                :class="
                  melhorando === item.chave
                    ? 'i-lucide-loader-circle animate-spin'
                    : item.icone
                "
                aria-hidden="true"
              />
              {{ t(`${NS}.MELHORIAS.${item.chave}`) }}
            </button>
            <Button
              v-if="anterior"
              data-desfazer
              :label="t(`${NS}.DESFAZER`)"
              icon="i-lucide-undo-2"
              variant="ghost"
              color="slate"
              class="!min-h-11"
              @click="desfazer"
            />
          </div>
        </div>
        <section v-if="!vazio" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.COMO_CHEGA`) }}
          </span>
          <div class="p-3 rounded-2xl bg-n-teal-2">
            <p
              data-previa-texto
              class="m-0 max-w-md whitespace-pre-wrap break-words rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
            >
              {{ previa(textoAtual, exemplos) }}
            </p>
          </div>
        </section>
      </template>
    </div>

    <template v-if="etapa === 'ajustar'" #rodape>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          :label="t(`${NS}.CANCELAR`)"
          color="slate"
          variant="faded"
          class="!min-h-11"
          @click="emit('fechar')"
        />
        <Button
          data-pronto
          :label="t(`${NS}.PRONTO`)"
          icon="i-lucide-check"
          class="!min-h-11"
          :disabled="vazio"
          @click="emit('usar', textoAtual)"
        />
      </div>
    </template>
  </AgenteGaveta>
</template>

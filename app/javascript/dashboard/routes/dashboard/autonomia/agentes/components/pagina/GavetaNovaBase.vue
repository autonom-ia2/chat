<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import { rotuloDaBase } from '../../utils/baseDoAgente';

// #1429 F3 — "Atualizar com a nova base": antes de confirmar, o dono vê as mesmas perguntas respondidas agora pelo
// agente com a base de hoje e com a nova, lado a lado (empilhadas no celular). Só a base muda; o resto do agente fica.
// Uma ação principal: o botão de atualizar só aparece depois que as respostas chegam, e grava a versão que foi
// comparada. Errou a comparação, o erro padrão com "Tentar de novo" no lugar. No limite (429), só a espera, com o texto
// do servidor e sem "Tentar de novo". A base nova mudou no meio (409) ou o servidor pede a comparação de novo (422):
// volta para o erro com "Tentar de novo", que compara a base que vale agora; nunca grava uma base que a pessoa não viu.
// Outro erro ao atualizar: o aviso no rodapé, e nada muda.
const props = defineProps({
  base: { type: Object, required: true },
  nome: { type: String, required: true },
  comparar: { type: Function, required: true },
  atualizar: { type: Function, required: true },
});

const emit = defineEmits(['fechar', 'atualizado']);

const { t, locale } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.BASE.GAVETA';
// Os avisos do servidor que a gaveta mostra no lugar da comparação: sem base nova ou sem comparação válida (422), a base
// nova que mudou (409) e o limite (429).
const COM_TEXTO_DO_SERVIDOR = [409, 422, 429];
// Depois de atualizar, estes mandam comparar de novo (a base que vale agora, ou a comparação que passou do prazo).
const COMPARAR_DE_NOVO = [409, 422];
const LIMITE = 429;
// Recusas que comparar de novo não resolve: sem base nova e agente sem instrução. A comparação que passou ou não vale
// (comparar_antes), a base que mudou e a falha da própria comparação oferecem "Tentar de novo".
const SEM_TENTAR_DE_NOVO = ['sem_base_nova', 'sem_instrucao'];

const estado = ref('comparando');
const perguntas = ref([]);
const versaoComparada = ref(null);
const erroComparar = ref('');
// No limite, a gaveta só mostra a espera: "Tentar de novo" ali só daria outro 429.
const esperando = ref(false);
const podeTentar = ref(true);
const atualizando = ref(false);
const falhouAtualizar = ref(false);
const rotuloHoje = ref('');
const rotuloNova = ref('');
let pedido = null;

const rotuloDe = base =>
  base ? rotuloDaBase(base, t, locale.value) : t(`${NS}.SEM_BASE`);

// A resposta do agente, ou o aviso de que ele passaria a conversa para a equipe.
const resposta = (texto, equipe) =>
  texto || (equipe ? t(`${NS}.PASSA_EQUIPE`) : '');

const tituloDoErro = computed(
  () => erroComparar.value || t(`${NS}.ERRO_COMPARAR`)
);

const textoDoServidor = erro =>
  COM_TEXTO_DO_SERVIDOR.includes(erro?.response?.status)
    ? erro.response.data?.error || ''
    : '';

// O aviso no lugar da comparação, com ou sem "Tentar de novo" conforme o motivo do servidor.
const mostrarErro = erro => {
  const { status, data } = erro?.response || {};
  erroComparar.value = textoDoServidor(erro);
  esperando.value = status === LIMITE;
  podeTentar.value =
    !esperando.value && !SEM_TENTAR_DE_NOVO.includes(data?.code);
  estado.value = 'erro';
};

const lerComparacao = async () => {
  // Os rótulos são os das bases que esta comparação usa (a linha já foi relida depois de um 409).
  rotuloHoje.value = rotuloDe(props.base.atual);
  rotuloNova.value = rotuloDe(props.base.nova);
  estado.value = 'comparando';
  erroComparar.value = '';
  esperando.value = false;
  podeTentar.value = true;
  pedido = new AbortController();
  try {
    const { versao, perguntas: lista } = await props.comparar(pedido.signal);
    versaoComparada.value = versao;
    perguntas.value = lista;
    estado.value = lista.length && versao ? 'pronto' : 'erro';
  } catch (erro) {
    if (pedido?.signal.aborted) return;
    mostrarErro(erro);
  }
};

onMounted(lerComparacao);
// Fechou a gaveta: o poll da comparação para.
onBeforeUnmount(() => pedido?.abort());

const confirmar = async () => {
  if (atualizando.value) return;
  atualizando.value = true;
  falhouAtualizar.value = false;
  try {
    await props.atualizar(versaoComparada.value);
    emit('atualizado');
  } catch (erro) {
    if (COMPARAR_DE_NOVO.includes(erro?.response?.status)) {
      mostrarErro(erro);
    } else {
      falhouAtualizar.value = true;
    }
  } finally {
    atualizando.value = false;
  }
};

// Enquanto grava, fechar no Esc ou no fundo não deixa a pessoa sem saber se mudou.
const podeFechar = () => !atualizando.value;
</script>

<template>
  <AgenteGaveta
    :titulo="t(`${NS}.TITULO`)"
    :pode-fechar="podeFechar"
    @fechar="emit('fechar')"
  >
    <p class="m-0 text-sm text-n-slate-12">
      {{ t(`${NS}.INTRO`, { nome }) }}
    </p>
    <div
      data-so-a-base
      class="flex items-start gap-3 p-4 text-sm rounded-xl bg-n-slate-2 text-n-slate-12"
    >
      <span
        class="i-lucide-lock size-5 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      <p class="m-0">{{ t(`${NS}.SO_A_BASE`, { nome }) }}</p>
    </div>

    <div
      v-if="estado === 'comparando'"
      data-comparando
      class="flex flex-col items-center gap-3 py-8 text-sm text-center text-n-slate-11"
    >
      <Spinner :size="24" aria-hidden="true" />
      <p role="status" class="m-0">{{ t(`${NS}.COMPARANDO`, { nome }) }}</p>
    </div>

    <AgenteErro
      v-else-if="estado === 'erro'"
      data-erro-comparar
      :titulo="tituloDoErro"
      :garantia="t(`${NS}.NADA_MUDOU`)"
      :tom="esperando ? 'ambar' : 'rubi'"
      :acao="podeTentar ? t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO') : ''"
      @acao="lerComparacao"
    />

    <ol
      v-else
      data-comparacao
      :aria-label="t(`${NS}.LISTA`)"
      class="flex flex-col gap-4 p-0 m-0 list-none"
    >
      <li
        v-for="(item, indice) in perguntas"
        :key="indice"
        data-pergunta-comparada
        class="flex flex-col gap-3 p-4 rounded-2xl ring-1 ring-inset ring-n-weak"
      >
        <p
          class="flex items-start gap-2 m-0 text-sm font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-message-circle-question size-4 shrink-0 mt-0.5 text-n-slate-11"
            aria-hidden="true"
          />
          <span class="relative">
            <span class="sr-only">{{ t(`${NS}.CLIENTE_PERGUNTA`) }}</span>
            {{ item.pergunta }}
          </span>
        </p>
        <div class="grid gap-2 sm:grid-cols-2">
          <div
            data-resposta="hoje"
            class="flex flex-col gap-1 p-3 rounded-xl bg-n-slate-2"
          >
            <span class="text-xs font-semibold text-n-slate-11">
              {{ t(`${NS}.HOJE`, { base: rotuloHoje }) }}
            </span>
            <p class="m-0 text-sm text-n-slate-12">
              {{ resposta(item.hoje, item.hoje_equipe) }}
            </p>
          </div>
          <div
            data-resposta="nova"
            class="flex flex-col gap-1 p-3 rounded-xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
          >
            <span class="text-xs font-semibold text-n-blue-11">
              {{ t(`${NS}.NOVA`, { base: rotuloNova }) }}
            </span>
            <p class="m-0 text-sm text-n-slate-12">
              {{ resposta(item.nova, item.nova_equipe) }}
            </p>
          </div>
        </div>
      </li>
    </ol>
    <div v-if="estado === 'pronto'" class="relative">
      <p data-respostas-prontas role="status" class="sr-only">
        {{ t(`${NS}.PRONTAS`, { nome }) }}
      </p>
    </div>
    <p v-if="estado === 'pronto'" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.NOTA`, { nome }) }}
    </p>

    <template #rodape>
      <p
        v-if="falhouAtualizar"
        data-erro-atualizar
        role="alert"
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ t(`${NS}.ERRO_ATUALIZAR`) }}
      </p>
      <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <AgenteBotao
          data-agora-nao
          variante="contorno"
          :desabilitado="atualizando"
          @click="emit('fechar')"
        >
          {{ t(`${NS}.AGORA_NAO`) }}
        </AgenteBotao>
        <AgenteBotao
          v-if="estado === 'pronto'"
          data-confirmar-base
          :carregando="atualizando"
          :rotulo-carregando="t(`${NS}.ATUALIZANDO`)"
          @click="confirmar"
        >
          {{ t('AGENTS.JORNADA.PAGINA.BASE.ATUALIZAR') }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>

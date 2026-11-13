<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import AprovacoesAPI from 'dashboard/api/autonomia/aprovacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import CartaoDoPedido from '../livre/passosNovos/CartaoDoPedido.vue';
import { P } from '../livre/passosNovos/passosNovos';

// #2931 — "Pedidos de aprovação": o que as automações esperam de quem olha. A
// pergunta vem com os valores lidos pelas permissões desta pessoa (o valor de
// venda só para quem vê valores). Vindo do sino (`?pedido=`), o pedido abre
// primeiro, mesmo já respondido ou encerrado.
const A = `${P}.APROVACOES`;
const { t, locale } = useI18n();
const route = useRoute();

const estado = ref('carregando');
const pedidos = ref([]);
const avulso = ref(null);
const naoAchou = ref(false);
const enviando = ref(null);
const erros = ref({});

const idDoSino = computed(() => Number(route.query.pedido) || null);
const lista = computed(() => {
  const abertos = pedidos.value.filter(item => item.id !== avulso.value?.id);
  return avulso.value ? [avulso.value, ...abertos] : abertos;
});

const quando = iso =>
  new Date(iso).toLocaleString(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  });
const linhaDoPrazo = pedido =>
  pedido.ate
    ? t(`${P}.PEDIDO.PRAZO_ATE`, {
        quando: quando(pedido.ate),
        automacao: pedido.automacao.nome,
      })
    : '';
const estadoDoCartao = pedido =>
  pedido.estado === 'aberto' ? null : pedido.estado;
const porNome = pedido =>
  pedido.decisao && !pedido.decisao.por_mim ? pedido.decisao.por_nome : '';
const linkDaConversa = pedido =>
  frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: pedido.conversa_id,
    })
  );

const carregarAvulso = async () => {
  naoAchou.value = false;
  avulso.value = null;
  if (!idDoSino.value) return;
  try {
    const { data } = await AprovacoesAPI.show(idDoSino.value);
    avulso.value = data;
  } catch {
    naoAchou.value = true;
  }
};

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const [{ data }] = await Promise.all([
      AprovacoesAPI.get(),
      carregarAvulso(),
    ]);
    pedidos.value = data.pedidos;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

const trocar = novo => {
  pedidos.value = pedidos.value.map(item =>
    item.id === novo.id ? novo : item
  );
  if (avulso.value?.id === novo.id) avulso.value = novo;
  if (!avulso.value && !pedidos.value.some(item => item.id === novo.id))
    avulso.value = novo;
};

const responder = async (pedido, aprovado, motivo = '') => {
  enviando.value = pedido.id;
  erros.value = { ...erros.value, [pedido.id]: '' };
  try {
    const { data } = await AprovacoesAPI.responder(pedido.id, {
      aprovado,
      motivo,
    });
    trocar(data);
  } catch (error) {
    const resposta = error?.response?.data;
    if (resposta?.pedido) trocar(resposta.pedido);
    erros.value = {
      ...erros.value,
      [pedido.id]: resposta?.error || t(`${A}.NAO_RESPONDEU`),
    };
  } finally {
    enviando.value = null;
  }
};

onMounted(carregar);
watch(idDoSino, carregarAvulso);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-5xl gap-8 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <header class="flex flex-col gap-2">
          <h1 class="mb-0 text-2xl font-semibold text-n-slate-12">
            {{ $t(`${A}.TITULO`) }}
          </h1>
          <p class="mb-0 text-base text-n-slate-11">
            {{ $t(`${A}.SUBTITULO`) }}
          </p>
        </header>

        <div
          v-if="estado === 'carregando'"
          data-carregando
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t(`${A}.CARREGANDO`) }}</span>
          <div class="h-48 rounded-2xl bg-n-alpha-2 animate-pulse" />
        </div>

        <div
          v-else-if="estado === 'erro'"
          data-erro
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="mb-0 text-base text-n-slate-12">{{ $t(`${A}.ERRO`) }}</p>
          <Button
            :label="$t(`${A}.TENTAR_DE_NOVO`)"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <template v-else>
          <p
            v-if="naoAchou"
            data-nao-achou
            role="status"
            class="p-5 mb-0 text-base rounded-2xl bg-n-solid-2 text-n-slate-12"
          >
            {{ $t(`${A}.NAO_ACHOU`) }}
          </p>

          <p
            v-if="!lista.length"
            data-vazio
            class="px-6 py-16 mb-0 text-xl font-semibold text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            {{ $t(`${A}.VAZIO`) }}
          </p>

          <article
            v-for="pedido in lista"
            :key="pedido.id"
            data-pedido-real
            class="flex flex-col gap-4 p-5 border md:p-6 rounded-3xl border-n-weak bg-n-solid-1"
          >
            <CartaoDoPedido
              :pergunta="pedido.pergunta"
              :linha-do-prazo="linhaDoPrazo(pedido)"
              :card="pedido.card || null"
              :com-valor="pedido.card?.value_cents !== undefined"
              :estado="estadoDoCartao(pedido)"
              :por-nome="porNome(pedido)"
              :motivo-dito="pedido.decisao?.motivo || ''"
              :enviando="enviando === pedido.id"
              @aprovar="responder(pedido, true)"
              @recusar="motivo => responder(pedido, false, motivo)"
            />
            <p
              v-if="erros[pedido.id]"
              data-pedido-erro
              role="alert"
              class="mb-0 text-sm text-n-ruby-11"
            >
              {{ erros[pedido.id] }}
            </p>
            <a
              v-if="pedido.conversa_id"
              data-pedido-conversa
              :href="linkDaConversa(pedido)"
              class="inline-flex items-center self-start gap-1.5 text-sm font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            >
              <span class="i-lucide-message-circle size-4" aria-hidden="true" />
              {{ $t(`${P}.PEDIDO.ABRIR_CONVERSA`) }}
            </a>
          </article>
        </template>
      </div>
    </main>
  </section>
</template>

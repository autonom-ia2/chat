<script setup>
// Gaveta "Escolher produtos" da Nova campanha (#1418): uma ação só — escolher
// do catálogo do WhatsApp da caixa. Busca pelo nome, foto e preço de cada um.
// Um produto: tocar escolhe (botão comum: escolher já fecha a gaveta). Vários ou carrossel: tocar marca, na ordem em que
// vão (o número aparece na foto); "Usar estes produtos" confirma. Esgotado
// aparece apagado, com o motivo.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import api from '../api/modelosWhatsapp';

const props = defineProps({
  caixa: { type: [Number, String], required: true },
  // { tipo: 'um' | 'varios' | 'carrossel', minimo, maximo }
  pedido: { type: Object, required: true },
  escolhidos: { type: Array, default: () => [] },
});
const emit = defineEmits(['usar', 'fechar']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.PONTE.PRODUTOS';

const umSo = computed(() => props.pedido.tipo === 'um');
const busca = ref('');
const produtos = ref([]);
const catalogo = ref(null);
const estado = ref('carregando');
// Cursor da próxima página da Meta ('' = acabou).
const depois = ref('');
const marcados = ref([...props.escolhidos]);

// `mais`: soma a próxima página à lista ("Ver mais produtos"). Só vale a
// resposta do último pedido: uma busca antiga que chega depois é descartada.
let ultimoPedido = 0;
const carregar = async ({ mais = false } = {}) => {
  ultimoPedido += 1;
  const este = ultimoPedido;
  estado.value = 'carregando';
  if (!mais) depois.value = '';
  try {
    const pagina = await api.listarProdutos(props.caixa, {
      busca: busca.value,
      depois: mais ? depois.value : '',
    });
    if (este !== ultimoPedido) return;
    produtos.value = mais
      ? [...produtos.value, ...pagina.produtos]
      : pagina.produtos;
    depois.value = pagina.depois;
    estado.value = 'pronto';
  } catch {
    if (este === ultimoPedido) estado.value = 'erro';
  }
};
const buscarDepois = useDebounceFn(() => carregar(), 300);
watch(busca, buscarDepois);

onMounted(async () => {
  catalogo.value = await api.obterCatalogo(props.caixa).catch(() => null);
  carregar();
});

const posicao = produto =>
  marcados.value.findIndex(item => item.id === produto.id);
const noMaximo = computed(() => marcados.value.length >= props.pedido.maximo);
const bloqueado = produto =>
  !produto.disponivel ||
  (!umSo.value && posicao(produto) < 0 && noMaximo.value);

const tocar = produto => {
  if (!produto.disponivel) return;
  if (umSo.value) {
    emit('usar', [produto]);
    return;
  }
  const indice = posicao(produto);
  if (indice >= 0) {
    marcados.value = marcados.value.filter(item => item.id !== produto.id);
  } else if (!noMaximo.value) {
    marcados.value = [...marcados.value, produto];
  }
};

const faltam = computed(() =>
  Math.max(props.pedido.minimo - marcados.value.length, 0)
);
const contagem = computed(() => {
  if (faltam.value) {
    return t(`${NS}.FALTAM`, { n: faltam.value }, faltam.value);
  }
  return t(
    `${NS}.ESCOLHIDOS`,
    { n: marcados.value.length, maximo: props.pedido.maximo },
    marcados.value.length
  );
});
</script>

<template>
  <AgenteGaveta
    :titulo="t(`${NS}.GAVETA.${pedido.tipo}`)"
    @fechar="emit('fechar')"
  >
    <div data-gaveta-produtos class="flex flex-col gap-4">
      <p v-if="catalogo" class="m-0 text-sm text-n-slate-11">
        {{
          t(
            `${NS}.DO_CATALOGO`,
            { nome: catalogo.nome, n: catalogo.produtos },
            catalogo.produtos
          )
        }}
      </p>
      <Input
        v-model="busca"
        :label="t(`${NS}.BUSCA`)"
        :placeholder="t(`${NS}.BUSCA_EXEMPLO`)"
        custom-input-class="!h-11"
        data-busca-produto
      />

      <p
        v-if="estado === 'carregando' && !produtos.length"
        class="m-0 text-sm text-n-slate-11"
        role="status"
      >
        {{ t(`${NS}.CARREGANDO`) }}
      </p>
      <p
        v-else-if="estado === 'erro'"
        role="alert"
        class="flex flex-wrap items-center gap-2 m-0 text-sm text-n-ruby-11"
      >
        {{ t(`${NS}.ERRO`) }}
        <Button
          :label="t('MODELOS_WHATSAPP.TENTAR_DE_NOVO')"
          variant="link"
          size="sm"
          @click="carregar()"
        />
      </p>
      <p
        v-else-if="!produtos.length"
        data-sem-produto
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.NENHUM`) }}
      </p>

      <ul
        v-else
        class="grid grid-cols-2 gap-3 p-0 m-0 list-none sm:grid-cols-3"
        role="group"
        :aria-label="t(`${NS}.GAVETA.${pedido.tipo}`)"
      >
        <li v-for="produto in produtos" :key="produto.id">
          <button
            type="button"
            :role="umSo ? undefined : 'checkbox'"
            :aria-checked="umSo ? undefined : posicao(produto) >= 0"
            :aria-pressed="umSo ? posicao(produto) >= 0 : undefined"
            :aria-disabled="bloqueado(produto)"
            :data-produto="produto.id"
            class="relative flex flex-col w-full h-full overflow-hidden text-start rounded-xl ring-1 ring-inset bg-n-solid-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="[
              posicao(produto) >= 0
                ? 'ring-2 ring-n-blue-9'
                : 'ring-n-weak hover:ring-n-blue-6',
              bloqueado(produto) ? 'opacity-50 cursor-not-allowed' : '',
            ]"
            @click="tocar(produto)"
          >
            <span class="block aspect-square bg-n-slate-3">
              <img
                v-if="produto.foto"
                :src="produto.foto"
                alt=""
                class="object-cover size-full"
              />
            </span>
            <span
              v-if="posicao(produto) >= 0"
              class="absolute grid text-sm font-semibold text-white rounded-full shadow top-2 ltr:right-2 rtl:left-2 place-items-center size-7 bg-n-blue-9"
              aria-hidden="true"
            >
              <span v-if="umSo" class="i-lucide-check size-4" />
              <template v-else>{{ posicao(produto) + 1 }}</template>
            </span>
            <span class="flex flex-col gap-0.5 p-2.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ produto.nome }}
              </span>
              <span class="text-sm text-n-slate-11">{{ produto.preco }}</span>
              <span
                v-if="!produto.disponivel"
                class="text-xs font-medium text-n-ruby-11"
              >
                {{ t(`${NS}.ESGOTADO`) }}
              </span>
            </span>
          </button>
        </li>
      </ul>
      <Button
        v-if="depois && produtos.length"
        :label="t(`${NS}.VER_MAIS`)"
        :is-loading="estado === 'carregando'"
        variant="outline"
        color="slate"
        class="self-center"
        data-ver-mais-produtos
        @click="carregar({ mais: true })"
      />
    </div>

    <template v-if="!umSo" #rodape>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span class="text-sm text-n-slate-12" aria-live="polite">
          {{ contagem }}
        </span>
        <Button
          :label="t(`${NS}.USAR`)"
          :disabled="faltam > 0"
          data-usar-produtos
          @click="emit('usar', marcados)"
        />
      </div>
    </template>
  </AgenteGaveta>
</template>

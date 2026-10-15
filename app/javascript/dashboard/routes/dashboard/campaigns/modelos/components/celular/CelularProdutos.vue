<script setup>
// Produtos do catálogo no celular (#1418), como o WhatsApp do cliente mostra:
//   um        → foto, nome e preço do produto no topo do balão;
//   varios    → a foto do primeiro produto e o título no topo; ao tocar em
//               "Ver itens" o cliente vê a lista (mostrada embaixo, em cinza);
//   carrossel → um cartão por produto, lado a lado, com o botão do modelo.
// `parte`: 'topo' (dentro do balão) ou 'depois' (embaixo do balão e do botão).
// Sem produtos escolhidos (tela de Modelos), um produto de exemplo.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // conteudo.produtos: { tipo, titulo, rodape, botao: { tipo, texto } }
  produtos: { type: Object, required: true },
  // Os escolhidos na campanha: [{ id, nome, preco (texto), foto }].
  escolhidos: { type: Array, default: () => [] },
  parte: { type: String, required: true },
});

const { t } = useI18n();

const EXEMPLOS_NO_CARROSSEL = 2;
const lista = computed(() => {
  if (props.escolhidos.length) return props.escolhidos;
  const exemplo = { id: '', nome: '', preco: '', foto: '' };
  return props.produtos.tipo === 'carrossel'
    ? Array.from({ length: EXEMPLOS_NO_CARROSSEL }, () => exemplo)
    : [exemplo];
});
const primeiro = computed(() => lista.value[0]);

// O preço como o catálogo mostra (texto da Meta).
const preco = produto => produto.preco || '';
const nome = produto =>
  produto.nome || t('MODELOS_WHATSAPP.CELULAR.PRODUTOS.EXEMPLO');

// Foto que não abre volta ao ícone.
const falhou = ref({});
const foto = (produto, indice) =>
  falhou.value[indice] ? '' : produto.foto || '';
const marcarFalha = indice => {
  falhou.value = { ...falhou.value, [indice]: true };
};
</script>

<template>
  <!-- Um produto: foto grande, nome e preço no topo do balão. -->
  <div
    v-if="parte === 'topo' && produtos.tipo === 'um'"
    data-celular-produto
    class="flex flex-col gap-1.5"
  >
    <div class="overflow-hidden rounded-lg h-36 bg-n-slate-4">
      <img
        v-if="foto(primeiro, 0)"
        :src="foto(primeiro, 0)"
        alt=""
        class="object-cover size-full"
        @error="marcarFalha(0)"
      />
      <span
        v-else
        class="grid size-full place-items-center text-n-slate-11"
        aria-hidden="true"
      >
        <span class="i-lucide-shopping-bag size-8" />
      </span>
    </div>
    <span class="flex flex-col px-1">
      <strong class="text-sm text-n-slate-12">{{ nome(primeiro) }}</strong>
      <span v-if="preco(primeiro)" class="text-xs text-n-slate-11">
        {{ preco(primeiro) }}
      </span>
    </span>
  </div>

  <!-- Vários: a foto do primeiro produto e o título do modelo. -->
  <div
    v-else-if="parte === 'topo' && produtos.tipo === 'varios'"
    data-celular-produtos-topo
    class="flex items-center gap-2.5 p-1.5 rounded-lg bg-n-slate-3"
  >
    <span class="overflow-hidden rounded-md size-12 shrink-0 bg-n-slate-4">
      <img
        v-if="foto(primeiro, 0)"
        :src="foto(primeiro, 0)"
        alt=""
        class="object-cover size-full"
        @error="marcarFalha(0)"
      />
      <span
        v-else
        class="grid size-full place-items-center text-n-slate-11"
        aria-hidden="true"
      >
        <span class="i-lucide-shopping-bag size-5" />
      </span>
    </span>
    <span class="flex flex-col min-w-0">
      <strong class="text-sm leading-snug line-clamp-2 text-n-slate-12">
        {{ produtos.titulo || $t('MODELOS_WHATSAPP.CELULAR.PRODUTOS.LISTA') }}
      </strong>
      <span class="text-xs text-n-slate-11">
        {{
          $t(
            'MODELOS_WHATSAPP.CELULAR.PRODUTOS.ITENS',
            { n: escolhidos.length || 1 },
            escolhidos.length || 1
          )
        }}
      </span>
    </span>
  </div>

  <!-- Vários: o que o cliente vê ao tocar no botão. -->
  <div
    v-else-if="parte === 'depois' && produtos.tipo === 'varios'"
    data-celular-produtos-lista
    class="flex flex-col gap-1.5 p-2 mt-1 rounded-xl bg-n-alpha-2 max-w-[92%]"
  >
    <span class="px-1 text-[0.6875rem] text-n-slate-11">
      {{
        $t('MODELOS_WHATSAPP.CELULAR.PRODUTOS.AO_TOCAR', {
          botao: produtos.botao.texto,
        })
      }}
    </span>
    <span
      v-for="(produto, indice) in lista"
      :key="indice"
      class="flex items-center gap-2 p-1.5 rounded-lg bg-n-solid-1"
    >
      <span class="overflow-hidden rounded size-9 shrink-0 bg-n-slate-4">
        <img
          v-if="foto(produto, indice)"
          :src="foto(produto, indice)"
          alt=""
          class="object-cover size-full"
          @error="marcarFalha(indice)"
        />
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-xs truncate text-n-slate-12">{{
          nome(produto)
        }}</span>
        <span v-if="preco(produto)" class="text-[0.6875rem] text-n-slate-11">
          {{ preco(produto) }}
        </span>
      </span>
    </span>
  </div>

  <!-- Carrossel: um cartão por produto. -->
  <ul
    v-else-if="parte === 'depois' && produtos.tipo === 'carrossel'"
    data-celular-produtos-cartoes
    class="flex gap-2 p-0 pb-2 m-0 overflow-x-auto list-none snap-x snap-mandatory"
    :aria-label="$t('MODELOS_WHATSAPP.CELULAR.CARTOES')"
  >
    <li
      v-for="(produto, indice) in lista"
      :key="indice"
      class="flex flex-col shrink-0 w-[10.5rem] overflow-hidden shadow-sm snap-start rounded-xl bg-n-solid-1"
    >
      <span class="h-28 bg-n-slate-4">
        <img
          v-if="foto(produto, indice)"
          :src="foto(produto, indice)"
          alt=""
          class="object-cover size-full"
          @error="marcarFalha(indice)"
        />
        <span
          v-else
          class="grid size-full place-items-center text-n-slate-11"
          aria-hidden="true"
        >
          <span class="i-lucide-shopping-bag size-7" />
        </span>
      </span>
      <span class="flex flex-col px-2.5 py-2">
        <strong class="text-xs text-n-slate-12 truncate">{{
          nome(produto)
        }}</strong>
        <span v-if="preco(produto)" class="text-[0.6875rem] text-n-slate-11">
          {{ preco(produto) }}
        </span>
      </span>
      <span
        class="flex items-center justify-center gap-1 py-1.5 mt-auto text-xs font-medium border-t border-n-weak text-n-blue-11"
      >
        <span
          class="size-3.5"
          :class="
            produtos.botao.tipo === 'site'
              ? 'i-lucide-external-link'
              : 'i-lucide-shopping-bag'
          "
          aria-hidden="true"
        />
        {{
          produtos.botao.texto || $t('MODELOS_WHATSAPP.CELULAR.BOTAO_SEM_TEXTO')
        }}
      </span>
    </li>
  </ul>
</template>

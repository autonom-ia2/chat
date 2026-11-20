<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { motivosEmPalavras } from '../../lista/motivosEmPalavras';
import MenuMaisAcoes from './MenuMaisAcoes.vue';

// #2894 — a barra que aparece embaixo ao marcar alguém: "12 marcadas", a ação
// principal (Mandar mensagem) e as outras. Em 390 px só o principal fica à
// vista; Criar cards e Etiqueta vão para o menu "⋯" junto com Apagar.
// "Criar cards", "Etiqueta" e "Apagar" só aparecem para quem pode (quem decide
// é a página). Sem nenhuma das três, fica só "Mandar mensagem", sem o "⋯".
// #2970 — o que ainda não é de verdade não aparece: "Mandar mensagem" daqui só
// simula, então só existe com `podeMandarMensagem` (a página liga na
// demonstração). Sem ele a barra não fala de quem recebe, fica numa linha só no
// celular ("N marcadas", "⋯" e ×) e, de `sm` para cima, mostra Criar cards e
// Etiqueta lado a lado, sem botão preenchido.
// #3078 — quando "Apagar" é a única ação (a aba Empresas, ou quem só pode
// apagar), ele fica à vista como botão: ninguém abre um menu para uma escolha.
const props = defineProps({
  quantas: { type: Number, required: true },
  // A conta de quem recebe (`contaDaMensagem`); sem ela, só "N marcadas".
  conta: { type: Object, default: null },
  podeMandarMensagem: { type: Boolean, default: false },
  podeCriarCards: { type: Boolean, default: true },
  podeEtiquetar: { type: Boolean, default: true },
  podeApagar: { type: Boolean, default: true },
});
const emit = defineEmits([
  'mandarMensagem',
  'criarCards',
  'etiqueta',
  'apagar',
  'fechar',
]);

const { t } = useI18n();

const aoEscolherNoMenu = id => {
  const comandos = {
    criarCards: () => emit('criarCards'),
    etiqueta: () => emit('etiqueta'),
    apagar: () => emit('apagar'),
  };
  comandos[id]?.();
};

// "3 marcadas · 2 vão receber · 1 pediu para não receber": só quando alguém fica
// de fora. Com todo mundo recebendo, fica só "3 marcadas".
const frase = computed(() => {
  const marcadas = t(
    'RELACIONAMENTOS.LISTA.MARCADAS.QUANTAS',
    { count: props.quantas },
    props.quantas
  );
  const conta = props.conta;
  if (!props.podeMandarMensagem || !conta?.fora) return marcadas;
  const receber = conta.recebem
    ? [
        t(
          'RELACIONAMENTOS.LISTA.MARCADAS.VAO_RECEBER',
          { count: conta.recebem },
          conta.recebem
        ),
      ]
    : [];
  return [marcadas, ...receber, ...motivosEmPalavras(t, conta)].join(' · ');
});

const itensDoMenu = computed(() =>
  [
    {
      id: 'criarCards',
      rotulo: t('RELACIONAMENTOS.LISTA.BARRA.CRIAR_CARDS'),
      icone: 'i-lucide-kanban',
      soNoCelular: true,
      pode: props.podeCriarCards,
    },
    {
      id: 'etiqueta',
      rotulo: t('RELACIONAMENTOS.LISTA.BARRA.ETIQUETA'),
      icone: 'i-lucide-tag',
      soNoCelular: true,
      pode: props.podeEtiquetar,
    },
    {
      id: 'apagar',
      rotulo: t('RELACIONAMENTOS.LISTA.BARRA.APAGAR'),
      icone: 'i-lucide-trash-2',
      destrutivo: true,
      pode: props.podeApagar,
    },
  ].filter(item => item.pode)
);
// #3078 — com "Apagar" sozinho (a aba Empresas) tudo cabe numa linha também no
// celular: "2 marcadas", "Apagar" e o "×" encostado no fim. No celular a barra
// abre espaço à esquerda para o botão do menu do app (ListaPage), então o
// espaço entre eles e a folga do "Apagar" e do "×" encolhem (o "×" segue com
// 44 px). Com três dígitos marcados o "×" desce para a linha de baixo.
const soApagar = computed(
  () =>
    props.podeApagar &&
    !props.podeMandarMensagem &&
    !props.podeCriarCards &&
    !props.podeEtiquetar
);
// Sem "Apagar", o que sobra no menu só existe no celular: de `sm` para cima o
// "⋯" abriria vazio, então some junto.
const menuSoNoCelular = computed(() =>
  itensDoMenu.value.every(item => item.soNoCelular)
);
</script>

<template>
  <div
    data-relacionamentos="barra"
    role="region"
    :aria-label="t('RELACIONAMENTOS.LISTA.BARRA.ROTULO')"
    class="flex flex-wrap items-center p-3 shadow-xl rounded-2xl bg-n-solid-1 ring-1 ring-n-weak sm:gap-3 sm:px-4"
    :class="soApagar ? 'gap-1.5' : 'gap-2'"
  >
    <p
      aria-live="polite"
      class="order-1 m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:order-1 sm:me-1 sm:flex-none"
      :class="soApagar ? 'whitespace-nowrap' : 'flex-1'"
    >
      {{ frase }}
    </p>
    <Button
      v-if="podeMandarMensagem"
      size="lg"
      class="order-3 flex-1 min-w-0 whitespace-nowrap sm:order-2 sm:flex-none"
      icon="i-lucide-send"
      data-relacionamentos="mandar-mensagem"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.MANDAR_MENSAGEM')"
      @click="emit('mandarMensagem')"
    />
    <Button
      v-if="podeCriarCards"
      slate
      faded
      size="lg"
      class="hidden sm:order-3 sm:inline-flex"
      icon="i-lucide-kanban"
      data-relacionamentos="criar-cards"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.CRIAR_CARDS')"
      @click="emit('criarCards')"
    />
    <Button
      v-if="podeEtiquetar"
      slate
      faded
      size="lg"
      class="hidden sm:order-4 sm:inline-flex"
      icon="i-lucide-tag"
      data-relacionamentos="etiqueta"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.ETIQUETA')"
      @click="emit('etiqueta')"
    />
    <Button
      v-if="soApagar"
      slate
      faded
      size="lg"
      class="order-2 sm:order-5 !text-n-ruby-11 max-sm:!px-3"
      icon="i-lucide-trash-2"
      data-relacionamentos="apagar"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.APAGAR')"
      @click="emit('apagar')"
    />
    <MenuMaisAcoes
      v-else-if="itensDoMenu.length"
      class="order-2 sm:order-5"
      :class="{ 'sm:hidden': menuSoNoCelular }"
      :itens="itensDoMenu"
      @escolher="aoEscolherNoMenu"
    />
    <Button
      ghost
      slate
      size="lg"
      class="order-2 sm:order-6"
      :class="soApagar ? 'ms-auto max-sm:!w-11' : 'sm:ms-auto'"
      icon="i-lucide-x"
      :aria-label="t('RELACIONAMENTOS.LISTA.MARCADAS.DESMARCAR')"
      @click="emit('fechar')"
    />
    <!-- Celular: quebra a linha entre "marcadas ⋯ ×" e "Mandar mensagem", que
         fica com a linha inteira (ao lado do "⋯" o texto saía cortado). Sem
         "Mandar mensagem" não há segunda linha. -->
    <span
      v-if="podeMandarMensagem"
      data-quebra-de-linha
      class="order-2 h-0 basis-full sm:hidden"
      aria-hidden="true"
    />
  </div>
</template>

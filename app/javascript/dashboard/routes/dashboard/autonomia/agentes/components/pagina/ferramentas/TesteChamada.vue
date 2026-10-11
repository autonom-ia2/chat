<script setup>
import { computed, h } from 'vue';

// #1301 (protótipo F07) — "O que vai ser chamado": método, endereço com os valores trocados como o
// backend troca, cabeçalhos (segredo mascarado e os automáticos) e o corpo. O trecho que entra cru
// com espaço no endereço fica marcado: é ali que a chamada quebra. Quebra linha, sem rolagem lateral.
// Texto montado por funções (h), para o espaço da formatação do template não entrar no endereço.
const props = defineProps({
  chamada: { type: Object, required: true },
});

const Endereco = ({ pedacos }) =>
  pedacos.map(pedaco =>
    pedaco.ruim
      ? h(
          'mark',
          {
            'data-trecho-ruim': '',
            class: 'px-0.5 rounded bg-n-amber-4 text-n-slate-12',
          },
          pedaco.texto
        )
      : pedaco.texto
  );
Endereco.props = ['pedacos'];

const Linhas = ({ linhas }) =>
  linhas.map(linha => h('span', { class: 'block whitespace-pre-wrap' }, linha));
Linhas.props = ['linhas'];

const metodo = computed(() => `${props.chamada.metodo} `);
const linhasDoCorpo = computed(() => props.chamada.corpo.split('\n'));
</script>

<template>
  <div
    data-previa
    class="flex flex-col gap-2 font-mono text-sm break-words [overflow-wrap:anywhere]"
  >
    <p class="m-0 text-n-slate-12">
      <span class="font-semibold whitespace-pre">{{ metodo }}</span>
      <Endereco :pedacos="chamada.endereco" />
    </p>
    <p class="m-0 text-n-slate-11">
      <Linhas :linhas="chamada.cabecalhos" />
    </p>
    <p v-if="chamada.corpo" class="m-0 text-n-slate-12">
      <Linhas :linhas="linhasDoCorpo" />
    </p>
  </div>
</template>

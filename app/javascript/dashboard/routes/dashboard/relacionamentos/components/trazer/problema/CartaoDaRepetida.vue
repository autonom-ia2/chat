<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { partesDoEmail } from '../../../trazer/emailEmPartes';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';
import MolduraDoCartao from './MolduraDoCartao.vue';

// #2896, Fatia 2 — o cartão da pessoa que aparece em duas linhas da planilha:
// as duas lado a lado, cada uma com o que a distingue da outra, e a pessoa
// escolhe com qual fica. Não tem campo nem "Salvar": a escolha já salva.
// O nome acessível de cada escolha é o conteúdo dela (o telefone, o e-mail, a
// linha e "Ficar com esta"): um aria-label por cima esconderia do leitor de
// tela justamente o que distingue uma linha da outra.
// As escolhas ficam desligadas enquanto a escrita não acaba: depois de uma
// recusa, o foco espera elas religarem (`ocupado`) para voltar à primeira.
const props = defineProps({
  problema: { type: Object, required: true },
  frases: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['guardar', 'deixarDeFora']);

const { t } = useI18n();

const moldura = ref(null);
const idDoErro = useId();
const { erro } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: '',
  raiz: moldura,
  ocupado: () => props.ocupado,
});

// O título de cada linha é o que a distingue da outra: o telefone ou, sem
// telefone, o e-mail (que só quebra no "@"); o e-mail de quem tem telefone vem
// logo abaixo. Sem os dados da linha, o título diz só qual linha é.
const opcaoDa = linha => {
  const dados = props.problema.duplicadas?.find(item => item.linha === linha);
  if (!dados) {
    const ficarCom = t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM', { linha });
    return { linha, titulo: [ficarCom], email: [] };
  }
  const email = dados.email ? partesDoEmail(dados.email) : [];
  if (dados.telefone) return { linha, titulo: [dados.telefone], email };
  const semTelefone = [t('RELACIONAMENTOS_TRAZER.PRECISAM.SEM_TELEFONE')];
  return { linha, titulo: email.length ? email : semTelefone, email: [] };
};
const opcoes = computed(() =>
  [props.problema.outraLinha, props.problema.linha].map(opcaoDa)
);
</script>

<template>
  <MolduraDoCartao
    ref="moldura"
    :linha="problema.linha"
    :frases="frases"
    :erro="erro"
    :id-do-erro="idDoErro"
    :ocupado="ocupado"
    @deixar-de-fora="linha => emit('deixarDeFora', linha)"
  >
    <div class="grid gap-3 sm:grid-cols-2">
      <button
        v-for="opcao in opcoes"
        :key="opcao.linha"
        type="button"
        :data-opcao="opcao.linha"
        class="flex flex-col items-start w-full gap-1 p-4 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:enabled:bg-n-alpha-2 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :disabled="ocupado"
        @click="emit('guardar', problema.linha, opcao.linha)"
      >
        <span
          data-relacionamentos="titulo-do-cartao"
          class="text-base font-medium break-words text-n-slate-12 tabular-nums"
        >
          <template v-for="(parte, posicao) in opcao.titulo" :key="posicao">
            <wbr v-if="posicao" />{{ parte }}
          </template>
        </span>
        <span
          v-if="opcao.email.length"
          class="text-sm break-words text-n-slate-11"
        >
          <template v-for="(parte, posicao) in opcao.email" :key="posicao">
            <wbr v-if="posicao" />{{ parte }}
          </template>
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
              linha: opcao.linha,
            })
          }}
        </span>
        <span
          data-relacionamentos="ficar-com-esta"
          class="flex items-center gap-1 mt-1 text-sm font-medium text-n-blue-11"
        >
          {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM_ESTA') }}
          <span
            class="i-lucide-arrow-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </span>
      </button>
    </div>
  </MolduraDoCartao>
</template>

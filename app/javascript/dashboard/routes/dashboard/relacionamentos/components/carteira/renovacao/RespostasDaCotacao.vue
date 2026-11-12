<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { respostasEmGrupos } from '../../../carteira/cotacaoDoCard';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import DialogoDaSenhaNoAgger from '../trazer/DialogoDaSenhaNoAgger.vue';

// #2897 — o que cada seguradora respondeu à cotação, cada uma no seu grupo:
// quem já deu preço (com "Pedir a proposta desta") e quem ainda não respondeu;
// à parte, quem não aceitou (com o motivo) e a que está sem senha no Agger
// (com "Como resolver", o mesmo caminho do Trazer). Depois do prazo, quem não
// respondeu aparece como "Não respondeu a tempo". O botão azul é um só: o da
// seguradora que o passo da vez escolheu (`escolhida`).
const props = defineProps({
  respostas: { type: Array, required: true },
  passouOPrazo: { type: Boolean, default: false },
  // A seguradora do passo da vez ('' = nenhuma).
  escolhida: { type: String, default: '' },
  // O nome da ação que está rodando ('' = nenhuma).
  ocupado: { type: String, default: '' },
});
const emit = defineEmits(['pedirProposta', 'cotarDeNovo']);

const { t } = useI18n();
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`, valores);
const ta = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.AGGER.${chave}`, valores);
const textos = useTextosDoSeguro();
const id = useId();

const grupos = computed(() => respostasEmGrupos(props.respostas));
// Quem deu preço e quem ainda não respondeu, na ordem em que chegaram.
const linhas = computed(() =>
  props.respostas.filter(
    resposta =>
      grupos.value.deram.includes(resposta) ||
      grupos.value.caladas.includes(resposta)
  )
);
const semResposta = computed(() =>
  ca(props.passouOPrazo ? 'NAO_RESPONDEU_A_TEMPO' : 'AINDA_NAO_RESPONDEU')
);
const preco = resposta =>
  ca('PRECO', {
    valor: textos.valor(resposta.valor),
    periodo: textos.periodo(resposta),
  });

const dialogo = ref(null);
const semSenha = ref('');
const comoResolver = nome => {
  semSenha.value = nome;
  dialogo.value?.abrir();
};
const cotarDeNovo = () => {
  dialogo.value?.fechar();
  emit('cotarDeNovo');
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ul
      v-if="linhas.length"
      data-carteira="respostas-da-cotacao"
      class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
    >
      <li
        v-for="resposta in linhas"
        :key="resposta.nome"
        class="flex flex-col gap-2 py-3"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-x-3">
          <span class="text-base font-medium text-n-slate-12">
            {{ resposta.nome }}
          </span>
          <span class="text-base tabular-nums text-n-slate-11">
            {{ resposta.valor === null ? semResposta : preco(resposta) }}
          </span>
        </div>
        <p v-if="resposta.semPdf" class="m-0 text-sm text-n-slate-11">
          {{ ca('SEM_PDF_DE_PROPOSTA') }}
        </p>
        <div v-else-if="resposta.valor !== null">
          <Button
            :slate="resposta.nome !== escolhida"
            :faded="resposta.nome !== escolhida"
            size="lg"
            data-carteira="pedir-proposta"
            :aria-label="ca('PEDIR_PROPOSTA_DE', { seguradora: resposta.nome })"
            :is-loading="ocupado === 'pedirProposta'"
            :label="ca('PEDIR_PROPOSTA')"
            @click="emit('pedirProposta', resposta.nome)"
          />
        </div>
      </li>
    </ul>

    <section
      v-if="grupos.recusaram.length"
      data-carteira="seguradoras-que-recusaram"
      :aria-labelledby="`${id}-recusaram`"
      class="flex flex-col gap-2"
    >
      <h4
        :id="`${id}-recusaram`"
        class="m-0 text-sm font-medium text-n-slate-11"
      >
        {{ ca('NAO_ACEITARAM') }}
      </h4>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="resposta in grupos.recusaram"
          :key="resposta.nome"
          class="flex flex-wrap items-baseline justify-between gap-x-3"
        >
          <span class="text-base font-medium text-n-slate-12">
            {{ resposta.nome }}
          </span>
          <span class="text-base text-n-slate-11">
            {{ ca(`RECUSA.${resposta.recusou.toUpperCase()}`) }}
          </span>
        </li>
      </ul>
    </section>

    <ul
      v-if="grupos.semSenha.length"
      data-carteira="seguradoras-sem-senha"
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li
        v-for="resposta in grupos.semSenha"
        :key="resposta.nome"
        class="flex flex-col items-start gap-2 p-4 border rounded-xl border-n-amber-6 bg-n-amber-2"
      >
        <p class="m-0 text-base break-words text-n-slate-12">
          {{ ca('FALTA_A_SENHA', { seguradora: resposta.nome }) }}
        </p>
        <Button
          slate
          faded
          size="lg"
          data-carteira="agger-como-resolver"
          :label="ta('COMO_RESOLVER')"
          :aria-label="ta('COMO_RESOLVER_DE', { seguradora: resposta.nome })"
          @click="comoResolver(resposta.nome)"
        />
      </li>
    </ul>

    <DialogoDaSenhaNoAgger
      ref="dialogo"
      :seguradora="semSenha"
      :texto="ca('SENHA_COMO_RESOLVER', { seguradora: semSenha })"
      :rotulo-da-acao="ca('COTAR_DE_NOVO')"
      marca-da-acao="cotar-de-novo-com-a-senha"
      :ocupado="ocupado === 'cotar'"
      @resolver="cotarDeNovo"
    />
  </div>
</template>

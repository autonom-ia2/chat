<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { custoEmTexto } from '../custoDaIa';
import { erroDaApi } from '../erroDaApi';

// #2500 F7 — no "Alterar" de um passo de IA: quanto ele custa por vez e o
// "Testar este passo". O teste é a única chamada paga fora de uma execução:
// roda em até 3 conversas que a pessoa vê, escolhidas pelo servidor, uma por
// pedido; não manda nem grava nada. O "extrair" não tem teste: gravar é o que
// ele faz. O custo só aparece para quem vê os custos da conta (financial_view).
const props = defineProps({
  passo: { type: Object, required: true },
  // O rascunho inteiro com este passo; o servidor confere como no "Salvar".
  receita: { type: Object, default: null },
  // { media, vezes } dos últimos 30 dias; ausente quando ainda não rodou.
  custo: { type: Object, default: null },
  mostraCusto: { type: Boolean, default: false },
  // O passo está completo (o mesmo que libera o "Salvar").
  pronto: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const I = 'AUTOMACAO_LIVRE.IA';
const podeTestar = useCanManage('automation_manage');

const testavel = computed(() =>
  ['decidir', 'escrever', 'resumir'].includes(props.passo.tipo)
);
const emTexto = valor => custoEmTexto(valor, t, locale.value);

const rodando = ref(false);
const conversas = ref([]);
const aviso = ref(null);
const erro = ref('');
const testou = ref(false);

// Cada teste tem um número. Trocar de passo ou fechar a tela muda o número, e o
// teste antigo para antes do próximo pedido: não chama a IA à toa nem mistura
// resultados de outro passo.
let rodada = 0;
const limpar = () => {
  rodada += 1;
  conversas.value = [];
  aviso.value = null;
  erro.value = '';
  testou.value = false;
  rodando.value = false;
};
watch(() => props.passo.id, limpar);
onBeforeUnmount(() => {
  rodada += 1;
});

const pedir = conversaId =>
  AutomacoesAPI.testarPasso({
    receita: props.receita,
    passoId: props.passo.id,
    conversaId,
  });

// A mesma conversa nunca aparece duas vezes, mesmo se o servidor repetir.
const mostrar = conversa => {
  if (conversas.value.some(item => item.conversa_id === conversa.conversa_id))
    return;
  conversas.value = [...conversas.value, conversa];
};

// Uma conversa por pedido: o 1º devolve as candidatas, e cada resultado
// aparece assim que chega.
const testar = async () => {
  limpar();
  const minha = rodada;
  const valendo = () => minha === rodada;
  rodando.value = true;
  try {
    const { data } = await pedir();
    if (!valendo()) return;
    aviso.value = data.aviso;
    mostrar(data.conversa);
    const restantes = (data.candidatas || []).filter(
      id => id !== data.conversa.conversa_id
    );
    for (let i = 0; i < restantes.length; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      const { data: seguinte } = await pedir(restantes[i]);
      if (!valendo()) return;
      mostrar(seguinte.conversa);
    }
    testou.value = true;
  } catch (e) {
    if (!valendo()) return;
    const { mensagem, problemas } = erroDaApi(e, t);
    erro.value = [mensagem, ...problemas].join(' ');
  } finally {
    if (valendo()) rodando.value = false;
  }
};

const custoDoTeste = computed(() =>
  conversas.value.reduce((soma, item) => soma + (item.custo_usd || 0), 0)
);

const MOTIVOS = {
  nada_para_ler: 'NADA_PARA_LER',
  ia_indisponivel: 'IA_INDISPONIVEL',
  ia_chave_recusada: 'CHAVE_RECUSADA',
};
// #2414 G20: o anexo que não pôde ir à IA, com a mesma frase do ensaio.
const MOTIVOS_DOS_ANEXOS = [
  'anexo_grande_demais',
  'anexo_fora_do_formato',
  'anexo_sem_leitura',
  'modelo_sem_imagem',
];
const linhaDaConversa = conversa => {
  if (MOTIVOS_DOS_ANEXOS.includes(conversa.motivo))
    return t(`${I}.ANEXOS.${conversa.motivo.toUpperCase()}`);
  if (!conversa.resultado)
    return t(`${I}.TESTAR.MOTIVOS.${MOTIVOS[conversa.motivo] || 'OUTRO'}`);
  if (props.passo.tipo !== 'decidir') return conversa.resultado.texto;
  // A IA devolve a chave; a tela mostra o nome que a pessoa deu ao caminho.
  const escolhido = (props.passo.caminhos || []).find(
    caminho => caminho.chave === conversa.resultado.caminho
  );
  return escolhido
    ? t(`${I}.TESTAR.ESCOLHEU`, { caminho: escolhido.nome })
    : t(`${I}.TESTAR.NENHUM`);
};
const nomeDaConversa = conversa =>
  conversa.nome
    ? t(`${I}.TESTAR.CONVERSA_DE`, {
        id: conversa.conversa_id,
        nome: conversa.nome,
      })
    : t(`${I}.TESTAR.CONVERSA`, { id: conversa.conversa_id });
</script>

<template>
  <section
    data-ia-testar
    class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
  >
    <p v-if="mostraCusto" data-ia-custo class="mb-0 text-sm text-n-slate-11">
      <span class="i-lucide-coins size-4 align-[-2px]" aria-hidden="true" />
      {{
        custo?.vezes
          ? $t(`${I}.CUSTO.MEDIA`, { custo: emTexto(custo.media) })
          : $t(`${I}.CUSTO.PRIMEIRA`)
      }}
    </p>

    <template v-if="testavel && podeTestar">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t(`${I}.TESTAR.DICA`) }}
      </p>
      <Button
        data-testar
        :label="rodando ? $t(`${I}.TESTAR.RODANDO`) : $t(`${I}.TESTAR.BOTAO`)"
        icon="i-lucide-flask-conical"
        faded
        class="self-start min-h-11"
        :disabled="rodando || !pronto || !receita"
        :is-loading="rodando"
        @click="testar"
      />
      <p
        v-if="erro"
        data-teste-erro
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
      <p
        v-if="aviso"
        data-teste-aviso
        role="status"
        class="px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${I}.TESTAR.AVISO.${aviso.toUpperCase()}`) }}
      </p>
      <ol
        v-if="conversas.length"
        aria-live="polite"
        class="flex flex-col gap-2 p-0 m-0 list-none"
      >
        <li
          v-for="conversa in conversas"
          :key="conversa.conversa_id"
          data-teste-conversa
          class="flex flex-col gap-1 p-3 rounded-lg bg-n-solid-1"
        >
          <span class="text-xs font-medium text-n-slate-10">
            {{ nomeDaConversa(conversa) }}
          </span>
          <span
            data-teste-resultado
            class="text-[0.9375rem] text-n-slate-12 whitespace-pre-line"
          >
            {{ linhaDaConversa(conversa) }}
          </span>
          <span
            v-if="passo.tipo === 'decidir' && conversa.resultado?.motivo"
            class="text-sm text-n-slate-11"
          >
            {{
              $t(`${I}.TESTAR.MOTIVO`, { motivo: conversa.resultado.motivo })
            }}
          </span>
        </li>
      </ol>
      <p
        v-if="testou && mostraCusto && custoDoTeste > 0"
        data-teste-custo
        class="mb-0 text-xs text-n-slate-10"
      >
        {{ $t(`${I}.TESTAR.CUSTOU`, { custo: emTexto(custoDoTeste) }) }}
      </p>
    </template>
  </section>
</template>

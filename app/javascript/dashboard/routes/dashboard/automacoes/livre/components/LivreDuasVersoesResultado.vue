<script setup>
// #3099 (F3 do épico #3095) — no Histórico da Automação livre, o resultado de
// cada passo "Mandar mensagem" que testa duas versões: o mesmo cartão do
// Resultado da campanha (ResultDuasVersoes, no jeito da automação). Os números
// vêm do servidor (GET automacoes/:id/duas_versoes); o texto de cada versão sai
// da receita salva, com os dados pelo nome do catálogo. "Ficar com esta" pede a
// chave de mudar automações e grava a versão que fica (POST …/vencedora).
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import ResultDuasVersoes from 'dashboard/components-next/CampaignResult/ResultDuasVersoes.vue';
import { fraseDoPasso, textoInteiro } from '../frases';
import { todosOsPassos } from '../receita';
import { temDuasVersoes } from '../versoesDoPasso';

const props = defineProps({
  automacaoId: { type: Number, required: true },
  // A receita da versão ativa (a que o servidor conta).
  receita: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  podeEscolher: { type: Boolean, default: false },
});

const NS = 'DUAS_VERSOES.RESULTADO';
const { t } = useI18n();
const estado = ref('carregando');
const resultados = ref([]);
const enviando = ref({});

const passos = computed(() =>
  todosOsPassos(props.receita?.passos || []).filter(temDuasVersoes)
);
const doPasso = id => passos.value.find(passo => passo.id === id);

const textoDa = (passo, numero) =>
  textoInteiro(
    numero === 1 ? passo.texto : passo.versoes.texto,
    props.catalogo,
    t
  );

const cartoes = computed(() =>
  resultados.value
    .map(resultado => ({ resultado, passo: doPasso(resultado.passo) }))
    .filter(({ passo }) => passo)
    .map(({ resultado, passo }) => ({
      id: passo.id,
      frase: fraseDoPasso(passo, props.catalogo, t),
      teste: {
        ...resultado,
        versoes: resultado.versoes.map(versao => ({
          ...versao,
          texto: textoDa(passo, versao.numero),
        })),
      },
    }))
);

const carregar = async () => {
  if (!passos.value.length) return;
  estado.value = 'carregando';
  try {
    const { data } = await AutomacoesAPI.duasVersoes(props.automacaoId);
    resultados.value = data.passos;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

const trocar = novo => {
  resultados.value = resultados.value.map(resultado =>
    resultado.passo === novo.passo ? novo : resultado
  );
};

const escolher = async (passoId, versao) => {
  if (enviando.value[passoId]) return;
  enviando.value = { ...enviando.value, [passoId]: versao };
  try {
    const { data } = await AutomacoesAPI.escolherVersao(
      props.automacaoId,
      passoId,
      versao
    );
    trocar(data);
  } catch (error) {
    // 422: outra pessoa (ou o sistema, na hora marcada) já escolheu. Recarrega e mostra qual foi.
    const jaEscolhida = error?.response?.status === 422;
    useAlert(
      t(
        jaEscolhida
          ? `${NS}.AUTOMACAO.JA_ESCOLHIDA`
          : `${NS}.AUTOMACAO.ERRO_ESCOLHER`
      )
    );
    if (jaEscolhida) carregar();
  } finally {
    const { [passoId]: _feito, ...resto } = enviando.value;
    enviando.value = resto;
  }
};

watch(
  () => [props.automacaoId, props.receita],
  () => carregar()
);
onMounted(() => carregar());
</script>

<template>
  <div
    :class="passos.length ? 'flex flex-col gap-4' : 'hidden'"
    data-duas-versoes-da-automacao
  >
    <template v-if="passos.length">
      <ResultDuasVersoes
        v-if="estado !== 'pronto'"
        :teste="null"
        na-automacao
        :carregando="estado === 'carregando'"
        @recarregar="carregar"
      />
      <template v-else>
        <div
          v-for="cartao in cartoes"
          :key="cartao.id"
          class="flex flex-col gap-2"
          :data-passo-com-versoes="cartao.id"
        >
          <p
            v-if="cartoes.length > 1"
            class="m-0 text-sm font-medium text-n-slate-11"
          >
            {{ t(`${NS}.AUTOMACAO.PASSO`, { frase: cartao.frase }) }}
          </p>
          <ResultDuasVersoes
            :teste="cartao.teste"
            na-automacao
            :pode-escolher="podeEscolher"
            :enviando="enviando[cartao.id] ?? null"
            @escolher="versao => escolher(cartao.id, versao)"
            @recarregar="carregar"
          />
        </div>
      </template>
    </template>
  </div>
</template>

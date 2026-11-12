<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { fraseDoPasso } from '../frases';
import { acharPasso } from '../receita';
import { chaveDoNome } from '../passosNovos/passosNovos';
import { abaixoDoMinimo, dolares } from '../custoDaIa';

// #2498 — "O que aconteceu": cada vez que a automação rodou, com os passos em
// frases e o porquê de cada pulo e falha. A frase sai da receita da versão em
// que a execução entrou; o motivo já vem traduzido da API. Conversa numa caixa
// que a pessoa não vê aparece sem nome e sem link; card e contato (#2731), pelo
// nome e com link para quem os vê, e só pelo tipo para quem não vê.
const props = defineProps({
  automacaoId: { type: Number, required: true },
  catalogo: { type: Object, required: true },
  accountId: { type: Number, required: true },
});

const { t, locale } = useI18n();
const estado = ref('carregando');
const execucoes = ref([]);
const versoes = ref({});
const pagina = ref(1);
const mais = ref(false);
const aberta = ref(null);

const ESTADO = {
  andando: 'bg-n-blue-3 text-n-blue-11',
  esperando: 'bg-n-blue-3 text-n-blue-11',
  concluida: 'bg-n-teal-3 text-n-teal-11',
  parada: 'bg-n-amber-3 text-n-amber-11',
  interrompida: 'bg-n-amber-3 text-n-amber-11',
  falhou: 'bg-n-ruby-3 text-n-ruby-11',
};

const RESULTADO = {
  ok: { icone: 'i-lucide-check', tom: 'text-n-teal-11', chave: '' },
  pulado: {
    icone: 'i-lucide-skip-forward',
    tom: 'text-n-amber-11',
    chave: 'PULOU',
  },
  falhou: {
    icone: 'i-lucide-circle-x',
    tom: 'text-n-ruby-11',
    chave: 'NAO_FEZ',
  },
};

const RAMO = {
  entao: 'ENTAO',
  senao: 'SENAO',
  se_vencer: 'SE_VENCER',
  nenhum: 'NENHUM',
  // G13 (#2670): o outro sistema recusou.
  se_recusar: 'SE_RECUSAR',
  // #2934: a busca em outro sistema não deu.
  nao_consultou: 'NAO_CONSULTOU',
};

const hora = iso =>
  new Date(iso).toLocaleString(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  });

// #2750: a espera sem prazo não tem hora para mostrar.
const estadoDe = execucao => {
  if (execucao.esperando_sem_prazo)
    return t('AUTOMACAO_LIVRE.HISTORICO.ESPERANDO_SEM_PRAZO');
  if (execucao.esperando_ate)
    return t('AUTOMACAO_LIVRE.HISTORICO.ESPERANDO_ATE', {
      quando: hora(execucao.esperando_ate),
    });
  return t(
    `AUTOMACAO_LIVRE.HISTORICO.ESTADOS.${execucao.estado.toUpperCase()}`
  );
};

const custoDaIa = valor =>
  t(
    abaixoDoMinimo(valor)
      ? 'AUTOMACAO_LIVRE.HISTORICO.IA_MENOS_DE'
      : 'AUTOMACAO_LIVRE.HISTORICO.IA',
    { valor: dolares(valor, locale.value) }
  );

// `lidas`: as versões de onde a frase sai (as da página, ou as de dentro de um
// bloco, #2933).
const fraseDe = (execucao, passo, lidas = versoes.value) => {
  if (passo.passo === 'inicio') return t('AUTOMACAO_LIVRE.HISTORICO.INICIO');
  const receita = lidas[execucao.versao_id]?.receita;
  const achado = acharPasso(receita?.passos || [], passo.passo);
  const frase = achado
    ? fraseDoPasso(achado, props.catalogo, t)
    : t('AUTOMACAO_LIVRE.HISTORICO.PASSO_SUMIU');
  const { chave } = RESULTADO[passo.resultado];
  return chave ? t(`AUTOMACAO_LIVRE.HISTORICO.${chave}`, { frase }) : frase;
};

// O caminho do "decidir" pelo nome que tinha na versão que rodou (a pessoa
// pode ter renomeado depois); sem achar, a chave.
const nomeDoCaminho = (execucao, passo) => {
  const receita = versoes.value[execucao.versao_id]?.receita;
  const decidir = acharPasso(receita?.passos || [], passo.passo);
  return (decidir?.caminhos || []).find(
    caminho => caminho.chave === passo.dados.ramo
  )?.nome;
};
const ramoDe = (execucao, passo) => {
  const { ramo } = passo.dados;
  if (RAMO[ramo]) return t(`AUTOMACAO_LIVRE.RAMOS.${RAMO[ramo]}`);
  return nomeDoCaminho(execucao, passo) || ramo;
};

// #2934: os dados que a busca guardou, pelo nome que a pessoa deu (o servidor
// manda só a chave do nome, nunca o valor nem o endereço).
const guardadosDe = (execucao, passo, lidas = versoes.value) => {
  const receita = lidas[execucao.versao_id]?.receita;
  const consulta = acharPasso(receita?.passos || [], passo.passo);
  return (passo.dados.guardados || [])
    .map(
      chave =>
        (consulta?.guardar || []).find(dado => chaveDoNome(dado.nome) === chave)
          ?.nome || chave
    )
    .join(', ');
};

// #2933: "Ver o que aconteceu dentro" do bloco, lido só quando a pessoa pede.
const dentro = ref({});
const verDentro = async filhaId => {
  if (dentro.value[filhaId]) {
    const { [filhaId]: _fechado, ...resto } = dentro.value;
    dentro.value = resto;
    return;
  }
  try {
    const { data } = await AutomacoesAPI.historicoDentro(
      props.automacaoId,
      filhaId
    );
    dentro.value = {
      ...dentro.value,
      [filhaId]: { execucao: data.execucoes[0], versoes: data.versoes },
    };
  } catch {
    dentro.value = { ...dentro.value, [filhaId]: { erro: true } };
  }
};

// G63: a volta do galho "a cada mensagem" à espera não vira linha: cada volta
// já tem a sua, a da mensagem do cliente, com a vez.
const passosDe = execucao =>
  execucao.passos.filter(passo => passo.dados.volta === undefined);

// A mensagem que saiu numa conversa aberta pelo passo (o número novo, G43) mora
// nela, não na conversa do alvo.
const linkDa = (execucao, mensagemId, conversaAberta) => {
  const url = frontendURL(
    conversationUrl({
      accountId: props.accountId,
      id: conversaAberta || execucao.alvo.conversa_id,
    })
  );
  return mensagemId ? `${url}?messageId=${mensagemId}` : url;
};

// O rótulo neutro de cada tipo, sem nome nem link. "Uma conversa" é só da
// conversa numa caixa que a pessoa não vê.
const SEM_NOME = {
  conversa: 'OCULTA',
  card: 'CARD_OCULTO',
  contato: 'CONTATO_OCULTO',
  conta: 'CONTA',
};

const conversaVisivel = ({ alvo }) => alvo.tipo === 'conversa' && alvo.visivel;

const nomeDa = ({ alvo }) => {
  if (!alvo.visivel)
    return t(`AUTOMACAO_LIVRE.HISTORICO.${SEM_NOME[alvo.tipo]}`);
  if (alvo.tipo === 'card')
    return t('AUTOMACAO_LIVRE.HISTORICO.CARD_DE', { nome: alvo.nome });
  if (alvo.tipo === 'contato')
    return alvo.nome || t('AUTOMACAO_LIVRE.HISTORICO.CONTATO_SEM_NOME');
  return alvo.nome
    ? t('AUTOMACAO_LIVRE.HISTORICO.CONVERSA_DE', { nome: alvo.nome })
    : t('AUTOMACAO_LIVRE.HISTORICO.CONVERSA_N', { n: alvo.conversa_id });
};

// O card e o contato que a pessoa vê abrem pelo link que a API manda.
const ABRIR = { card: 'ABRIR_CARD', contato: 'ABRIR_CONTATO' };
const abrirOutro = ({ alvo }) => alvo.visivel && ABRIR[alvo.tipo];

const carregar = async (proxima = 1) => {
  if (proxima === 1) estado.value = 'carregando';
  try {
    const { data } = await AutomacoesAPI.historico(props.automacaoId, proxima);
    // Uma execução que começou entre duas páginas empurra a lista: a que já
    // está na tela não aparece de novo.
    const vistas = new Set(proxima === 1 ? [] : execucoes.value.map(e => e.id));
    execucoes.value = [
      ...(proxima === 1 ? [] : execucoes.value),
      ...data.execucoes.filter(execucao => !vistas.has(execucao.id)),
    ];
    versoes.value = {
      ...(proxima === 1 ? {} : versoes.value),
      ...data.versoes,
    };
    pagina.value = data.pagina;
    mais.value = data.mais;
    if (proxima === 1) aberta.value = data.execucoes[0]?.id ?? null;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

const alternar = id => {
  aberta.value = aberta.value === id ? null : id;
};

watch(
  () => props.automacaoId,
  () => carregar()
);
onMounted(() => carregar());
</script>

<template>
  <section
    data-historico
    class="flex flex-col gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    aria-labelledby="titulo-historico"
  >
    <div class="flex flex-col gap-1">
      <h2
        id="titulo-historico"
        class="mb-0 text-lg font-semibold text-n-slate-12"
      >
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.TITULO') }}
      </h2>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.SUBTITULO') }}
      </p>
    </div>

    <div
      v-if="estado === 'carregando'"
      data-carregando
      aria-busy="true"
      :aria-label="$t('AUTOMACAO_LIVRE.HISTORICO.CARREGANDO')"
      class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse"
    />

    <div
      v-else-if="estado === 'erro'"
      data-erro
      role="alert"
      class="flex flex-col items-start gap-3"
    >
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.ERRO') }}
      </p>
      <Button
        :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="min-h-11"
        @click="carregar()"
      />
    </div>

    <p
      v-else-if="!execucoes.length"
      data-vazio
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('AUTOMACAO_LIVRE.HISTORICO.VAZIO') }}
    </p>

    <template v-else>
      <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
        <li v-for="execucao in execucoes" :key="execucao.id" class="py-1">
          <button
            type="button"
            data-execucao
            :aria-expanded="aberta === execucao.id"
            class="flex flex-wrap items-center w-full py-2 gap-x-3 gap-y-1 text-start min-h-11"
            @click="alternar(execucao.id)"
          >
            <span
              class="transition size-4 text-n-slate-10 i-lucide-chevron-right rtl:rotate-180"
              :class="[aberta === execucao.id ? '!rotate-90' : '']"
              aria-hidden="true"
            />
            <span
              data-alvo
              :data-oculta="!execucao.alvo.visivel || undefined"
              :title="
                execucao.alvo.tipo === 'conversa' && !execucao.alvo.visivel
                  ? $t('AUTOMACAO_LIVRE.HISTORICO.OCULTA_DICA')
                  : undefined
              "
              class="text-[0.9375rem] font-medium"
              :class="
                execucao.alvo.visivel ? 'text-n-slate-12' : 'text-n-slate-11'
              "
            >
              {{ nomeDa(execucao) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ relativeTimeFromISO(execucao.criada_em, locale) }}
            </span>
            <span
              data-estado
              class="px-2.5 py-0.5 text-xs font-semibold rounded-full"
              :class="ESTADO[execucao.estado]"
            >
              {{ estadoDe(execucao) }}
            </span>
          </button>
          <div
            v-if="aberta === execucao.id"
            class="flex flex-col gap-3 pb-3 ps-7"
          >
            <ol class="flex flex-col gap-2 p-0 m-0 list-none">
              <li
                v-for="(passo, indice) in passosDe(execucao)"
                :key="indice"
                data-passo
                class="flex items-start gap-2.5"
              >
                <span
                  class="mt-0.5 size-4 shrink-0"
                  :class="[
                    RESULTADO[passo.resultado].icone,
                    RESULTADO[passo.resultado].tom,
                  ]"
                  aria-hidden="true"
                />
                <span class="flex flex-col gap-0.5">
                  <span class="text-[0.9375rem] text-n-slate-12">
                    {{ fraseDe(execucao, passo) }}
                  </span>
                  <span
                    v-if="passo.dados.ramo"
                    data-ramo
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR', {
                        ramo: ramoDe(execucao, passo),
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.dados.sem_prazo"
                    data-sem-prazo
                    class="text-sm text-n-slate-11"
                  >
                    {{ $t('AUTOMACAO_LIVRE.HISTORICO.ESPERA_SEM_PRAZO') }}
                  </span>
                  <span
                    v-if="passo.dados.conferir_as !== undefined"
                    data-conferir-as
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.CONFERE_AS', {
                        hora: passo.dados.conferir_as,
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.dados.vez"
                    data-vez
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.VEZ', {
                        n: passo.dados.vez,
                      })
                    }}
                  </span>
                  <span v-if="passo.dados.ate" class="text-sm text-n-slate-11">
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.ESPERA_ATE', {
                        quando: hora(passo.dados.ate),
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.motivo"
                    data-motivo
                    class="text-sm text-n-slate-11"
                  >
                    {{ passo.motivo }}
                  </span>
                  <span
                    v-if="passo.dados.guardados?.length"
                    data-guardados
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.GUARDOU', {
                        dados: guardadosDe(execucao, passo),
                      })
                    }}
                  </span>
                  <span v-if="passo.dados.filha_id" class="flex flex-col gap-2">
                    <Button
                      data-ver-dentro
                      type="button"
                      :label="
                        $t(
                          dentro[passo.dados.filha_id]
                            ? 'AUTOMACAO_LIVRE.HISTORICO.FECHAR_DENTRO'
                            : 'AUTOMACAO_LIVRE.HISTORICO.VER_DENTRO'
                        )
                      "
                      icon="i-lucide-boxes"
                      slate
                      link
                      class="self-start min-h-11"
                      @click="verDentro(passo.dados.filha_id)"
                    />
                    <span
                      v-if="dentro[passo.dados.filha_id]?.erro"
                      role="alert"
                      class="text-sm text-n-ruby-11"
                    >
                      {{ $t('AUTOMACAO_LIVRE.HISTORICO.DENTRO_ERRO') }}
                    </span>
                    <ol
                      v-else-if="dentro[passo.dados.filha_id]"
                      data-dentro
                      class="flex flex-col gap-1.5 p-0 m-0 border-s-2 border-n-weak ps-3 list-none"
                    >
                      <li
                        v-for="(deDentro, n) in dentro[passo.dados.filha_id]
                          .execucao.passos"
                        :key="n"
                        class="flex flex-col gap-0.5"
                      >
                        <span class="text-sm text-n-slate-12">
                          {{
                            fraseDe(
                              dentro[passo.dados.filha_id].execucao,
                              deDentro,
                              dentro[passo.dados.filha_id].versoes
                            )
                          }}
                        </span>
                        <span
                          v-if="deDentro.motivo"
                          class="text-sm text-n-slate-11"
                        >
                          {{ deDentro.motivo }}
                        </span>
                      </li>
                    </ol>
                  </span>
                  <span
                    v-if="passo.dados.tentativa"
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.TENTATIVA', {
                        n: passo.dados.tentativa,
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.dados.numero_novo"
                    data-numero-novo
                    class="text-sm text-n-slate-11"
                  >
                    {{ $t('AUTOMACAO_LIVRE.HISTORICO.NUMERO_NOVO') }}
                  </span>
                  <span
                    v-if="passo.dados.conversas_fora"
                    data-conversas-fora
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t(
                        'AUTOMACAO_LIVRE.HISTORICO.CONVERSAS_FORA',
                        { n: passo.dados.conversas_fora },
                        passo.dados.conversas_fora
                      )
                    }}
                  </span>
                  <span
                    v-if="passo.dados.conversa_principal_do_card"
                    data-conversa-principal
                    class="text-sm text-n-slate-11"
                  >
                    {{ $t('AUTOMACAO_LIVRE.HISTORICO.CONVERSA_PRINCIPAL') }}
                  </span>
                  <span
                    v-if="passo.dados.ia?.custo_usd != null"
                    data-ia
                    class="text-xs text-n-slate-10"
                  >
                    {{ custoDaIa(passo.dados.ia.custo_usd) }}
                  </span>
                  <a
                    v-if="
                      conversaVisivel(execucao) &&
                      (passo.dados.mensagem_id || passo.dados.nota_id)
                    "
                    data-ver-mensagem
                    :href="
                      linkDa(
                        execucao,
                        passo.dados.mensagem_id || passo.dados.nota_id,
                        passo.dados.conversa_aberta
                      )
                    "
                    class="text-sm font-medium text-n-blue-11 hover:underline"
                  >
                    {{ $t('AUTOMACAO_LIVRE.HISTORICO.VER_MENSAGEM') }}
                  </a>
                </span>
              </li>
            </ol>
            <a
              v-if="conversaVisivel(execucao)"
              data-abrir-conversa
              :href="linkDa(execucao)"
              class="self-start text-sm font-medium text-n-blue-11 hover:underline"
            >
              {{ $t('AUTOMACAO_LIVRE.HISTORICO.ABRIR_CONVERSA') }}
            </a>
            <a
              v-else-if="abrirOutro(execucao)"
              data-abrir-alvo
              :href="frontendURL(execucao.alvo.link)"
              class="self-start text-sm font-medium text-n-blue-11 hover:underline"
            >
              {{ $t(`AUTOMACAO_LIVRE.HISTORICO.${abrirOutro(execucao)}`) }}
            </a>
          </div>
        </li>
      </ul>
      <Button
        v-if="mais"
        data-ver-mais
        :label="$t('AUTOMACAO_LIVRE.HISTORICO.VER_MAIS')"
        slate
        faded
        class="self-start min-h-11"
        @click="carregar(pagina + 1)"
      />
    </template>
  </section>
</template>

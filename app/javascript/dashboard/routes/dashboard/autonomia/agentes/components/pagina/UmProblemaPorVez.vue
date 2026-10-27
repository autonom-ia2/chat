<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import EscolhaRadio from '../EscolhaRadio.vue';

// #1426 (tema 4b) — "um problema por vez" (mockup aprovado em 19/10): o que as conferências e o autoteste acharam no
// material, um cartão de cada vez, com "1 de N", uma explicação simples e no máximo duas saídas. Nada trava: "Pular por
// agora" passa para o próximo, e o agente segue atendendo com o resto do material. Nada se resolve sozinho: cada saída é
// a pessoa que escolhe. Quem só vê lê o cartão, sem as ações. "Ficar só com X" (duplicado) tira o repetido pelo
// mesmo caminho do "Tirar" da gaveta, com a mesma confirmação.
// Tipos (Material::Problemas): vazio, ocr (leitura ruim), sem_cabecalho (tabela sem títulos), duplicado, contradicao,
// paginas_de_fora (o material vale com o que foi lido), autoteste (resposta errada) e autoteste_fora (inventou numa
// pergunta de fora do material).
const props = defineProps({
  problemas: { type: Array, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  // O problema que está sendo resolvido (o botão mostra que está salvando).
  resolvendo: { type: String, default: '' },
});

const emit = defineEmits([
  'resolver',
  'mandarOutro',
  'mandarNovo',
  'tirar',
  'corrigir',
]);

const { t, locale } = useI18n();

const escolha = ref(null);
// "Pular por agora" (sempre presente): o cartão pulado sai da fila até a gaveta abrir de novo. Pulado o último, o
// cartão some; o que precisa da pessoa continua contado no quadro "O que sabe" da página.
const pulados = ref([]);
const fila = computed(() =>
  props.problemas.filter(problema => !pulados.value.includes(problema.id))
);
const atual = computed(() => fila.value[0]);
watch(
  () => atual.value?.id,
  () => {
    escolha.value = null;
  }
);

const pular = () => {
  pulados.value = [...pulados.value, atual.value.id];
};

// Chaves estáticas (a trava de lint da CI recusa chave montada em tempo de execução).
const CHAVES = {
  vazio: 'VAZIO',
  ocr: 'OCR',
  sem_cabecalho: 'SEM_CABECALHO',
  duplicado: 'DUPLICADO',
  contradicao: 'CONTRADICAO',
  paginas_de_fora: 'PAGINAS',
  autoteste: 'AUTOTESTE',
  autoteste_fora: 'AUTOTESTE_FORA',
};
const chave = computed(() => CHAVES[atual.value?.tipo] || 'VAZIO');

const MOTIVOS = {
  falha: () =>
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MOTIVO.FALHA'),
  grande: () =>
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MOTIVO.GRANDE'),
  limite: () =>
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MOTIVO.LIMITE'),
  tempo: () =>
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MOTIVO.TEMPO'),
};
// Os motivos das páginas de fora, em palavras, juntos como a língua junta ("a, b e c").
const motivos = computed(() => {
  const lista = (atual.value?.motivos || [])
    .map(motivo => MOTIVOS[motivo]?.())
    .filter(Boolean);
  if (!lista.length)
    return t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MOTIVO.LIMITE');
  // O idioma do painel vem como "pt_BR"; o Intl quer "pt-BR".
  const idioma = String(locale.value).replaceAll('_', '-');
  return new Intl.ListFormat(idioma, { type: 'conjunction' }).format(lista);
});
const dados = computed(() => ({
  ...atual.value,
  agente: props.nome,
  motivos: motivos.value,
}));

// Variantes do texto: a leitura ruim de um arquivo (não foto) e as páginas de fora sem o total conhecido.
const sufixo = computed(() => {
  if (atual.value?.tipo === 'ocr' && !atual.value.foto) return '_ARQUIVO';
  if (atual.value?.tipo === 'paginas_de_fora' && !atual.value.total) {
    return '_SEM_TOTAL';
  }
  return '';
});
const TEXTOS = {
  VAZIO: {
    titulo: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.VAZIO.TITULO', d),
    texto: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.VAZIO.TEXTO', d),
  },
  OCR: {
    titulo: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.TITULO', d),
    texto: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.TEXTO', d),
  },
  OCR_ARQUIVO: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.TITULO_ARQUIVO', d),
    texto: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.TEXTO_ARQUIVO', d),
  },
  SEM_CABECALHO: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.SEM_CABECALHO.TITULO', d),
    texto: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.SEM_CABECALHO.TEXTO', d),
  },
  DUPLICADO: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.DUPLICADO.TITULO', d),
    texto: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.DUPLICADO.TEXTO', d),
  },
  CONTRADICAO: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTRADICAO.TITULO', d),
    texto: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTRADICAO.TEXTO', d),
  },
  PAGINAS: {
    titulo: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.TITULO', d),
    texto: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.TEXTO', d),
  },
  PAGINAS_SEM_TOTAL: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.TITULO_SEM_TOTAL', d),
    texto: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.TEXTO_SEM_TOTAL', d),
  },
  AUTOTESTE: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.TITULO', d),
    texto: d => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.TEXTO', d),
  },
  AUTOTESTE_FORA: {
    titulo: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE_FORA.TITULO', d),
    texto: d =>
      t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE_FORA.TEXTO', d),
  },
};
const textos = computed(() => TEXTOS[`${chave.value}${sufixo.value}`]);
const titulo = computed(() => textos.value.titulo(dados.value));
const texto = computed(() => textos.value.texto(dados.value));
const MANDAR = {
  VAZIO: () => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.VAZIO.MANDAR'),
  OCR: () => t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.MANDAR'),
  OCR_ARQUIVO: () =>
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.MANDAR_ARQUIVO'),
};
const mandar = computed(() => MANDAR[`${chave.value}${sufixo.value}`]());

const ehAutoteste = computed(() =>
  ['autoteste', 'autoteste_fora'].includes(atual.value?.tipo)
);
const respondeu = computed(
  () =>
    atual.value?.resposta ||
    t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.PASSOU')
);

const opcoesDaContradicao = computed(() =>
  (atual.value?.opcoes || []).map(opcao => ({
    valor: opcao.valor,
    titulo: opcao.diz,
    texto: t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTRADICAO.ONDE', {
      onde: opcao.onde,
    }),
  }))
);

const salvando = computed(() => props.resolvendo === atual.value?.id);
const resolver = valor => emit('resolver', atual.value.id, valor);
const fonte = computed(() => atual.value?.fontes?.[0]);
const corrigirResposta = () =>
  emit('corrigir', {
    pergunta: atual.value.pergunta,
    resposta: respondeu.value,
  });
</script>

<template>
  <!-- Raiz sem v-if (regra vue/no-root-v-if); "contents" não cria caixa, então a gaveta não ganha espaço extra. -->
  <div class="contents">
    <section
      v-if="atual"
      data-um-problema
      :data-tipo="atual.tipo"
      :aria-label="t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.ROTULO')"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
    >
      <p
        class="flex items-center gap-2 m-0 text-xs font-semibold text-n-amber-11"
      >
        <span class="i-lucide-hand size-4" aria-hidden="true" />
        <span data-contagem>
          {{
            t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTAGEM', {
              atual: problemas.length - fila.length + 1,
              total: problemas.length,
            })
          }}
        </span>
      </p>
      <h3 data-titulo class="m-0 text-base font-semibold text-n-slate-12">
        {{ titulo }}
      </h3>
      <p data-texto class="m-0 text-sm text-n-slate-12">{{ texto }}</p>

      <ul
        v-if="atual.tipo === 'sem_cabecalho' && atual.amostra?.length"
        data-amostra
        :aria-label="
          t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.SEM_CABECALHO.AMOSTRA')
        "
        class="flex flex-wrap gap-1 p-0 m-0 list-none"
      >
        <li
          v-for="(celula, i) in atual.amostra"
          :key="i"
          class="px-2 py-1 font-mono text-xs rounded-md bg-n-solid-1 ring-1 ring-inset ring-n-weak text-n-slate-12"
        >
          {{ celula }}
        </li>
      </ul>

      <dl
        v-if="ehAutoteste"
        data-autoteste
        class="flex flex-col gap-1 p-3 m-0 text-sm rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <dt class="font-semibold text-n-slate-11">
          {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.PERGUNTA') }}
        </dt>
        <dd class="m-0 text-n-slate-12">{{ atual.pergunta }}</dd>
        <dt class="font-semibold text-n-slate-11">
          {{
            t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.RESPONDEU', {
              agente: nome,
            })
          }}
        </dt>
        <dd class="m-0 text-n-slate-12">{{ respondeu }}</dd>
        <template v-if="atual.tipo === 'autoteste' && atual.esperado">
          <dt class="font-semibold text-n-slate-11">
            {{
              t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.MATERIAL')
            }}
          </dt>
          <dd class="m-0 text-n-slate-12">
            {{
              atual.onde
                ? t(
                    'AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.MATERIAL_DIZ',
                    {
                      onde: atual.onde,
                      texto: atual.esperado,
                    }
                  )
                : atual.esperado
            }}
          </dd>
        </template>
      </dl>

      <EscolhaRadio
        v-if="atual.tipo === 'contradicao' && podeGerenciar"
        v-model="escolha"
        :rotulo="t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTRADICAO.QUAL')"
        :opcoes="opcoesDaContradicao"
      />

      <div v-if="podeGerenciar" data-acoes class="flex flex-wrap gap-2">
        <template v-if="atual.tipo === 'vazio' || atual.tipo === 'ocr'">
          <AgenteBotao
            data-acao="mandar-outro"
            @click="emit('mandarOutro', fonte)"
          >
            {{ mandar }}
          </AgenteBotao>
          <AgenteBotao
            v-if="atual.tipo === 'vazio'"
            data-acao="tirar"
            variante="contorno"
            @click="emit('tirar', fonte)"
          >
            {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.VAZIO.TIRAR') }}
          </AgenteBotao>
          <AgenteBotao
            v-else
            data-acao="escrever"
            variante="contorno"
            @click="emit('corrigir', null)"
          >
            {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.OCR.ESCREVER') }}
          </AgenteBotao>
        </template>
        <template v-else-if="atual.tipo === 'duplicado'">
          <AgenteBotao data-acao="um-so" @click="emit('tirar', atual.tirar)">
            {{
              t(
                'AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.DUPLICADO.UM_SO',
                dados
              )
            }}
          </AgenteBotao>
          <AgenteBotao
            data-acao="os-dois"
            variante="contorno"
            :carregando="salvando"
            @click="resolver('os_dois')"
          >
            {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.DUPLICADO.OS_DOIS') }}
          </AgenteBotao>
        </template>
        <template v-else-if="atual.tipo === 'sem_cabecalho'">
          <AgenteBotao
            data-acao="mandar-outro"
            @click="emit('mandarOutro', fonte)"
          >
            {{
              t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.SEM_CABECALHO.MANDAR')
            }}
          </AgenteBotao>
          <AgenteBotao
            data-acao="explicar"
            variante="contorno"
            @click="emit('corrigir', null)"
          >
            {{
              t(
                'AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.SEM_CABECALHO.EXPLICAR'
              )
            }}
          </AgenteBotao>
        </template>
        <AgenteBotao
          v-else-if="atual.tipo === 'paginas_de_fora'"
          data-acao="mandar-novo"
          @click="emit('mandarNovo')"
        >
          {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PAGINAS.MANDAR') }}
        </AgenteBotao>
        <AgenteBotao
          v-else-if="atual.tipo === 'contradicao'"
          data-acao="usar"
          :inativo="escolha === null"
          :carregando="salvando"
          @click="resolver(escolha)"
        >
          {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTRADICAO.USAR') }}
        </AgenteBotao>
        <template v-else-if="ehAutoteste">
          <AgenteBotao data-acao="corrigir" @click="corrigirResposta">
            {{
              t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.CORRIGIR')
            }}
          </AgenteBotao>
          <AgenteBotao
            data-acao="certa"
            variante="contorno"
            :carregando="salvando"
            @click="resolver('certa')"
          >
            {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.AUTOTESTE.CERTA') }}
          </AgenteBotao>
        </template>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="m-0 text-xs text-n-slate-11">
          {{
            t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.CONTINUA', {
              agente: nome,
            })
          }}
        </p>
        <button
          type="button"
          data-pular
          class="px-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="pular"
        >
          {{ t('AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA.PULAR') }}
        </button>
      </div>
    </section>
  </div>
</template>

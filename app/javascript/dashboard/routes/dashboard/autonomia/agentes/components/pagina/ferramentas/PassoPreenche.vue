<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import CartaoInformacao from './CartaoInformacao.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import {
  avisosDasInformacoes,
  jsonValido,
  novaInformacao,
} from '../../../utils/ferramentas';

// #1301 (protótipo F05) — passo 3: as informações que o agente tira da conversa, o corpo (só em
// POST, com checagem de JSON) e, em Avançado, como a resposta chega ao agente (response_mapping).
// Avisos dos dois lados: {{variável}} sem informação e informação que não vai a lugar nenhum.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
});

const emit = defineEmits(['update:rascunho', 'anunciar']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.TRES';
// onde: ENDERECO, CORPO ou CABECALHO → SEM_INFORMACAO_ENDERECO / _CORPO / _CABECALHO.
const { t } = useI18n();

const EXEMPLO_NOME = '{{termo}}';
const EXEMPLO_CORPO = '{ "termo": "{{termo}}", "limite": 5 }';
const EXEMPLO_MAPEAMENTO =
  '{% for i in response.itens %}{{ i.nome }} – R$ {{ i.preco }}; {% endfor %}';

const mudar = (campo, valor) =>
  emit('update:rascunho', { ...props.rascunho, [campo]: valor });

const mudarInformacao = (indice, informacao) =>
  mudar(
    'informacoes',
    props.rascunho.informacoes.map((item, i) =>
      i === indice ? informacao : item
    )
  );

const adicionar = () =>
  mudar('informacoes', [...props.rascunho.informacoes, novaInformacao()]);

const remover = indice => {
  mudar(
    'informacoes',
    props.rascunho.informacoes.filter((_, i) => i !== indice)
  );
  emit('anunciar', t(`${NS}.REMOVIDA`));
};

const post = computed(() => props.rascunho.metodo === 'POST');
const corpoValido = computed(() =>
  jsonValido(props.rascunho.corpo, props.rascunho.informacoes)
);

const avisos = computed(() => {
  const { semInformacao, naoUsadas } = avisosDasInformacoes(props.rascunho);
  const lista = naoUsadas.map(nome => t(`${NS}.NAO_USADA`, { nome }));
  if (!semInformacao) return lista;
  const chave = `SEM_INFORMACAO_${semInformacao.onde}`;
  return [
    t(`${NS}.${chave}`, {
      variavel: `{{${semInformacao.nome}}}`,
      nome: semInformacao.nome,
    }),
    ...lista,
  ];
});

const preenchido = valor => String(valor ?? '').trim() !== '';
</script>

<template>
  <div class="flex flex-col gap-5">
    <p class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.INTRO`, { exemplo: EXEMPLO_NOME }) }}
    </p>
    <div
      v-if="avisos.length"
      data-avisos-informacoes
      class="flex flex-col gap-2"
    >
      <FerramentaFaixa v-for="aviso in avisos" :key="aviso" tom="ambar" solta>
        <p class="m-0 break-words">{{ aviso }}</p>
      </FerramentaFaixa>
    </div>
    <div class="flex flex-col gap-3">
      <CartaoInformacao
        v-for="(informacao, indice) in rascunho.informacoes"
        :key="informacao.id"
        :informacao="informacao"
        :indice="indice"
        :base="base"
        :erro="
          erros[`i${indice}`] ? t(`${NS}.ERRO.${erros[`i${indice}`]}`) : ''
        "
        @update:informacao="mudarInformacao(indice, $event)"
        @remover="remover(indice)"
      />
      <p
        v-if="!rascunho.informacoes.length"
        data-sem-informacao
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.NENHUMA`) }}
      </p>
    </div>
    <AgenteBotao
      :id="`${base}-adicionar-informacao`"
      data-adicionar-informacao
      variante="contorno"
      icone="i-lucide-plus"
      class="self-start"
      @click="adicionar"
    >
      {{ t(`${NS}.ADICIONAR`) }}
    </AgenteBotao>
    <FerramentaCampo
      v-if="post"
      :id="`${base}-corpo`"
      :rotulo="t(`${NS}.CORPO`)"
      :ajuda="t(`${NS}.CORPO_AJUDA`)"
      :exemplo="EXEMPLO_CORPO"
      exemplo-mono
      :preenchido="preenchido(rascunho.corpo)"
    >
      <template #default="{ descricao }">
        <FerramentaEntrada
          :id="`${base}-corpo`"
          data-campo-corpo
          :model-value="rascunho.corpo"
          :linhas="5"
          mono
          :descricao="descricao"
          :invalido="!corpoValido"
          @update:model-value="mudar('corpo', $event)"
        />
      </template>
      <template #depois>
        <FerramentaFaixa
          v-if="!corpoValido"
          data-corpo-invalido
          tom="ambar"
          solta
        >
          <p class="m-0">{{ t(`${NS}.CORPO_INVALIDO`) }}</p>
        </FerramentaFaixa>
      </template>
    </FerramentaCampo>
    <FerramentaFaixa v-else data-sem-corpo tom="azul" solta>
      <p class="m-0">{{ t(`${NS}.SEM_CORPO`) }}</p>
    </FerramentaFaixa>
    <details
      class="group rounded-xl ring-1 ring-inset ring-n-weak"
      :open="preenchido(rascunho.mapeamento)"
    >
      <summary
        class="flex items-center gap-2 px-3 text-sm font-semibold list-none cursor-pointer rounded-xl min-h-11 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        <span
          aria-hidden="true"
          class="transition i-lucide-chevron-right size-4 group-open:rotate-90"
        />
        {{ t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.AVANCADO') }}
      </summary>
      <div class="px-3 pb-3">
        <FerramentaCampo
          :id="`${base}-mapeamento`"
          :rotulo="t(`${NS}.MAPEAMENTO`)"
          opcional
          :ajuda="t(`${NS}.MAPEAMENTO_AJUDA`, { response: 'response' })"
          :exemplo="EXEMPLO_MAPEAMENTO"
          exemplo-mono
          :preenchido="preenchido(rascunho.mapeamento)"
        >
          <template #default="{ descricao }">
            <FerramentaEntrada
              :id="`${base}-mapeamento`"
              data-campo-mapeamento
              :model-value="rascunho.mapeamento"
              :linhas="3"
              mono
              :descricao="descricao"
              @update:model-value="mudar('mapeamento', $event)"
            />
          </template>
        </FerramentaCampo>
      </div>
    </details>
  </div>
</template>

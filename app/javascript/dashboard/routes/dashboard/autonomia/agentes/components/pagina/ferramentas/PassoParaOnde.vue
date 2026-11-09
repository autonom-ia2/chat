<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolhaRadio from '../../EscolhaRadio.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import {
  avisosDasInformacoes,
  conferirEndereco,
  corpoPadrao,
  enderecoLegivel,
  inserirInformacao,
  jsonValido,
  nomeTecnico,
  variaveisEm,
} from '../../../utils/ferramentas';

// #1301 (protótipo F04) — buscar ou mandar informação, e o link. O link é conferido ao sair do campo
// (parser URL do navegador, sem regex); cada valor é codificado pelo backend conforme a posição (#1425).
// #1430: é o passo 3. A pessoa cola o link e toca na informação do passo 2 para encaixá-la onde o
// cursor está: ela nunca digita {{ }}. Logo abaixo, o link como o agente usa, com [CEP] no lugar.
// Nome técnico, o que vai junto (já pronto com as informações) e o recorte da resposta ficam em Avançado.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
});

const emit = defineEmits(['update:rascunho']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.DOIS';
const { t } = useI18n();

const INICIO = 'https://';
const EXEMPLO_MAPEAMENTO =
  '{% for i in response.itens %}{{ i.nome }} – R$ {{ i.preco }}; {% endfor %}';

const preenchido = valor => String(valor ?? '').trim() !== '';
const idDoLink = computed(() => `${props.base}-endereco`);

const mudar = (campo, valor) =>
  emit('update:rascunho', { ...props.rascunho, [campo]: valor });

// "Mandar informação" sem nada escrito em "O que vai junto": já vai com todas as informações.
const mudarMetodo = metodo => {
  const corpo =
    metodo === 'POST' && !preenchido(props.rascunho.corpo)
      ? corpoPadrao(props.rascunho.informacoes)
      : props.rascunho.corpo;
  emit('update:rascunho', { ...props.rascunho, metodo, corpo });
};

const opcoes = computed(() => [
  { valor: 'GET', titulo: t(`${NS}.GET`), texto: t(`${NS}.GET_TEXTO`) },
  { valor: 'POST', titulo: t(`${NS}.POST`), texto: t(`${NS}.POST_TEXTO`) },
]);

const informacoes = computed(() =>
  props.rascunho.informacoes.filter(i => preenchido(i.nome))
);

// O cursor do link fica guardado no próprio campo, mesmo depois do toque no botão.
const encaixar = async informacao => {
  const campo = document.getElementById(idDoLink.value);
  const posicao = campo ? campo.selectionStart : null;
  const novo = inserirInformacao(
    props.rascunho.endereco,
    posicao,
    informacao.nome
  );
  mudar('endereco', novo);
  await nextTick();
  if (!campo) return;
  const depois = novo.length - String(props.rascunho.endereco ?? '').length;
  const fim = (Number.isInteger(posicao) ? posicao : novo.length) + depois;
  campo.focus();
  campo.setSelectionRange(fim, fim);
};

const legivel = computed(() =>
  variaveisEm(props.rascunho.endereco).length
    ? enderecoLegivel(props.rascunho.endereco, props.rascunho.informacoes)
    : ''
);

// Erro do campo: o da conferência ao sair do campo vale até o próximo "Continuar".
const conferido = ref(null);
watch(
  () => props.erros,
  () => {
    conferido.value = null;
  }
);
const erroDoEndereco = computed(
  () => conferido.value ?? props.erros.endereco ?? ''
);
const conferirAoSair = () => {
  const texto = String(props.rascunho.endereco ?? '').trim();
  conferido.value = texto ? conferirEndereco(texto) : '';
};

const rotuloDe = nome =>
  props.rascunho.informacoes.find(i => i.nome === nome)?.rotulo || nome;

// Dois lados: [informação] sem informação no passo 2 e informação que não vai a lugar nenhum.
const avisos = computed(() => {
  const { semInformacao, naoUsadas } = avisosDasInformacoes(props.rascunho);
  const lista = naoUsadas.map(nome =>
    t(`${NS}.NAO_USADA`, { nome: rotuloDe(nome) })
  );
  if (!semInformacao) return lista;
  return [
    t(`${NS}.SEM_INFORMACAO_${semInformacao.onde}`, {
      nome: semInformacao.nome,
    }),
    ...lista,
  ];
});

const post = computed(() => props.rascunho.metodo === 'POST');
const corpoValido = computed(() => jsonValido(props.rascunho.corpo));
const avancadoAberto = computed(
  () =>
    Boolean(props.rascunho.slug || props.erros.slug) ||
    preenchido(props.rascunho.mapeamento) ||
    !corpoValido.value
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-col gap-2">
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.METODO`) }}
      </p>
      <EscolhaRadio
        data-metodo
        :rotulo="t(`${NS}.METODO`)"
        :opcoes="opcoes"
        :model-value="rascunho.metodo"
        @update:model-value="mudarMetodo"
      />
    </div>
    <FerramentaCampo
      :id="idDoLink"
      :rotulo="t(`${NS}.ENDERECO`)"
      :erro="erroDoEndereco ? t(`${NS}.ERRO.${erroDoEndereco}`) : ''"
      :ajuda="t(`${NS}.ENDERECO_AJUDA`)"
      :preenchido="preenchido(rascunho.endereco)"
    >
      <template #default="{ descricao, invalido }">
        <FerramentaEntrada
          :id="idDoLink"
          data-campo-endereco
          :model-value="rascunho.endereco"
          :linhas="2"
          mono
          inputmode="url"
          :placeholder="INICIO"
          :descricao="descricao"
          :invalido="invalido"
          @update:model-value="mudar('endereco', $event)"
          @blur="conferirAoSair"
        />
      </template>
      <template #depois>
        <div
          v-if="informacoes.length"
          data-encaixar
          class="flex flex-col gap-2"
        >
          <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.ENCAIXAR`) }}</p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="informacao in informacoes"
              :key="informacao.id"
              type="button"
              data-encaixar-informacao
              :aria-label="
                t(`${NS}.ENCAIXAR_SR`, {
                  rotulo: informacao.rotulo || informacao.nome,
                })
              "
              class="inline-flex items-center gap-1.5 px-3 text-sm font-medium rounded-full min-h-11 bg-n-blue-2 text-n-blue-11 ring-1 ring-inset ring-n-blue-6 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @mousedown.prevent
              @click="encaixar(informacao)"
            >
              <span aria-hidden="true" class="i-lucide-plus size-4" />
              {{ informacao.rotulo || informacao.nome }}
            </button>
          </div>
        </div>
        <p v-else data-sem-informacoes class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.SEM_INFORMACOES`) }}
        </p>
        <p
          v-if="legivel"
          data-link-legivel
          class="m-0 text-sm break-words text-n-slate-11 [overflow-wrap:anywhere]"
        >
          {{ t(`${NS}.COMO_FICA`) }}
          <span class="font-mono text-n-slate-12">{{ legivel }}</span>
        </p>
      </template>
    </FerramentaCampo>
    <div
      v-if="avisos.length"
      data-avisos-informacoes
      class="flex flex-col gap-2"
    >
      <FerramentaFaixa v-for="aviso in avisos" :key="aviso" tom="ambar" solta>
        <p class="m-0 break-words">{{ aviso }}</p>
      </FerramentaFaixa>
    </div>
    <details
      class="group rounded-xl ring-1 ring-inset ring-n-weak"
      :open="avancadoAberto"
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
      <div class="flex flex-col gap-5 px-3 pb-3">
        <FerramentaCampo
          :id="`${base}-slug`"
          :rotulo="t(`${NS}.SLUG`)"
          opcional
          :erro="erros.slug ? t(`${NS}.SLUG_ERRO`) : ''"
          :ajuda="t(`${NS}.SLUG_AJUDA`)"
        >
          <template #default="{ descricao, invalido }">
            <FerramentaEntrada
              :id="`${base}-slug`"
              data-campo-slug
              :model-value="rascunho.slug"
              mono
              :placeholder="nomeTecnico(rascunho.nome)"
              :descricao="descricao"
              :invalido="invalido"
              @update:model-value="mudar('slug', $event)"
            />
          </template>
        </FerramentaCampo>
        <FerramentaCampo
          v-if="post"
          :id="`${base}-corpo`"
          :rotulo="t(`${NS}.AVANCADO.CORPO`)"
          :ajuda="t(`${NS}.AVANCADO.CORPO_AJUDA`)"
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
              <p class="m-0">{{ t(`${NS}.AVANCADO.CORPO_INVALIDO`) }}</p>
            </FerramentaFaixa>
          </template>
        </FerramentaCampo>
        <FerramentaCampo
          :id="`${base}-mapeamento`"
          :rotulo="t(`${NS}.AVANCADO.MAPEAMENTO`)"
          opcional
          :ajuda="
            t(`${NS}.AVANCADO.MAPEAMENTO_AJUDA`, { response: 'response' })
          "
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

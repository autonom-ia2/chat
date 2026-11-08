<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolhaRadio from '../../EscolhaRadio.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import {
  conferirEndereco,
  enderecoDeExemplo,
  nomeTecnico,
  variaveisEm,
} from '../../../utils/ferramentas';

// #1301 (protótipo F04) — passo 2: buscar (GET) ou enviar (POST) e o endereço. O endereço é
// conferido ao sair do campo (parser URL do navegador, sem regex). Cada valor do endereço é codificado
// pelo backend conforme a posição (#1425): não há aviso de url_encode.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
  novo: { type: Boolean, default: false },
});

const emit = defineEmits(['update:rascunho']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.DOIS';
const { t } = useI18n();

const VARIAVEL = '{{nome}}';
const INICIO = 'https://';

const mudar = (campo, valor) =>
  emit('update:rascunho', { ...props.rascunho, [campo]: valor });

const opcoes = computed(() => [
  { valor: 'GET', titulo: t(`${NS}.GET`), texto: t(`${NS}.GET_TEXTO`) },
  { valor: 'POST', titulo: t(`${NS}.POST`), texto: t(`${NS}.POST_TEXTO`) },
]);

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

const avisoCriar = computed(() => {
  if (!props.novo) return '';
  const nomes = props.rascunho.informacoes.map(i => String(i.nome).trim());
  const faltam = variaveisEm(props.rascunho.endereco).filter(
    v => !nomes.includes(v)
  );
  if (!faltam.length) return '';
  return t(`${NS}.VAI_CRIAR`, {
    variaveis: faltam.map(v => `{{${v}}}`).join(', '),
  });
});
const preenchido = valor => String(valor ?? '').trim() !== '';
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
        @update:model-value="mudar('metodo', $event)"
      />
    </div>
    <FerramentaCampo
      :id="`${base}-endereco`"
      :rotulo="t(`${NS}.ENDERECO`)"
      :erro="erroDoEndereco ? t(`${NS}.ERRO.${erroDoEndereco}`) : ''"
      :ajuda="
        t(`${NS}.ENDERECO_AJUDA`, {
          variavel: VARIAVEL,
        })
      "
      :exemplo="enderecoDeExemplo(t)"
      exemplo-mono
      :preenchido="preenchido(rascunho.endereco)"
    >
      <template #default="{ descricao, invalido }">
        <FerramentaEntrada
          :id="`${base}-endereco`"
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
        <FerramentaFaixa v-if="avisoCriar" data-aviso-criar tom="azul" solta>
          <p class="m-0 break-words">{{ avisoCriar }}</p>
        </FerramentaFaixa>
      </template>
    </FerramentaCampo>
    <details
      class="group rounded-xl ring-1 ring-inset ring-n-weak"
      :open="Boolean(rascunho.slug || erros.slug)"
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
      </div>
    </details>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatAttributeDate } from 'dashboard/helper/attributeDate';
import { linkCompleto, linkSeguro, temValor } from '../../ficha/atributos';
import { useIdioma } from '../../ficha/idioma';
import BotaoCopiar from './BotaoCopiar.vue';

// #2894 — a lista "nome: valor" das informações. `linhas` vem de
// ficha/informacoes.js: { chave, valor, rotulo?, copiar? }. Sem `rotulo`, o nome
// vem do catálogo (`<raiz>.<CHAVE>`). O que falta mostra "Não informado" em cinza.
// `redes` são as redes sociais já preenchidas: { rede, usuario }.
// Sem nenhum valor e sem redes, mostra a frase de vazio em vez de uma lista de
// "Não informado".
// #3075 — os campos personalizados vêm com o `tipo` e o valor como está
// gravado: a data sai no formato do idioma, o número com a pontuação dele, o
// "sim ou não" escrito e o link abre numa aba nova (só http e https). Texto
// longo (`longo`, "Sobre a pessoa") mantém as quebras de linha.
const props = defineProps({
  linhas: { type: Array, required: true },
  raiz: { type: String, default: 'RELACIONAMENTOS_FICHA.INFORMACOES' },
  redes: { type: Array, default: () => [] },
});

const { t } = useI18n();
const idioma = useIdioma();
const semNada = computed(
  () =>
    !props.redes.length && props.linhas.every(linha => !temValor(linha.valor))
);

const rotuloDe = linha =>
  linha.rotulo || t(`${props.raiz}.${linha.chave.toUpperCase()}`);

const SIM = [true, 'true'];

const textoDe = ({ tipo, valor }) => {
  if (!temValor(valor)) return t('RELACIONAMENTOS.COMUM.NAO_INFORMADO');
  if (tipo === 'checkbox')
    return t(
      `RELACIONAMENTOS_FICHA.INFORMACOES.${SIM.includes(valor) ? 'SIM' : 'NAO'}`
    );
  if (tipo === 'date')
    return formatAttributeDate(valor, idioma.value) || String(valor);
  if (tipo === 'number' && Number.isFinite(Number(valor)))
    return new Intl.NumberFormat(idioma.value).format(Number(valor));
  return String(valor);
};

// O link gravado sem "https://" (antes desta tela) também abre.
const linkDe = linha =>
  linha.tipo === 'link' ? linkSeguro(linkCompleto(linha.valor)) : '';
</script>

<template>
  <p v-if="semNada" data-vazio class="m-0 text-base text-n-slate-11">
    {{ t('RELACIONAMENTOS_FICHA.INFORMACOES.VAZIO') }}
  </p>
  <dl v-else class="grid gap-4 m-0">
    <div
      v-for="linha in linhas"
      :key="linha.chave"
      :data-informacao="linha.chave"
      class="flex items-center justify-between gap-3 min-w-0"
    >
      <div class="min-w-0">
        <dt class="text-sm text-n-slate-11">
          {{ rotuloDe(linha) }}
        </dt>
        <dd
          class="m-0 text-base break-words tabular-nums"
          :class="[
            temValor(linha.valor) ? 'text-n-slate-12' : 'text-n-slate-10',
            { 'whitespace-pre-line': linha.longo },
          ]"
        >
          <a
            v-if="linkDe(linha)"
            :href="linkDe(linha)"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 -my-2.5 font-medium break-all text-n-blue-11 hover:underline min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            {{ linha.valor }}
            <span
              class="i-lucide-external-link size-4 shrink-0"
              aria-hidden="true"
            />
          </a>
          <template v-else>{{ textoDe(linha) }}</template>
        </dd>
      </div>
      <BotaoCopiar
        v-if="linha.copiar && linha.valor"
        :valor="linha.valor"
        :item="rotuloDe(linha)"
      />
    </div>
    <div v-for="item in redes" :key="item.rede" :data-informacao="item.rede">
      <dt class="text-sm text-n-slate-11">
        {{ t(`RELACIONAMENTOS_FICHA.GAVETA.REDE.${item.rede}`) }}
      </dt>
      <dd class="m-0 text-base break-words text-n-slate-12">
        {{ item.usuario }}
      </dd>
    </div>
  </dl>
</template>

<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import GavetaLateral from '../ficha/GavetaLateral.vue';
import CartoesDeEscolha from '../trazer/CartoesDeEscolha.vue';
import { TIPOS_DE_SEGURO, chaveDoTipo } from '../../carteira/tiposDeSeguro';
import {
  PASSOS_DE_FORA as PASSOS,
  QUER,
  useSeguroDeFora,
} from '../../carteira/useSeguroDeFora';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import CampoDoSeguro from './CampoDoSeguro.vue';
import SoltarPdf from './SoltarPdf.vue';

// #2899 (E6.5) — "Seguro de outra corretora": guardar quando termina o seguro
// que a pessoa tem em outro lugar, para chamar na hora certa. Uma coisa de cada
// vez: qual PDF, o que eu li, se a pessoa quer o lembrete. O botão do rodapé
// fica sempre ligado: sem a resposta, o clique diz o que falta. A cada etapa
// nova o foco vai ao título dela. O que está para conferir (o valor achado sem
// certeza) só entra se a pessoa ligar "Está certo".
const props = defineProps({
  aberta: { type: Boolean, default: false },
  pessoaId: { type: Number, required: true },
  fonte: { type: Object, required: true },
  // O primeiro nome de quem é o seguro, para as perguntas.
  nome: { type: String, default: '' },
});
const emit = defineEmits(['fechar', 'guardado']);

const { t } = useI18n();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.DE_FORA.${chave}`, valores);
const campo = chave => t(`RELACIONAMENTOS_CARTEIRA.CAMPOS.${chave}`);
const textos = useTextosDoSeguro();
const id = useId();
const ids = {
  tipo: `${id}-tipo`,
  seguradora: `${id}-seguradora`,
  termina: `${id}-termina`,
  corretora: `${id}-corretora`,
  quer: `${id}-quer`,
  faltaQuer: `${id}-falta-quer`,
};
const raiz = ref(null);

const seguro = useSeguroDeFora({
  fonte: props.fonte,
  pessoaId: () => props.pessoaId,
});
const { passo, formulario, naoAchou, falta, quer } = seguro;

watch(
  () => props.aberta,
  aberta => {
    if (aberta) seguro.abrir();
  }
);

// A cada etapa nova, o foco vai ao título dela.
watch(passo, async () => {
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-etapa]')?.focus();
});

const opcoesDeTipo = computed(() =>
  TIPOS_DE_SEGURO.map(tipo => ({ value: tipo, label: t(chaveDoTipo(tipo)) }))
);
const respostas = computed(() => [
  { id: QUER.SIM, rotulo: td('SIM') },
  { id: QUER.NAO, rotulo: td('NAO') },
]);
const falaComNome = chave =>
  props.nome ? td(chave, { nome: props.nome }) : td(`${chave}_SEM_NOME`);
const escrito = item =>
  item.valor === null || item.valor === undefined
    ? ''
    : textos.doCampo(item.campo, item.valor);

const focarOQueFalta = async () => {
  await nextTick();
  const primeiro = ['tipo', 'seguradora', 'termina'].find(
    nome => falta.value[nome]
  );
  const alvo = primeiro
    ? document.getElementById(ids[primeiro])
    : raiz.value?.querySelector('[role="radio"]');
  alvo?.focus();
};

const guardar = async () => {
  if (seguro.guardando.value) return;
  const guardado = await seguro.guardar();
  if (guardado) emit('guardado', guardado);
  else focarOQueFalta();
};
</script>

<template>
  <GavetaLateral
    :aberta="aberta"
    :titulo="td('TITULO')"
    marca="gaveta-de-fora"
    @fechar="emit('fechar')"
  >
    <div ref="raiz" data-carteira="de-fora" class="flex flex-col gap-6">
      <div v-if="passo === PASSOS.ABRINDO" data-carteira="carregando">
        <EsqueletoDeLista :linhas="3" />
      </div>
      <div v-else-if="passo === PASSOS.ERRO" data-carteira="erro">
        <ErroComTentarDeNovo
          :mensagem="td('ERRO_ABRIR')"
          @tentar="seguro.abrir"
        />
      </div>

      <template v-else-if="passo === PASSOS.ARQUIVO">
        <h3
          data-titulo-da-etapa
          tabindex="-1"
          class="m-0 text-xl font-semibold text-n-slate-12 focus:outline-none"
        >
          {{ td('QUAL_ARQUIVO') }}
        </h3>
        <p
          v-if="seguro.erro.value"
          role="alert"
          data-carteira="de-fora-erro"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ t(seguro.erro.value) }}
        </p>
        <Button
          v-if="seguro.podeTentarDeNovo.value"
          size="lg"
          class="self-start"
          data-carteira="de-fora-tentar"
          :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
          @click="seguro.tentarDeNovo"
        />
        <section
          v-if="seguro.arquivos.value.length"
          class="flex flex-col gap-2"
          :aria-labelledby="`${id}-da-conversa`"
        >
          <h4
            :id="`${id}-da-conversa`"
            class="m-0 text-base font-medium text-n-slate-12"
          >
            {{ td('DA_CONVERSA') }}
          </h4>
          <ul class="flex flex-col gap-2 p-0 m-0 list-none">
            <li v-for="arquivo in seguro.arquivos.value" :key="arquivo.id">
              <button
                type="button"
                data-carteira="de-fora-arquivo"
                class="flex items-center w-full gap-3 px-4 py-3 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
                @click="seguro.ler({ anexoId: arquivo.id })"
              >
                <span
                  class="i-lucide-file-text size-5 shrink-0 text-n-blue-11"
                  aria-hidden="true"
                />
                <span class="flex flex-col min-w-0">
                  <span class="text-base break-all text-n-slate-12">
                    {{ arquivo.nome }}
                  </span>
                  <span class="text-sm text-n-slate-11">
                    {{ textos.dataInteira(arquivo.quando) }}
                  </span>
                </span>
              </button>
            </li>
          </ul>
        </section>
        <SoltarPdf
          :apoio="td('APOIO')"
          @arquivo="seguro.ler({ arquivo: $event })"
        />
      </template>

      <div
        v-else-if="passo === PASSOS.LENDO"
        data-carteira="de-fora-lendo"
        role="status"
        class="flex flex-col gap-4"
      >
        <p
          data-titulo-da-etapa
          tabindex="-1"
          class="m-0 text-lg text-n-slate-12 focus:outline-none"
        >
          {{ td('LENDO') }}
        </p>
        <EsqueletoDeLista :linhas="3" />
      </div>

      <template v-else>
        <section data-carteira="de-fora-lido" class="flex flex-col gap-4">
          <h3
            data-titulo-da-etapa
            tabindex="-1"
            class="m-0 text-xl font-semibold text-n-slate-12 focus:outline-none"
          >
            {{ td('O_QUE_LI') }}
          </h3>
          <p class="m-0 text-base text-n-slate-11">{{ td('CONFIRA_APOIO') }}</p>
          <div class="flex flex-col gap-1.5">
            <label :for="ids.tipo" class="text-sm font-medium text-n-slate-12">
              {{ campo('TIPO') }}
            </label>
            <ChoiceSelect
              :model-value="formulario.tipo"
              :trigger-id="ids.tipo"
              :options="opcoesDeTipo"
              :aria-label="campo('TIPO')"
              :placeholder="td('ESCOLHA')"
              :invalid="falta.tipo"
              :described-by="falta.tipo ? `${ids.tipo}-falta` : undefined"
              @update:model-value="seguro.mudar('tipo', $event)"
            />
            <p
              v-if="falta.tipo"
              :id="`${ids.tipo}-falta`"
              role="alert"
              data-carteira="falta"
              class="m-0 text-sm text-n-ruby-11"
            >
              {{ td('FALTA_TIPO') }}
            </p>
          </div>
          <CampoDoSeguro
            :id="ids.seguradora"
            type="text"
            autocomplete="off"
            :model-value="formulario.seguradora"
            :rotulo="campo('SEGURADORA')"
            :placeholder="td('NAO_ACHEI')"
            :falta="falta.seguradora ? td('FALTA_SEGURADORA') : ''"
            @update:model-value="seguro.mudar('seguradora', $event)"
          />
          <CampoDoSeguro
            :id="ids.termina"
            type="date"
            :model-value="formulario.termina"
            :rotulo="campo('TERMINA')"
            :falta="falta.termina ? td('FALTA_TERMINA') : ''"
            @update:model-value="seguro.mudar('termina', $event)"
          />
          <p
            v-if="naoAchou.includes('termina') && !falta.termina"
            data-carteira="de-fora-nao-achei"
            class="m-0 -mt-2 text-sm text-n-slate-11"
          >
            {{ td('NAO_ACHEI_DATA') }}
          </p>
          <CampoDoSeguro
            :id="ids.corretora"
            type="text"
            autocomplete="off"
            :model-value="formulario.corretora"
            :rotulo="td('CORRETORA')"
            :placeholder="td('NAO_ACHEI')"
            @update:model-value="seguro.mudar('corretora', $event)"
          />
          <div
            v-if="seguro.tambem.value.length"
            data-carteira="de-fora-tambem"
            class="flex flex-col gap-2"
          >
            <h4 class="m-0 text-base font-medium text-n-slate-12">
              {{ td('TAMBEM') }}
            </h4>
            <ul class="flex flex-col gap-2 p-0 m-0 list-none">
              <li
                v-for="item in seguro.tambem.value"
                :key="item.campo"
                :data-tambem="item.campo"
                class="flex flex-col gap-1"
              >
                <span
                  :id="`${id}-${item.campo}`"
                  class="text-base text-n-slate-12"
                >
                  {{
                    td('CAMPO_E_VALOR', {
                      campo: campo(item.campo.toUpperCase()),
                      valor: escrito(item),
                    })
                  }}
                </span>
                <template v-if="item.confira">
                  <span data-carteira="confira" class="text-sm text-n-amber-11">
                    {{ td('CONFIRA') }}
                  </span>
                  <button
                    type="button"
                    role="switch"
                    data-carteira="esta-certo"
                    :aria-checked="
                      seguro.confirmados.value.includes(item.campo)
                    "
                    :aria-labelledby="`${id}-${item.campo} ${id}-${item.campo}-certo`"
                    class="inline-flex items-center self-start gap-2 px-3 text-sm font-medium border rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      seguro.confirmados.value.includes(item.campo)
                        ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-12'
                        : 'border-n-weak bg-n-solid-1 text-n-slate-12'
                    "
                    @click="seguro.trocarConfirmado(item.campo)"
                  >
                    <span
                      aria-hidden="true"
                      class="size-4"
                      :class="
                        seguro.confirmados.value.includes(item.campo)
                          ? 'i-lucide-check-square'
                          : 'i-lucide-square'
                      "
                    />
                    <span :id="`${id}-${item.campo}-certo`">
                      {{ td('ESTA_CERTO') }}
                    </span>
                  </button>
                </template>
              </li>
            </ul>
          </div>
          <Button
            link
            size="lg"
            class="self-start min-h-11"
            data-carteira="de-fora-outro-arquivo"
            :label="td('OUTRO_ARQUIVO')"
            @click="seguro.outroArquivo"
          />
        </section>

        <section data-carteira="de-fora-quer" class="flex flex-col gap-4">
          <h3 :id="ids.quer" class="m-0 text-xl font-semibold text-n-slate-12">
            {{ falaComNome('QUER') }}
          </h3>
          <p class="m-0 text-base text-n-slate-11">
            {{ td('QUER_APOIO') }}
          </p>
          <CartoesDeEscolha
            :model-value="quer"
            :opcoes="respostas"
            :rotulo-id="ids.quer"
            :invalido="falta.quer"
            :descrito-por="falta.quer ? ids.faltaQuer : undefined"
            @update:model-value="seguro.responder"
          />
          <p
            v-if="falta.quer"
            :id="ids.faltaQuer"
            role="alert"
            data-carteira="falta"
            class="m-0 text-base font-medium text-n-ruby-11"
          >
            {{ falaComNome('FALTA_RESPOSTA') }}
          </p>
          <p
            v-if="seguro.erro.value"
            role="alert"
            data-carteira="de-fora-erro"
            class="m-0 text-base font-medium text-n-ruby-11"
          >
            {{ t(seguro.erro.value) }}
          </p>
        </section>
      </template>
    </div>

    <template v-if="passo === PASSOS.LIDO" #rodape>
      <Button
        size="lg"
        data-carteira="guardar-seguro-de-fora"
        :label="td('GUARDAR')"
        :is-loading="seguro.guardando.value"
        @click="guardar"
      />
    </template>
  </GavetaLateral>
</template>

<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import GavetaLateral from '../ficha/GavetaLateral.vue';
import CartoesDeEscolha from '../trazer/CartoesDeEscolha.vue';
import SoltarArquivo from '../trazer/SoltarArquivo.vue';
import { ACEITA_APOLICES } from '../../carteira/arquivosDeApolice';
import { TIPOS_DE_SEGURO, chaveDoTipo } from '../../carteira/tiposDeSeguro';
import {
  PASSOS_DE_FORA as PASSOS,
  QUER,
  primeiroNomeDe,
  useSeguroDeFora,
} from '../../carteira/useSeguroDeFora';
import CampoDoSeguro from './CampoDoSeguro.vue';

// #2897 — "Seguro de outra corretora" (Tela 20): guardar quando termina o
// seguro que a pessoa tem em outro lugar, para chamar na hora certa. Uma coisa
// de cada vez: qual arquivo, o que li, se a pessoa quer o lembrete. O botão do
// rodapé fica sempre ligado: sem a resposta, o clique diz o que falta.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  pessoaId: { type: Number, required: true },
  fonte: { type: Object, required: true },
  // Na conversa, quem está falando é o contato dela: a pergunta, o aviso e a
  // faixa usam o primeiro nome dele. Sem isso, vale o nome da ficha.
  nomeDoContato: { type: String, default: '' },
});
const emit = defineEmits(['fechar', 'guardado', 'perguntar']);

const { t } = useI18n();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.DE_FORA.${chave}`, valores);
const campo = chave => t(`RELACIONAMENTOS_CARTEIRA.PDF.CAMPOS.${chave}`);
const id = useId();
const ids = {
  tipo: `${id}-tipo`,
  seguradora: `${id}-seguradora`,
  termina: `${id}-termina`,
  quer: `${id}-quer`,
  faltaQuer: `${id}-falta-quer`,
};
const raiz = ref(null);

const seguro = useSeguroDeFora({
  fonte: props.fonte,
  pessoaId: () => props.pessoaId,
});
const { passo, lido, naoAchou, falta, quer } = seguro;
const nome = computed(
  () => primeiroNomeDe(props.nomeDoContato) || seguro.primeiroNome.value
);

watch(
  () => props.aberta,
  aberta => {
    if (aberta) seguro.abrir();
  }
);

const opcoesDeTipo = computed(() =>
  TIPOS_DE_SEGURO.map(tipo => ({ value: tipo, label: t(chaveDoTipo(tipo)) }))
);
const respostas = computed(() => [
  { id: QUER.SIM, rotulo: td('SIM') },
  { id: QUER.AINDA_NAO, rotulo: td('AINDA_NAO') },
]);
const aindaNaoPerguntou = computed(() => quer.value === QUER.AINDA_NAO);

const focarOQueFalta = async () => {
  await nextTick();
  const alvo = falta.value.termina
    ? document.getElementById(ids.termina)
    : raiz.value?.querySelector('[role="radio"]');
  alvo?.focus();
};

const guardar = async () => {
  if (seguro.guardando.value) return;
  const guardado = await seguro.guardar();
  if (guardado) emit('guardado', { seguro: guardado, nome: nome.value });
  else focarOQueFalta();
};
</script>

<template>
  <GavetaLateral
    :aberta="aberta"
    :titulo="td('TITULO')"
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
        <h3 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ td('QUAL_ARQUIVO') }}
        </h3>
        <p
          v-if="seguro.erro.value"
          role="alert"
          data-carteira="de-fora-erro"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ td(seguro.erro.value) }}
        </p>
        <ul
          v-if="seguro.arquivos.value.length"
          :aria-label="td('ARQUIVOS')"
          class="flex flex-col gap-2 p-0 m-0 list-none"
        >
          <li v-for="arquivo in seguro.arquivos.value" :key="arquivo.nome">
            <button
              type="button"
              data-carteira="de-fora-arquivo"
              class="flex items-center w-full gap-3 px-4 py-3 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              @click="seguro.escolher(arquivo)"
            >
              <span
                class="i-lucide-file-text size-5 shrink-0 text-n-blue-11"
                aria-hidden="true"
              />
              <span class="text-base break-all text-n-slate-12">
                {{ arquivo.nome }}
              </span>
            </button>
          </li>
        </ul>
        <p v-else class="m-0 text-base text-n-slate-11">
          {{ td('SEM_ARQUIVOS') }}
        </p>
        <SoltarArquivo
          icone="i-lucide-file-up"
          :titulo="
            td(seguro.arquivos.value.length ? 'SOLTAR' : 'SOLTAR_SEM_LISTA')
          "
          :apoio="t('RELACIONAMENTOS_CARTEIRA.TRAZER.PDFS.APOIO')"
          :aceita="ACEITA_APOLICES"
          @arquivo="seguro.escolher({ nome: $event.name })"
        />
      </template>

      <div
        v-else-if="passo === PASSOS.LENDO"
        data-carteira="de-fora-lendo"
        role="status"
        class="flex flex-col gap-4"
      >
        <p class="m-0 text-lg text-n-slate-12">{{ td('LENDO') }}</p>
        <EsqueletoDeLista :linhas="3" />
      </div>

      <template v-else>
        <section data-carteira="de-fora-lido" class="flex flex-col gap-4">
          <h3 class="m-0 text-xl font-semibold text-n-slate-12">
            {{ td('O_QUE_LI') }}
          </h3>
          <div class="flex flex-col gap-1.5">
            <label :for="ids.tipo" class="text-sm font-medium text-n-slate-12">
              {{ campo('TIPO') }}
            </label>
            <ChoiceSelect
              :model-value="lido.tipo"
              :trigger-id="ids.tipo"
              :options="opcoesDeTipo"
              :aria-label="campo('TIPO')"
              @update:model-value="seguro.mudar('tipo', $event)"
            />
          </div>
          <CampoDoSeguro
            :id="ids.seguradora"
            type="text"
            :model-value="lido.seguradora"
            :rotulo="campo('SEGURADORA')"
            :placeholder="td('NAO_ACHEI')"
            @update:model-value="seguro.mudar('seguradora', $event)"
          />
          <CampoDoSeguro
            :id="ids.termina"
            type="date"
            :model-value="lido.termina"
            :rotulo="campo('TERMINA')"
            :falta="falta.termina ? td('FALTA_TERMINA') : ''"
            @update:model-value="seguro.mudar('termina', $event)"
          />
          <p
            v-if="naoAchou.includes('termina') && !falta.termina"
            data-carteira="de-fora-nao-achei"
            class="m-0 -mt-2 text-sm text-n-slate-11"
          >
            {{ td('NAO_ACHEI') }}
          </p>
          <Button
            link
            size="lg"
            class="self-start"
            data-carteira="de-fora-outro-arquivo"
            :label="td('OUTRO_ARQUIVO')"
            @click="seguro.outroArquivo"
          />
        </section>

        <section data-carteira="de-fora-quer" class="flex flex-col gap-4">
          <h3 :id="ids.quer" class="m-0 text-xl font-semibold text-n-slate-12">
            {{ td('QUER', { nome }) }}
          </h3>
          <CartoesDeEscolha
            :model-value="quer"
            :opcoes="respostas"
            :rotulo-id="ids.quer"
            duas-colunas
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
            {{ td('FALTA_RESPOSTA', { nome }) }}
          </p>
          <p
            v-if="seguro.erro.value"
            role="alert"
            data-carteira="de-fora-erro"
            class="m-0 text-base font-medium text-n-ruby-11"
          >
            {{ td(seguro.erro.value) }}
          </p>
        </section>
      </template>
    </div>

    <template v-if="passo === PASSOS.LIDO" #rodape>
      <Button
        v-if="aindaNaoPerguntou"
        size="lg"
        data-carteira="de-fora-perguntar"
        :label="td('PERGUNTAR')"
        @click="emit('perguntar')"
      />
      <Button
        v-else
        size="lg"
        data-carteira="guardar-lembrete"
        :label="td('GUARDAR')"
        :is-loading="seguro.guardando.value"
        :disabled="seguro.guardando.value"
        @click="guardar"
      />
    </template>
  </GavetaLateral>
</template>

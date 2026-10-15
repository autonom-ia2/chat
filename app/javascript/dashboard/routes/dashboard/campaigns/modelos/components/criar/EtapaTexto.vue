<script setup>
import { andarComSetas } from '../../helpers/setas';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { CODIGO_DE_EXEMPLO } from '../../constants';
import {
  camposUsados,
  contarLetras,
  limiteDoTexto,
} from '../../helpers/conteudo';
import ModeloEditorTexto from '../ModeloEditorTexto.vue';
import ModeloMelhorarComIA from '../ModeloMelhorarComIA.vue';
import CustoDoTipo from '../CustoDoTipo.vue';
import {
  exemploDoCampo,
  ligacaoDoCatalogo,
  useRotuloDoCampo,
} from '../../helpers/campos';
import { useCanUseIA } from '../../helpers/useCanUseIA';

const props = defineProps({
  // Na correção: marca a caixa de texto enquanto o problema existir.
  destacarFim: { type: Boolean, default: false },
  // Modelo novo do zero ou cópia: a pessoa diz o tipo. Alterar e corrigir não
  // perguntam: a Meta não deixa trocar o tipo de um modelo que existe (#1394).
  perguntarTipo: { type: Boolean, default: false },
  // Alterar ou corrigir (#1394): o tipo que a Meta tem, travado (a Meta não deixa
  // trocar). Vazio: a tela não mostra o tipo aqui.
  tipoTravado: { type: String, default: '' },
  // Para onde vai "crie um modelo novo com este texto" (null: sem a saída).
  criarNovoCom: { type: Object, default: null },
  // Nome já usado na mesma conta do WhatsApp: a sugestão de outro (ou '').
  nomeRepetido: { type: String, default: '' },
  // Corrigir um recusado: o motivo, para o "Melhorar com IA" (#1333).
  recusa: { type: String, default: '' },
  // Cópia para mudar o tipo (#1394): a mesma conta não aceita texto igual, então
  // a etapa pede, antes do editor, para mudar pelo menos uma palavra.
  pedirTextoNovo: { type: Boolean, default: false },
});

// Nome, texto e exemplos.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const { t } = useI18n();
const rotulo = useRotuloDoCampo();
// Gaveta "Melhorar com IA" (#1333): só para quem cria modelo.
const podeUsarIA = useCanUseIA();
const melhorando = ref(false);

const conteudo = computed(() => rascunho.value.conteudo);
const campos = computed(() => camposUsados(conteudo.value.texto));
const letras = computed(() => contarLetras(conteudo.value.texto));
const limite = computed(() => limiteDoTexto(conteudo.value));
// Código de verificação: o texto vem fixo do WhatsApp.
const textoFixo = computed(() => conteudo.value.formato === 'codigo');

const { currentAccount } = useAccount();
// "Nome da empresa" é o nome da conta no Chat2You (texto fixo, dá para trocar).
const exemploPadrao = campo =>
  campo === 'nome_empresa' && currentAccount.value?.name
    ? currentAccount.value.name
    : exemploDoCampo(t, campo);

// Texto novo: todo campo usado ganha exemplo (o que já tinha fica). Uma troca só
// por vez no rascunho: o valor do v-model só muda depois que a página atualiza.
const comTexto = (texto, extras = {}) => ({
  ...rascunho.value,
  ...extras,
  conteudo: {
    ...conteudo.value,
    texto,
    exemplos: Object.fromEntries(
      camposUsados(texto).map(campo => [
        campo,
        conteudo.value.exemplos[campo] ?? exemploPadrao(campo),
      ])
    ),
  },
});

const mudarTexto = texto => {
  rascunho.value = comTexto(texto);
};

const mudarExemplo = (campo, valor) => {
  rascunho.value = {
    ...rascunho.value,
    conteudo: {
      ...conteudo.value,
      exemplos: { ...conteudo.value.exemplos, [campo]: valor },
    },
  };
};

const mudarNome = nome => {
  rascunho.value = { ...rascunho.value, nome };
};

// De onde vem o valor de cada campo quando o modelo for usado numa campanha.
const fonteDoCampo = campo => {
  if (campo === 'nome_empresa') {
    return t('MODELOS_WHATSAPP.TEXTO.NOME_DA_EMPRESA', {
      conta: currentAccount.value?.name || '',
    });
  }
  return ligacaoDoCatalogo(campo)
    ? t('MODELOS_WHATSAPP.TEXTO.FONTE_CADASTRO')
    : t('MODELOS_WHATSAPP.TEXTO.FONTE_COLUNA');
};

// "Começar do zero": a pessoa diz o tipo (aviso ou divulgação), sem padrão.
const TIPOS_DO_ZERO = ['aviso', 'divulgacao'];
const escolherTipo = tipo => {
  rascunho.value = { ...rascunho.value, tipo };
};

// "Usar" na gaveta: o texto novo entra (os exemplos que a pessoa já tinha
// ficam) e o tipo passa a ser o que a resposta prevê.
const usarMelhoria = resposta => {
  // Tipo travado (alterar/corrigir): a resposta não troca o tipo.
  rascunho.value = comTexto(
    resposta.texto,
    props.tipoTravado ? {} : { tipo: resposta.tipo }
  );
  melhorando.value = false;
};
</script>

<template>
  <div data-etapa-texto class="flex flex-col gap-7">
    <Input
      wrap-message
      :model-value="rascunho.nome"
      data-nome
      :label="$t('MODELOS_WHATSAPP.TEXTO.NOME')"
      :message="
        nomeRepetido
          ? $t('MODELOS_WHATSAPP.TEXTO.NOME_REPETIDO', {
              sugestao: nomeRepetido,
            })
          : $t('MODELOS_WHATSAPP.TEXTO.NOME_AJUDA')
      "
      :message-type="nomeRepetido ? 'error' : 'info'"
      @update:model-value="mudarNome"
    />

    <section v-if="perguntarTipo" data-tipo-do-zero class="flex flex-col gap-3">
      <h2 id="tipo-do-zero" class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.TEXTO.TIPO.PERGUNTA') }}
      </h2>
      <div
        role="radiogroup"
        aria-labelledby="tipo-do-zero"
        class="grid gap-3 sm:grid-cols-2"
        @keydown="andarComSetas"
      >
        <button
          v-for="tipo in TIPOS_DO_ZERO"
          :key="tipo"
          type="button"
          role="radio"
          :data-tipo="tipo"
          :aria-checked="rascunho.tipo === tipo"
          class="flex flex-col items-start gap-1 p-4 text-start rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            rascunho.tipo === tipo
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-blue-6'
          "
          @click="escolherTipo(tipo)"
        >
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">
            {{ $t(`MODELOS_WHATSAPP.TEXTO.TIPO.${tipo}.ROTULO`) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`MODELOS_WHATSAPP.TEXTO.TIPO.${tipo}.PARA`) }}
          </span>
        </button>
      </div>
    </section>

    <section
      v-if="tipoTravado"
      data-tipo-travado
      class="flex flex-col gap-3 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.TEXTO.TIPO_TRAVADO.TITULO') }}
      </h2>
      <CustoDoTipo :tipo="tipoTravado" />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.TEXTO.TIPO_TRAVADO.NAO_MUDA') }}
      </p>
      <router-link
        v-if="criarNovoCom"
        data-criar-novo-com-texto
        :to="criarNovoCom"
        class="inline-flex items-center self-start gap-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
      >
        <span class="i-lucide-copy-plus size-4" aria-hidden="true" />
        {{ $t('MODELOS_WHATSAPP.TEXTO.TIPO_TRAVADO.CRIAR_NOVO') }}
      </router-link>
    </section>

    <section class="flex flex-col gap-3">
      <div class="flex flex-wrap items-end justify-between gap-2">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.TEXTO.MENSAGEM') }}
        </h2>
        <Button
          v-if="podeUsarIA && !textoFixo && conteudo.texto.length"
          data-melhorar-com-ia
          :label="$t('MODELOS_WHATSAPP.IA.MELHORAR_COM_IA')"
          icon="i-lucide-sparkles"
          variant="faded"
          size="sm"
          class="min-h-11"
          @click="melhorando = true"
        />
      </div>

      <div
        v-if="textoFixo"
        data-texto-fixo
        class="flex flex-col gap-3 p-5 rounded-xl bg-n-violet-2 ring-1 ring-inset ring-n-violet-6"
      >
        <p class="mb-0 text-base leading-relaxed text-n-slate-12">
          <strong class="font-semibold">{{ CODIGO_DE_EXEMPLO }}</strong>
          {{ $t('MODELOS_WHATSAPP.FORMATOS.codigo.TEXTO_FIXO') }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.FORMATOS.codigo.PARA_QUE_SERVE') }}
        </p>
      </div>

      <template v-else>
        <p
          v-if="pedirTextoNovo"
          data-mudar-texto
          class="flex items-start gap-2.5 mb-0 text-[0.9375rem] text-n-slate-11"
        >
          <span
            class="i-lucide-info mt-0.5 size-5 shrink-0 text-n-blue-10"
            aria-hidden="true"
          />
          {{ $t('MODELOS_WHATSAPP.TEXTO.MUDAR_O_TEXTO') }}
        </p>
        <ModeloEditorTexto
          :model-value="conteudo.texto"
          :rotulo="$t('MODELOS_WHATSAPP.TEXTO.MENSAGEM')"
          :destacar-fim="destacarFim"
          @update:model-value="mudarTexto"
        />
        <p
          class="mb-0 text-sm text-end"
          :class="letras > limite ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{
            $t('MODELOS_WHATSAPP.TEXTO.LETRAS', {
              n: letras,
              limite,
            })
          }}
        </p>
      </template>
    </section>

    <section
      v-if="campos.length && !textoFixo"
      data-exemplos
      class="flex flex-col gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <div>
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.TEXTO.EXEMPLOS') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.TEXTO.EXEMPLOS_AJUDA') }}
        </p>
      </div>
      <div class="grid gap-4 sm:grid-cols-2">
        <div
          v-for="campo in campos"
          :key="campo"
          class="flex flex-col gap-1 min-w-0"
        >
          <Input
            wrap-message
            :data-exemplo="campo"
            :model-value="conteudo.exemplos[campo] || ''"
            :label="rotulo(campo)"
            :message-type="conteudo.exemplos[campo] ? 'info' : 'error'"
            :message="
              conteudo.exemplos[campo]
                ? ''
                : $t('MODELOS_WHATSAPP.TEXTO.SEM_EXEMPLO')
            "
            @update:model-value="valor => mudarExemplo(campo, valor)"
          />
          <!-- De onde vem o valor de verdade na campanha (texto que quebra linha). -->
          <p :data-fonte="campo" class="mb-0 text-xs text-n-slate-11">
            {{ fonteDoCampo(campo) }}
          </p>
        </div>
      </div>
    </section>
    <ModeloMelhorarComIA
      v-if="podeUsarIA && melhorando"
      :rascunho="rascunho"
      :tipo-travado="tipoTravado"
      :recusa="recusa"
      @usar="usarMelhoria"
      @fechar="melhorando = false"
    />
  </div>
</template>

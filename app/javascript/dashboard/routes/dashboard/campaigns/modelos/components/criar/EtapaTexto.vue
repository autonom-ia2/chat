<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  CODIGO_DE_EXEMPLO,
  LIMITE_DO_TEXTO,
  LIMITE_DO_TEXTO_DA_OFERTA,
} from '../../constants';
import { camposUsados, contarLetras } from '../../helpers/conteudo';
import ModeloEditorTexto from '../ModeloEditorTexto.vue';
import ModeloMelhorarComIA from '../ModeloMelhorarComIA.vue';
import { exemploDoCampo, useRotuloDoCampo } from '../../helpers/campos';
import { useCanUseIA } from '../../helpers/useCanUseIA';

defineProps({
  // Na correção: marca a caixa de texto enquanto o problema existir.
  destacarFim: { type: Boolean, default: false },
  // Modelo novo do zero, cópia ou correção de recusado: a pessoa diz o tipo. Num
  // modelo aprovado a Meta não deixa trocar o tipo, então não pergunta.
  perguntarTipo: { type: Boolean, default: false },
});

// Nome, texto e exemplos.
const rascunho = defineModel('rascunho', { type: Object, required: true });

const { t } = useI18n();
const rotulo = useRotuloDoCampo();
// Gaveta "Melhorar com IA" (entrega E, #1333): escondida enquanto não existir.
const podeUsarIA = useCanUseIA();
const melhorando = ref(false);

const conteudo = computed(() => rascunho.value.conteudo);
const campos = computed(() => camposUsados(conteudo.value.texto));
const letras = computed(() => contarLetras(conteudo.value.texto));
const limite = computed(() =>
  conteudo.value.formato === 'oferta'
    ? LIMITE_DO_TEXTO_DA_OFERTA
    : LIMITE_DO_TEXTO
);
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

// "Começar do zero": a pessoa diz o tipo (aviso ou divulgação), sem padrão.
const TIPOS_DO_ZERO = ['aviso', 'divulgacao'];
const escolherTipo = tipo => {
  rascunho.value = { ...rascunho.value, tipo };
};

// "Usar" na gaveta: o texto novo entra (os exemplos que a pessoa já tinha
// ficam) e o tipo passa a ser o que a resposta prevê.
const usarMelhoria = resposta => {
  rascunho.value = comTexto(resposta.texto, { tipo: resposta.tipo });
  melhorando.value = false;
};
</script>

<template>
  <div data-etapa-texto class="flex flex-col gap-7">
    <Input
      :model-value="rascunho.nome"
      data-nome
      :label="$t('MODELOS_WHATSAPP.TEXTO.NOME')"
      :message="$t('MODELOS_WHATSAPP.TEXTO.NOME_AJUDA')"
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

    <section class="flex flex-col gap-3">
      <div class="flex flex-wrap items-end justify-between gap-2">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.TEXTO.MENSAGEM') }}
        </h2>
        <Button
          v-if="podeUsarIA && !textoFixo"
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
        <Input
          v-for="campo in campos"
          :key="campo"
          :data-exemplo="campo"
          :model-value="conteudo.exemplos[campo] || ''"
          :label="rotulo(campo)"
          :message-type="conteudo.exemplos[campo] ? 'info' : 'error'"
          :message="
            !conteudo.exemplos[campo]
              ? $t('MODELOS_WHATSAPP.TEXTO.SEM_EXEMPLO')
              : campo === 'nome_empresa'
                ? $t('MODELOS_WHATSAPP.TEXTO.NOME_DA_EMPRESA', {
                    conta: currentAccount?.name || '',
                  })
                : ''
          "
          @update:model-value="valor => mudarExemplo(campo, valor)"
        />
      </div>
    </section>
    <ModeloMelhorarComIA
      v-if="podeUsarIA && melhorando"
      :rascunho="rascunho"
      @usar="usarMelhoria"
      @fechar="melhorando = false"
    />
  </div>
</template>

<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreCelular from './LivreCelular.vue';
import { ALVOS_DE_ENSAIO } from '../prototipo/dados';
import { ensaiar } from '../prototipo/ensaio';
import { fraseDoPasso, rotuloDoCaminho } from '../prototipo/frases';

// #2414 F0 — "Ensaiar": escolhe uma conversa ou um cartão e vê, passo a passo,
// o que a automação faria. A mensagem aparece no celular simulado. Nada é
// executado.
const props = defineProps({
  receita: { type: Object, required: true },
  automacaoId: { type: Number, default: null },
});

const alvoId = defineModel('alvo', { type: [String, Number], default: '' });

const { t } = useI18n();
const id = useId();

// Os alvos de exemplo de cada automação; sem ela, qualquer cartão.
const alvos = computed(() =>
  ALVOS_DE_ENSAIO.filter(alvo =>
    props.automacaoId
      ? alvo.automacoes.includes(props.automacaoId)
      : alvo.tipo === 'cartao'
  )
);
// Passo dentro de um caminho fica recuado, como no editor.
const RECUO = ['', 'ms-6', 'ms-12'];
const opcoes = computed(() =>
  alvos.value.map(alvo => ({
    value: alvo.id,
    label: alvo.nome,
    hint: t(`AUTOMACAO_LIVRE.ENSAIO.${alvo.detalheChave}`, alvo.detalhe),
  }))
);

const alvo = computed(
  () =>
    alvos.value.find(item => item.id === Number(alvoId.value)) ||
    alvos.value[0] ||
    null
);
const resultado = computed(() => ensaiar(props.receita, alvo.value));
const mensagens = computed(() =>
  resultado.value.linhas
    .filter(linha => linha.mensagem)
    .map(linha => linha.mensagem)
);
</script>

<template>
  <section data-ensaio class="flex flex-col gap-5">
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('AUTOMACAO_LIVRE.ENSAIO.EXPLICA') }}
    </p>
    <div class="flex flex-col gap-1.5">
      <label :for="id" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ENSAIO.ESCOLHA') }}
      </label>
      <ChoiceSelect
        :model-value="alvo?.id ?? ''"
        :trigger-id="id"
        :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.ESCOLHA')"
        :options="opcoes"
        @update:model-value="novo => (alvoId = String(novo))"
      />
      <p v-if="alvo" class="mb-0 text-sm text-n-slate-11">
        {{ $t(`AUTOMACAO_LIVRE.ENSAIO.${alvo.detalheChave}`, alvo.detalhe) }}
      </p>
    </div>

    <div
      v-if="alvo"
      class="grid items-start gap-6 md:grid-cols-[minmax(0,1fr)_18rem]"
    >
      <div class="flex flex-col gap-2">
        <p
          v-if="!resultado.comeca"
          data-nao-comeca
          class="p-4 mb-0 text-[0.9375rem] rounded-xl bg-n-amber-2 text-n-slate-12"
        >
          {{
            $t(`AUTOMACAO_LIVRE.ENSAIO.${alvo.naoComecaChave}`, alvo.naoComeca)
          }}
        </p>
        <ol v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="(linha, indice) in resultado.linhas"
            :key="indice"
            data-faria
            class="flex flex-col gap-1"
            :class="RECUO[Math.min(linha.nivel, 2)]"
          >
            <div
              class="flex items-start gap-3 px-4 py-3 border rounded-xl bg-n-solid-1"
              :class="linha.semVolta ? 'border-n-amber-6' : 'border-n-weak'"
            >
              <span
                class="mt-0.5 size-5 shrink-0"
                :class="
                  linha.caminho
                    ? 'i-lucide-git-branch text-n-violet-11'
                    : 'i-lucide-check text-n-teal-11'
                "
                aria-hidden="true"
              />
              <span class="flex flex-col min-w-0 gap-0.5">
                <span class="text-[0.9375rem] text-n-slate-12">
                  {{
                    $t('AUTOMACAO_LIVRE.ENSAIO.FARIA', {
                      frase: fraseDoPasso(linha.passo, t),
                    })
                  }}
                </span>
                <span
                  v-if="linha.caminho"
                  class="text-sm font-medium text-n-violet-11"
                >
                  {{
                    $t('AUTOMACAO_LIVRE.ENSAIO.SEGUIRIA', {
                      caminho: rotuloDoCaminho(linha.passo, linha.caminho, t),
                    })
                  }}
                </span>
                <span v-if="linha.semVolta" class="text-xs text-n-amber-11">
                  {{ $t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA') }}
                </span>
              </span>
            </div>
          </li>
        </ol>
      </div>
      <LivreCelular
        :contato="alvo.nome"
        :mensagens="mensagens"
        :valores="alvo.valores"
      />
    </div>
  </section>
</template>

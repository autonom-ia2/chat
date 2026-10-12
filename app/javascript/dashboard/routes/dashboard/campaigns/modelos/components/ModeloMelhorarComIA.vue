<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import api from '../api/modelosWhatsapp';
import CustoDoTipo from './CustoDoTipo.vue';

// Melhorar com IA: a gaveta (foco preso, Esc fecha) com o que a pessoa quer
// melhorar, o antes e o depois lado a lado, e "Usar" ou "Manter o meu".
const props = defineProps({
  rascunho: { type: Object, required: true },
});

const emit = defineEmits(['usar', 'fechar']);

const PEDIDOS = [
  { chave: 'mais_curto', icone: 'i-lucide-scissors' },
  { chave: 'mais_claro', icone: 'i-lucide-lightbulb' },
  { chave: 'manter_aviso', icone: 'i-lucide-piggy-bank' },
  { chave: 'corrigir_recusa', icone: 'i-lucide-shield-check' },
];

const pedido = ref('mais_claro');
const estado = ref('pedindo');
const resposta = ref(null);

const melhorar = async () => {
  estado.value = 'escrevendo';
  try {
    resposta.value = await api.melhorarComIA({
      texto: props.rascunho.conteudo.texto,
      pedido: pedido.value,
      objetivo: props.rascunho.objetivo,
      tipo: props.rascunho.tipo,
    });
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};
</script>

<template>
  <AgenteGaveta
    :titulo="$t('MODELOS_WHATSAPP.IA.MELHORAR_TITULO')"
    larga
    @fechar="emit('fechar')"
  >
    <div data-melhorar-ia class="flex flex-col gap-5">
      <div
        role="radiogroup"
        :aria-label="$t('MODELOS_WHATSAPP.IA.MELHORAR_O_QUE')"
        class="grid gap-2 sm:grid-cols-2"
      >
        <button
          v-for="item in PEDIDOS"
          :key="item.chave"
          type="button"
          role="radio"
          :data-pedido-ia="item.chave"
          :aria-checked="pedido === item.chave"
          class="flex items-center gap-2.5 p-3 text-sm font-medium text-start rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            pedido === item.chave
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
              : 'ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-blue-6'
          "
          @click="pedido = item.chave"
        >
          <span
            class="size-5 shrink-0"
            :class="item.icone"
            aria-hidden="true"
          />
          {{ $t(`MODELOS_WHATSAPP.IA.PEDIDOS.${item.chave}`) }}
        </button>
      </div>
      <Button
        data-melhorar
        :label="$t('MODELOS_WHATSAPP.IA.MELHORAR')"
        icon="i-lucide-sparkles"
        class="self-start !min-h-11 !rounded-xl"
        :disabled="estado === 'escrevendo'"
        @click="melhorar"
      />

      <p
        v-if="estado === 'escrevendo'"
        data-ia-escrevendo
        role="status"
        aria-live="polite"
        class="flex items-center gap-2 mb-0 text-base font-medium text-n-slate-12"
      >
        <span
          class="i-lucide-loader-circle size-5 animate-spin text-n-iris-11"
          aria-hidden="true"
        />
        {{ $t('MODELOS_WHATSAPP.IA.ESCREVENDO') }}
      </p>

      <p
        v-else-if="estado === 'erro'"
        data-ia-erro
        role="alert"
        class="p-4 mb-0 text-[0.9375rem] rounded-xl bg-n-ruby-2 text-n-slate-12"
      >
        {{ $t('MODELOS_WHATSAPP.IA.ERRO') }}
      </p>

      <template v-else-if="estado === 'pronto'">
        <div data-antes-depois class="grid gap-3 sm:grid-cols-2">
          <section
            v-for="lado in ['ANTES', 'DEPOIS']"
            :key="lado"
            class="flex flex-col gap-2 p-4 rounded-xl ring-1 ring-inset"
            :class="
              lado === 'DEPOIS'
                ? 'ring-n-blue-6 bg-n-blue-2'
                : 'ring-n-weak bg-n-slate-2'
            "
          >
            <h3 class="m-0 text-xs font-semibold text-n-slate-11">
              {{ $t(`MODELOS_WHATSAPP.IA.${lado}`) }}
            </h3>
            <p
              class="mb-0 text-sm leading-relaxed whitespace-pre-wrap break-words text-n-slate-12"
            >
              <template
                v-for="(pedaco, indice) in lado === 'ANTES'
                  ? rascunho.conteudo.texto
                  : resposta.texto"
                :key="indice"
              >
                <span
                  v-if="pedaco.t === 'campo'"
                  class="px-1 text-xs font-medium rounded bg-n-blue-3 text-n-blue-11"
                >
                  <span>{{
                    $t(`MODELOS_WHATSAPP.CAMPOS.${pedaco.v}.ROTULO`)
                  }}</span>
                </span>
                <span v-else>{{ pedaco.v }}</span>
              </template>
            </p>
          </section>
        </div>
        <p
          v-if="resposta.continuaDivulgacao"
          data-continua-divulgacao
          class="p-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
        >
          {{ $t('MODELOS_WHATSAPP.IA.NAO_DA_AVISO') }}
        </p>
        <CustoDoTipo :tipo="resposta.tipo" />
      </template>
    </div>

    <template v-if="estado === 'pronto'" #rodape>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          data-manter-o-meu
          :label="$t('MODELOS_WHATSAPP.IA.MANTER_O_MEU')"
          color="slate"
          variant="faded"
          class="!min-h-11"
          @click="emit('fechar')"
        />
        <Button
          data-usar-melhoria
          :label="$t('MODELOS_WHATSAPP.IA.USAR')"
          icon="i-lucide-check"
          class="!min-h-11"
          @click="emit('usar', resposta)"
        />
      </div>
    </template>
  </AgenteGaveta>
</template>

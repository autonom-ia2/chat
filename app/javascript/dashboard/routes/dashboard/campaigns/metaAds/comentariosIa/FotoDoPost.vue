<script setup>
import { computed, onMounted, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// IA cuida dos comentários (#2454): "O que eu vi na foto", no passo 1 do "Cuidar dos comentários" (depois do clique do
// dono: antes dele, nenhuma IA). Ao abrir, pede a leitura ao servidor, que olha a foto do post uma vez (no carrossel,
// todas juntas) e guarda. O dono corrige com as palavras dele, e a correção passa a valer no lugar da leitura: é ela que
// a IA usa para entender comentários como "quanto custa esse?". Sem foto no post, o bloco não aparece.
const props = defineProps({
  // async () => { status: 'ready', text, corrected } | { status: 'no_image' | 'unavailable' } | null (a ida falhou)
  read: { type: Function, required: true },
  // async texto => o mesmo formato, ou null quando não guardou
  fix: { type: Function, required: true },
});

const KEY = 'META_ADS_COMMENTS_AI.DONO.PHOTO';
// 'lendo' | 'pronto' | 'falhou' | 'sem_foto'
const estado = ref('lendo');
const texto = ref('');
const corrigindo = ref(false);
const rascunho = ref('');
const guardando = ref(false);
const naoGuardou = ref(false);

const aplicar = resultado => {
  if (resultado?.status === 'no_image') {
    estado.value = 'sem_foto';
    return;
  }
  if (resultado?.status === 'ready' && resultado.text) {
    texto.value = resultado.text;
    estado.value = 'pronto';
    return;
  }
  estado.value = 'falhou';
};

onMounted(async () => {
  aplicar(await props.read());
});

const podeGuardar = computed(
  () => Boolean(rascunho.value.trim()) && !guardando.value
);
const abrir = () => {
  rascunho.value = texto.value;
  naoGuardou.value = false;
  corrigindo.value = true;
};
const cancelar = () => {
  corrigindo.value = false;
  naoGuardou.value = false;
};
const guardar = async () => {
  if (!podeGuardar.value) return;
  guardando.value = true;
  naoGuardou.value = false;
  const resultado = await props.fix(rascunho.value.trim());
  guardando.value = false;
  if (resultado?.status !== 'ready') {
    naoGuardou.value = true;
    return;
  }
  aplicar(resultado);
  corrigindo.value = false;
};

const LINK =
  'min-h-11 w-fit rounded-lg border-0 bg-transparent px-2 text-start text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
const FIELD =
  '!mb-0 w-full min-h-24 resize-none rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';
</script>

<template>
  <div
    v-if="estado !== 'sem_foto'"
    data-ia-foto
    :data-estado="estado"
    class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-4"
  >
    <p
      v-if="estado === 'lendo'"
      role="status"
      class="m-0 flex items-center gap-2 text-sm font-medium text-n-slate-11"
    >
      <span
        class="i-lucide-scan-eye size-4 animate-pulse text-n-violet-11"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.LOOKING`) }}
    </p>
    <template v-else-if="corrigindo">
      <label for="ia-foto-campo" class="text-sm font-semibold text-n-slate-12">
        {{ $t(`${KEY}.SEEN`) }}
      </label>
      <textarea
        id="ia-foto-campo"
        v-model="rascunho"
        data-ia-foto-campo
        rows="3"
        :class="FIELD"
      />
      <p
        v-if="naoGuardou"
        data-ia-foto-erro
        role="alert"
        class="m-0 text-sm font-medium text-n-ruby-11"
      >
        {{ $t(`${KEY}.SAVE_ERROR`) }}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          data-ia-foto-guardar
          variant="faded"
          color="slate"
          :label="$t(`${KEY}.SAVE`)"
          :disabled="!podeGuardar"
          :is-loading="guardando"
          class="!min-h-11 !rounded-xl"
          @click="guardar"
        />
        <button
          type="button"
          data-ia-foto-cancelar
          :class="LINK"
          @click="cancelar"
        >
          {{ $t(`${KEY}.CANCEL`) }}
        </button>
      </div>
    </template>
    <div v-else class="flex flex-wrap items-center gap-x-2">
      <p
        v-if="estado === 'falhou'"
        class="m-0 text-sm leading-6 text-n-slate-12"
      >
        {{ $t(`${KEY}.FAILED`) }}
      </p>
      <p v-else class="m-0 text-sm leading-6 text-n-slate-12">
        <span class="font-semibold">{{ $t(`${KEY}.SEEN`) }}</span>
        {{ texto }}
      </p>
      <button type="button" data-ia-foto-corrigir :class="LINK" @click="abrir">
        {{ $t(`${KEY}.${estado === 'falhou' ? 'WRITE' : 'FIX'}`) }}
      </button>
    </div>
  </div>
</template>

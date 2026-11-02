<script setup>
import { ref, watch } from 'vue';
import CompanyAPI from 'dashboard/api/companies';
import Input from 'dashboard/components-next/input/Input.vue';

// #2414 F5 — escolher uma empresa da conta pelo nome. A conta pode ter muitas,
// então a lista sai da busca, não de uma lista inteira.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Number, default: null },
});

const emit = defineEmits(['update:modelValue']);

const busca = ref('');
const achadas = ref([]);
const escolhida = ref(null);
const falhou = ref(false);

// Só vale a resposta da última busca: uma lenta não troca a lista da nova.
let ultima = 0;
const procurar = async texto => {
  ultima += 1;
  const esta = ultima;
  falhou.value = false;
  if (!texto.trim()) {
    achadas.value = [];
    return;
  }
  try {
    const { data } = await CompanyAPI.search(texto.trim());
    if (esta === ultima) achadas.value = data?.payload || [];
  } catch {
    if (esta !== ultima) return;
    achadas.value = [];
    falhou.value = true;
  }
};

let espera = null;
const ESPERA_MS = 300;
watch(busca, texto => {
  clearTimeout(espera);
  espera = setTimeout(() => procurar(texto), ESPERA_MS);
});

const escolher = empresa => {
  escolhida.value = empresa;
  busca.value = '';
  emit('update:modelValue', empresa.id);
};
</script>

<template>
  <div class="flex flex-col gap-2" data-peca="empresa">
    <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
    <p
      v-if="props.modelValue"
      class="flex items-center gap-2 px-3 mb-0 text-[0.9375rem] min-h-11 rounded-xl bg-n-alpha-2 text-n-slate-12"
    >
      <span class="i-lucide-building-2 size-4" aria-hidden="true" />
      {{ escolhida?.name || `#${props.modelValue}` }}
    </p>
    <Input
      v-model="busca"
      :aria-label="rotulo"
      :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.PROCURAR')"
    />
    <p v-if="falhou" role="alert" class="mb-0 text-sm text-n-ruby-11">
      {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.BUSCA_FALHOU') }}
    </p>
    <ul v-if="achadas.length" class="flex flex-col gap-1.5 p-0 m-0 list-none">
      <li v-for="empresa in achadas" :key="empresa.id">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-3 py-2 border text-start rounded-xl min-h-11 border-n-weak bg-n-solid-1 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="escolher(empresa)"
        >
          {{ empresa.name }}
        </button>
      </li>
    </ul>
  </div>
</template>

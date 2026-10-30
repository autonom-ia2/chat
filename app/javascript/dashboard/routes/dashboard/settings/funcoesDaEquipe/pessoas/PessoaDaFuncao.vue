<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import EfeitoSemFuncao from './EfeitoSemFuncao.vue';

// Uma pessoa na gaveta (#2308, especificação 5.D e 9). A ação vem escrita na própria linha (sem checkbox); o estado
// fica sempre na 2ª linha; uma mudança marca a linha e oferece "Desfazer". `modo`: 'ja' (já tem a função), 'outra'
// (outras pessoas) ou 'sem' (quem está sem função). `destino`: undefined = sem mudança, null = sem função, id = função.
const props = defineProps({
  pessoa: { type: Object, required: true },
  modo: { type: String, required: true },
  alvo: { type: Object, default: null },
  atual: { type: Object, default: null },
  destino: { type: [Number, null], default: undefined },
  nomeDoDestino: { type: String, default: '' },
  trava: { type: String, default: '' },
  somenteLeitura: { type: Boolean, default: false },
  opcoes: { type: Array, default: () => [] },
  // Enquanto a gaveta salva, a linha não muda: o fim do salvar troca as mudanças pelo que não gravou (rodada 4).
  salvando: { type: Boolean, default: false },
});

const emit = defineEmits(['mudar', 'desfazer']);
const { t } = useI18n();

const mudou = computed(() => props.destino !== undefined);
const ficaSem = computed(() => props.destino === null);
const livre = computed(() => !props.trava && !props.somenteLeitura);

const estado = computed(() => {
  if (props.trava) return t(`FUNCOES_EQUIPE.PESSOA.TRAVA.${props.trava}`);
  if (ficaSem.value) return t('FUNCOES_EQUIPE.PESSOA.VAI_FICAR_SEM');
  const nova = props.nomeDoDestino;
  if (mudou.value && props.modo === 'sem')
    return t('FUNCOES_EQUIPE.PESSOA.VAI_SER', { nova });
  if (mudou.value)
    return props.atual
      ? t('FUNCOES_EQUIPE.PESSOA.HOJE_E', { atual: props.atual.name, nova })
      : t('FUNCOES_EQUIPE.PESSOA.HOJE_SEM', { nova });
  if (props.modo === 'ja') return '';
  return props.atual?.name || t('FUNCOES_EQUIPE.PESSOA.SEM_FUNCAO');
});

const ICONE = {
  trava: 'i-lucide-lock text-n-slate-11',
  ficaSem: 'i-lucide-circle-minus text-n-amber-11',
  mudou: 'i-lucide-repeat text-n-amber-11',
};
const icone = computed(() => {
  if (props.trava) return ICONE.trava;
  if (ficaSem.value) return ICONE.ficaSem;
  return mudou.value ? ICONE.mudou : '';
});

// "Pôr em outra função" para quem sai; "Escolher função" para quem está sem.
const escolha = computed(() => {
  if (!livre.value) return null;
  if (props.modo === 'sem') return 'ESCOLHER_FUNCAO';
  return props.modo === 'ja' && mudou.value ? 'OUTRA_FUNCAO' : null;
});

const acao = computed(() => {
  if (!livre.value) return null;
  if (mudou.value) return { chave: 'DESFAZER', emitir: () => emit('desfazer') };
  if (props.modo === 'ja')
    return { chave: 'TIRAR', emitir: () => emit('mudar', null) };
  if (props.modo === 'outra')
    return { chave: 'POR_COMO', emitir: () => emit('mudar', props.alvo.id) };
  return null;
});
const valores = computed(() => ({
  pessoa: props.pessoa.name,
  funcao: props.alvo?.name,
}));
</script>

<template>
  <li
    :data-pessoa="pessoa.id"
    class="flex flex-col gap-2 px-3 rounded-xl"
    :class="
      mudou ? 'py-4 bg-n-amber-2 ring-1 ring-inset ring-n-amber-6' : 'py-2'
    "
  >
    <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:gap-3">
      <div class="flex items-start flex-1 min-w-0 gap-3 min-h-11">
        <Avatar
          :name="pessoa.name"
          :src="pessoa.thumbnail"
          :size="36"
          rounded-full
        />
        <span class="flex flex-col min-w-0">
          <span class="font-medium break-words text-n-slate-12">
            {{ pessoa.name }}
          </span>
          <span
            v-if="estado"
            data-estado
            class="inline-flex items-start gap-1.5 text-sm text-n-slate-11"
            :class="{ 'font-medium text-n-slate-12': mudou }"
          >
            <span
              v-if="icone"
              class="size-4 mt-0.5 shrink-0"
              :class="icone"
              aria-hidden="true"
            />
            {{ estado }}
          </span>
        </span>
      </div>
      <Button
        v-if="acao"
        :data-acao="acao.chave"
        :label="$t(`FUNCOES_EQUIPE.PESSOA.${acao.chave}`, valores)"
        :aria-label="$t(`FUNCOES_EQUIPE.PESSOA.${acao.chave}_ROTULO`, valores)"
        slate
        faded
        :disabled="salvando"
        class="min-h-11 sm:min-w-[11.5rem] max-sm:w-full"
        @click="acao.emitir"
      />
    </div>
    <div v-if="ficaSem || escolha" class="flex flex-col gap-2 sm:ps-12">
      <EfeitoSemFuncao
        v-if="ficaSem && alvo"
        :permissions="alvo.permissions || []"
      />
      <ChoiceSelect
        v-if="escolha"
        data-escolha
        :model-value="typeof destino === 'number' ? destino : ''"
        :options="opcoes"
        :aria-label="$t(`FUNCOES_EQUIPE.PESSOA.${escolha}_ROTULO`, valores)"
        :placeholder="$t(`FUNCOES_EQUIPE.PESSOA.${escolha}`)"
        :disabled="salvando"
        class="w-full sm:w-auto sm:self-start"
        @update:model-value="valor => emit('mudar', valor)"
      />
    </div>
  </li>
</template>

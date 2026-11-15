<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { chaveDaRecusa, codigoDaRecusa } from '../../carteira/recusas';
import AvisoComDesfazer from './AvisoComDesfazer.vue';
import GavetaDeFora from './GavetaDeFora.vue';

// #2899 (E6.5) — a entrada de "Guardar seguro de outra corretora" (no painel da
// conversa e no bloco Seguros da ficha): o link, a gaveta e o aviso do que foi
// guardado, com "Desfazer" sem prazo (apaga o seguro que acabou de entrar).
// Quem usa só põe esta peça onde a conta lê PDF e a pessoa pode editar.
const props = defineProps({
  pessoaId: { type: Number, required: true },
  fonte: { type: Object, required: true },
  // O nome de quem é o seguro (a ficha, ou quem está na conversa).
  nome: { type: String, default: '' },
  marca: { type: String, default: 'entrada-de-fora' },
});
const emit = defineEmits(['mudou']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_DEU';

const { t } = useI18n();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.DE_FORA.${chave}`, valores);

const aberta = ref(false);
const aviso = ref('');
// O seguro que acabou de ser guardado (dá para desfazer).
const guardado = ref(null);
const desfazendo = ref(false);

// "Marcela Antunes Prado" -> "Marcela".
const primeiroNome = computed(() => props.nome.trim().split(' ')[0]);

const abrir = () => {
  aviso.value = '';
  guardado.value = null;
  aberta.value = true;
};

const aoGuardar = seguro => {
  aberta.value = false;
  guardado.value = seguro;
  aviso.value = td(
    seguro.lembreteAceitoEm ? 'GUARDADO_COM_LEMBRETE' : 'GUARDADO'
  );
  emit('mudou');
};

const desfazer = async () => {
  if (desfazendo.value || !guardado.value) return;
  desfazendo.value = true;
  try {
    await props.fonte.apagarDeFora(guardado.value.id);
    guardado.value = null;
    aviso.value = td('DESFEITO');
    emit('mudou');
  } catch (falha) {
    aviso.value = t(chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU));
  } finally {
    desfazendo.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col items-start gap-2">
    <AvisoComDesfazer
      class="self-stretch"
      :texto="aviso"
      :pode-desfazer="Boolean(guardado)"
      :desfazendo="desfazendo"
      @desfazer="desfazer"
    />
    <Button
      variant="link"
      color="blue"
      size="sm"
      class="min-h-11 text-start"
      icon="i-lucide-file-plus"
      :data-carteira="marca"
      :label="td('ENTRADA')"
      @click="abrir"
    />
    <GavetaDeFora
      :aberta="aberta"
      :pessoa-id="pessoaId"
      :fonte="fonte"
      :nome="primeiroNome"
      @fechar="aberta = false"
      @guardado="aoGuardar"
    />
  </div>
</template>

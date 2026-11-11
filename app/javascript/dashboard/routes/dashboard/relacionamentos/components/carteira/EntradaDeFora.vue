<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import AvisoComDesfazer from './AvisoComDesfazer.vue';
import GavetaDeFora from './GavetaDeFora.vue';

// #2897 — a entrada de "Guardar seguro de outra corretora" (no painel da
// conversa e no bloco Seguros da ficha): o link, a gaveta e o aviso do que foi
// guardado, com Desfazer sem prazo. Pôr a pergunta na caixa de mensagem é de
// outra entrega: por ora, o aviso diz o que ficaria pronto.
const props = defineProps({
  pessoaId: { type: Number, required: true },
  fonte: { type: Object, required: true },
  marca: { type: String, required: true },
});
const emit = defineEmits(['mudou']);

const { t } = useI18n();
const td = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.DE_FORA.${chave}`, valores);
const textos = useTextosDoSeguro();

const aberta = ref(false);
const aviso = ref('');
// O lembrete que acabou de ser guardado (dá para desfazer).
const guardado = ref(null);
const desfazendo = ref(false);

const abrir = () => {
  aviso.value = '';
  guardado.value = null;
  aberta.value = true;
};

const aoGuardar = ({ seguro, nome }) => {
  aberta.value = false;
  guardado.value = seguro;
  aviso.value = td('GUARDADO', {
    nome,
    data: textos.diaMes(seguro.lembreteEm),
  });
  emit('mudou');
};

const desfazer = async () => {
  desfazendo.value = true;
  try {
    await props.fonte.desfazerDeFora(guardado.value.id);
    guardado.value = null;
    aviso.value = td('DESFEITO');
    emit('mudou');
  } catch {
    useAlert(t('RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_DEU'));
  } finally {
    desfazendo.value = false;
  }
};

const perguntar = () => {
  aberta.value = false;
  useAlert(td('PERGUNTA_PRONTA', { texto: td('PERGUNTA') }));
};
</script>

<template>
  <AvisoComDesfazer
    :texto="aviso"
    :pode-desfazer="Boolean(guardado)"
    :desfazendo="desfazendo"
    @desfazer="desfazer"
  />
  <Button
    link
    size="lg"
    class="text-start"
    :data-carteira="marca"
    :label="t('RELACIONAMENTOS_CARTEIRA.PAINEL.GUARDAR_DE_FORA')"
    @click="abrir"
  />
  <GavetaDeFora
    :aberta="aberta"
    :pessoa-id="pessoaId"
    :fonte="fonte"
    @fechar="aberta = false"
    @guardado="aoGuardar"
    @perguntar="perguntar"
  />
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import ModeloCelular from '../components/ModeloCelular.vue';
import { rotuloDoCampo } from '../helpers/campos';
import { miniaturaDe } from '../api/arquivos';

// "Como o cliente vê" na campanha: o mesmo celular da tela de Modelos (com
// topo, rodapé e botões), com o que cada variável vai receber da primeira
// pessoa do público.
const props = defineProps({
  modelo: { type: Object, required: true },
  bindings: { type: Object, default: () => ({}) },
  sample: { type: Object, default: null },
  remetente: { type: String, default: '' },
  // #1334: o cupom digitado na campanha aparece no celular.
  cupom: { type: String, default: '' },
  // #1465: o arquivo do topo escolhido na campanha ({ referencia, nome }); sem
  // ele, vai o aprovado.
  topo: { type: Object, default: null },
});

const { t } = useI18n();
const { currentAccount } = useAccount();

const primeiroNome = () =>
  props.sample?.first_name ||
  (props.sample?.name || '').split(' ')[0] ||
  t('MODELOS_WHATSAPP.PONTE.PRIMEIRO_NOME');

// Campo do catálogo (#1331): o que dá para mostrar daqui; o resto aparece pelo
// nome do campo, entre colchetes.
const valorDoCatalogo = chave => {
  if (chave === 'cliente.primeiro_nome') return primeiroNome();
  if (chave === 'cliente.nome') {
    return props.sample?.name || t('MODELOS_WHATSAPP.PONTE.NOME_DO_CONTATO');
  }
  if (chave === 'minha_empresa.nome') return currentAccount.value?.name || '';
  if (chave.startsWith('publico.')) {
    const coluna = chave.slice('publico.'.length);
    return props.sample?.extra_values?.[coluna] || `[${coluna}]`;
  }
  return `[${rotuloDoCampo(t, chave)}]`;
};

const valorDe = ligacao => {
  if (!ligacao?.value) return '';
  if (ligacao.source === 'fixed') return ligacao.value;
  if (ligacao.source === 'field') return valorDoCatalogo(ligacao.value);
  if (ligacao.source === 'column') {
    return props.sample?.extra_values?.[ligacao.value] || `[${ligacao.value}]`;
  }
  if (ligacao.value === 'first_name') return primeiroNome();
  return props.sample?.name || t('MODELOS_WHATSAPP.PONTE.NOME_DO_CONTATO');
};

const conteudo = computed(() => {
  const exemplos = Object.fromEntries(
    Object.entries(props.modelo.campos || {}).map(([chave, campo]) => [
      campo,
      valorDe(props.bindings[chave]) || rotuloDoCampo(t, campo),
    ])
  );
  // O arquivo do topo que vai — o escolhido agora ou o aprovado guardado — e,
  // se for foto, a miniatura dele.
  const guardado = props.modelo.topoGuardado;
  const arquivoDoTopo = props.topo?.nome || guardado?.nome;
  const topo = {
    ...props.modelo.conteudo.topo,
    arquivo: arquivoDoTopo,
    imagem: miniaturaDe(props.topo, guardado),
  };
  const base = {
    ...props.modelo.conteudo,
    exemplos,
    ...(arquivoDoTopo ? { topo } : {}),
  };
  if (!props.cupom) return base;
  return {
    ...base,
    ...(base.oferta ? { oferta: { ...base.oferta, cupom: props.cupom } } : {}),
    botoes: (base.botoes || []).map(botao =>
      botao.tipo === 'copiar_codigo' ? { ...botao, valor: props.cupom } : botao
    ),
  };
});
</script>

<template>
  <aside data-ponte-previa class="flex flex-col gap-2 lg:sticky lg:top-4">
    <p class="mb-0 text-sm font-medium text-center text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.CELULAR.TITULO') }}
    </p>
    <ModeloCelular :conteudo="conteudo" :remetente="remetente" compacto />
  </aside>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  formatInZone,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';
import ModeloCelular from '../components/ModeloCelular.vue';
import { rotuloDoCampo } from '../helpers/campos';
import { miniaturaDe } from '../api/arquivos';

// "Como o cliente vê" na campanha: o mesmo celular da tela de Modelos (com
// topo, rodapé e botões), com o que cada variável vai receber da primeira
// pessoa do público. #1456: também sem a ponte de Modelos (o modelo vem do
// `conteudoDaMeta`), e com o que a campanha preencheu do formato: o cupom, o
// "vale até" da oferta e o arquivo de cada cartão.
const props = defineProps({
  modelo: { type: Object, required: true },
  bindings: { type: Object, default: () => ({}) },
  // Texto padrão de cada variável (quando a pessoa não tem o valor).
  defaults: { type: Object, default: () => ({}) },
  sample: { type: Object, default: null },
  remetente: { type: String, default: '' },
  // #1334: o que a campanha preencheu do formato (formatoNaCampanha): cupom,
  // validade da oferta, o arquivo escolhido de cada cartão e o do topo (#1465).
  valores: { type: Object, default: () => ({}) },
  timeZone: { type: String, default: 'UTC' },
});

const { t, locale } = useI18n();
const { currentAccount } = useAccount();

const PUBLICO = 'publico.';

// O que a primeira pessoa do público (ou a conta) responde; vazio quando não há.
const doCatalogo = chave => {
  if (chave === 'cliente.primeiro_nome') {
    return (
      props.sample?.first_name || (props.sample?.name || '').split(' ')[0] || ''
    );
  }
  if (chave === 'cliente.nome') return props.sample?.name || '';
  if (chave === 'empresa_cliente.nome') return props.sample?.company_name || '';
  if (chave === 'minha_empresa.nome') return currentAccount.value?.name || '';
  if (chave.startsWith(PUBLICO)) {
    return props.sample?.extra_values?.[chave.slice(PUBLICO.length)] || '';
  }
  return '';
};

const CONTATO_NO_CATALOGO = {
  first_name: 'cliente.primeiro_nome',
  name: 'cliente.nome',
  company: 'empresa_cliente.nome',
};

const daAmostra = ligacao => {
  if (ligacao.source === 'fixed') return ligacao.value;
  if (ligacao.source === 'column') {
    return props.sample?.extra_values?.[ligacao.value] || '';
  }
  if (ligacao.source === 'field') return doCatalogo(ligacao.value);
  return doCatalogo(CONTATO_NO_CATALOGO[ligacao.value] || '');
};

// Sem valor da amostra nem texto padrão: o nome da origem, entre colchetes.
const marcador = ligacao => {
  if (ligacao.source === 'column') return `[${ligacao.value}]`;
  if (ligacao.source === 'field' && ligacao.value.startsWith(PUBLICO)) {
    return `[${ligacao.value.slice(PUBLICO.length)}]`;
  }
  const chave =
    ligacao.source === 'field'
      ? ligacao.value
      : CONTATO_NO_CATALOGO[ligacao.value];
  return chave ? `[${rotuloDoCampo(t, chave)}]` : '';
};

// Mesma ordem do envio (previewMessage): a amostra, o texto padrão da
// variável, o marcador; sem ligação, o rótulo do campo.
const valorDe = (chave, campo) => {
  const ligacao = props.bindings[chave];
  if (!ligacao?.value) return rotuloDoCampo(t, campo);
  return (
    daAmostra(ligacao) || props.defaults[chave] || marcador(ligacao) || campo
  );
};

const cupom = computed(() => (props.valores.cupom || '').trim());

const validade = computed(() => {
  const iso = scheduleToUtc(props.valores.validade, props.timeZone);
  return iso ? formatInZone(iso, props.timeZone, locale.value) : '';
});

// O arquivo escolhido agora, senão o aprovado guardado com o modelo.
const arquivoDoCartao = indice =>
  props.valores.cartoes?.[indice]?.nome ||
  props.modelo.cartoesGuardados?.[indice]?.nome ||
  '';

// #1465: o arquivo do topo que vai — o escolhido agora ou o aprovado guardado —
// e, se for foto, a miniatura dele.
const topoQueVai = () => {
  const guardado = props.modelo.topoGuardado;
  const escolhido = props.valores.topo;
  const arquivo = escolhido?.nome || guardado?.nome;
  if (!arquivo) return {};
  return {
    topo: {
      ...props.modelo.conteudo.topo,
      arquivo,
      imagem: miniaturaDe(escolhido, guardado),
    },
  };
};

const conteudo = computed(() => {
  const exemplos = Object.fromEntries(
    Object.entries(props.modelo.campos || {}).map(([chave, campo]) => [
      campo,
      valorDe(chave, campo),
    ])
  );
  const base = { ...props.modelo.conteudo, exemplos, ...topoQueVai() };
  return {
    ...base,
    // O celular sabe que é a campanha: mostra o cupom digitado e nunca a
    // contagem de exemplo da tela de Modelos.
    naCampanha: true,
    ...(base.oferta
      ? {
          oferta: {
            ...base.oferta,
            cupom: cupom.value,
            validade: validade.value,
          },
        }
      : {}),
    // O código de exemplo do modelo nunca aparece como se fosse o da campanha.
    botoes: (base.botoes || []).map(botao =>
      botao.tipo === 'copiar_codigo' ? { ...botao, valor: cupom.value } : botao
    ),
    // #1418: os produtos escolhidos na campanha, na ordem em que vão.
    ...(base.produtos
      ? { produtosEscolhidos: props.valores.produtos || [] }
      : {}),
    ...(base.cartoes
      ? {
          cartoes: base.cartoes.map((cartao, indice) => ({
            ...cartao,
            arquivo: arquivoDoCartao(indice) || cartao.arquivo,
          })),
        }
      : {}),
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

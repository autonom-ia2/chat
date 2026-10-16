import { computed } from 'vue';
import { FUNIL } from './funil';

// #1384 — o cabeçalho e o rodapé de cada tela da gaveta de funil. Uma ação
// principal por tela, sempre no mesmo lugar; o herói tem a mesma anatomia em
// todas. Recebe da gaveta o estado e as ações (refs e funções).
export const useFunilMoldura = ({
  t,
  view,
  pilha,
  form,
  isEditing,
  selectedStage,
  selectedIndex,
  canSubmit,
  improving,
  aiPanel,
  salvando,
  apagandoEtapa,
  hasUnnamedStages,
  passoGoogle,
  onSubmit,
  fechar,
  pronto,
  cancelar,
  removeStage,
  ligarGoogle,
  tipo,
}) => {
  const VOLTA_PARA = {
    stages: 'CRM_FUNIL.ETAPAS.ROTULO',
    returns: 'CRM_FUNIL.RETORNO.ROTULO',
    ads: 'CRM_FUNIL.ANUNCIOS.ROTULO',
    etapas: 'CRM_FUNIL.ETAPAS.ROTULO',
    confira: 'CRM_FUNIL.PASSOS.CONFIRA',
  };
  const voltarPara = computed(() => {
    const de = pilha.value.at(-1)?.de;
    if (VOLTA_PARA[de]) return t(VOLTA_PARA[de]);
    if (de === 'stage') return selectedStage.value?.name.trim() || '…';
    if (isEditing.value) return form.name.trim() || t('CRM_FUNIL.EDITAR');
    return t('CRM_FUNIL.NOVO');
  });
  const SUBTELAS = {
    stages: { chave: 'ETAPAS', icone: 'i-lucide-columns-3' },
    about: { chave: 'SOBRE', icone: 'i-lucide-message-square-text' },
    sales: { chave: 'VENDAS', icone: 'i-lucide-target' },
    returns: { chave: 'RETORNO', icone: 'i-lucide-bell-ring' },
    'returns-detail': {
      chave: 'RETORNO.DETALHE',
      icone: 'i-lucide-rotate-ccw',
    },
    inboxes: { chave: 'CAIXAS', icone: 'i-lucide-inbox' },
    ads: { chave: 'ANUNCIOS', icone: 'i-lucide-megaphone' },
    'ads-facebook': {
      chave: 'ANUNCIOS.FACEBOOK',
      icone: 'i-ri-facebook-circle-fill',
    },
    'ads-google': {
      chave: 'ANUNCIOS.GOOGLE',
      icone: 'i-lucide-search',
      titulo: 'HEROI',
    },
  };
  // Telas de cima: o lugar, o rótulo e a frase de cada passo de criar.
  const TOPO = {
    home: { rotulo: 'CRM_FUNIL.EDITAR', texto: 'CRM_FUNIL.RESUMO.TEXTO' },
    nome: { rotulo: 'CRM_FUNIL.NOVO', texto: 'CRM_FUNIL.NOVO_TEXTO' },
    etapas: { rotulo: 'CRM_FUNIL.NOVO', texto: 'CRM_FUNIL.ETAPAS.HEROI' },
    confira: { rotulo: 'CRM_FUNIL.NOVO', texto: 'CRM_FUNIL.CONFIRA.HEROI' },
  };
  const heroi = computed(() => {
    const base = { voltar: voltarPara.value, migalha: '' };
    if (['stage', 'stage-actions'].includes(view.value)) {
      const acoes = view.value === 'stage-actions';
      return {
        ...base,
        rotulo: acoes
          ? t('CRM_FUNIL.ETAPA.ACOES')
          : t('CRM_FUNIL.ETAPA.POSICAO', {
              atual: selectedIndex.value + 1,
              total: form.stages.length,
            }),
        icone: acoes ? 'i-lucide-zap' : 'i-lucide-columns-3',
        titulo: acoes
          ? t('CRM_FUNIL.ETAPA.ACOES_TITULO')
          : selectedStage.value?.name.trim() || '…',
        texto: t(
          acoes ? 'CRM_FUNIL.ETAPA.ACOES_TEXTO' : 'CRM_FUNIL.ETAPA.TEXTO'
        ),
      };
    }
    const subtela = SUBTELAS[view.value];
    // #1498 — "Vendas e meta" virou "Para que serve": Vender fala de vendas e
    // meta; Atender, de como cada pedido termina.
    if (view.value === 'sales') {
      const parte = form.countsAsSale ? 'VENDAS' : 'ATENDER';
      return {
        ...base,
        rotulo: t(`${FUNIL}.TIPO.ROTULO`),
        icone: form.countsAsSale ? 'i-lucide-target' : 'i-lucide-life-buoy',
        titulo: t(`${FUNIL}.${parte}.TITULO`),
        texto: t(`${FUNIL}.${parte}.TEXTO`),
      };
    }
    if (subtela)
      return {
        ...base,
        rotulo: t(`${FUNIL}.${subtela.chave}.ROTULO`),
        icone: subtela.icone,
        titulo: t(`${FUNIL}.${subtela.chave}.${subtela.titulo || 'TITULO'}`),
        // #1498 — Atender: os lembretes falam do andamento, não de chamar de volta.
        texto: t(
          !form.countsAsSale && view.value === 'returns'
            ? `${FUNIL}.RETORNO.TEXTO_ATENDER`
            : `${FUNIL}.${subtela.chave}.TEXTO`
        ),
      };
    const topo = TOPO[view.value] || TOPO.nome;
    return {
      voltar: '',
      migalha: t('CRM_FUNIL.ROTULO'),
      rotulo: t(topo.rotulo),
      icone: 'i-lucide-kanban',
      titulo:
        view.value === 'nome'
          ? t('CRM_FUNIL.NOVO_TITULO')
          : form.name.trim() || '…',
      texto: t(topo.texto),
    };
  });

  const salvarDesabilitado = computed(
    () =>
      !canSubmit.value ||
      improving.value ||
      aiPanel.value?.isLoading ||
      aiPanel.value?.isSaving ||
      aiPanel.value?.loadFailed
  );
  const salvar = () => ({
    rotulo: t('CRM_FUNIL.SALVAR'),
    icone: 'i-lucide-check',
    acao: onSubmit,
    carregando: salvando.value,
    desabilitado: salvarDesabilitado.value,
  });
  const continuar = (para, desabilitado = false) => ({
    rotulo: t('CRM_FUNIL.CONTINUAR'),
    icone: 'i-lucide-arrow-right',
    depois: true,
    acao: () => {
      view.value = para;
    },
    desabilitado,
  });
  const voltarA = para => ({
    rotulo: t('CRM_FUNIL.VOLTAR'),
    acao: () => {
      view.value = para;
    },
  });
  const rodapeGoogle = () => ({
    secundaria:
      passoGoogle.value === 1
        ? { rotulo: t('CRM_FUNIL.CANCELAR'), acao: cancelar }
        : {
            rotulo: t('CRM_FUNIL.VOLTAR'),
            acao: () => {
              passoGoogle.value -= 1;
            },
          },
    principal:
      passoGoogle.value < 3
        ? {
            ...continuar('ads-google'),
            acao: () => {
              passoGoogle.value += 1;
            },
          }
        : {
            rotulo: t('CRM_FUNIL.ANUNCIOS.GOOGLE.LIGAR'),
            icone: 'i-lucide-check',
            acao: ligarGoogle,
          },
  });
  // Uma ação principal por tela, sempre no mesmo lugar e com o mesmo peso.
  // Tirar a etapa fica à parte, à esquerda, sem cor cheia.
  const rodape = computed(() => {
    const criar = {
      nome: () => ({
        secundaria: { rotulo: t('CRM_FUNIL.CANCELAR'), acao: fechar },
        principal: continuar('etapas', !tipo.value || !form.name.trim()),
      }),
      etapas: () => ({
        secundaria: voltarA('nome'),
        principal: continuar(
          'confira',
          hasUnnamedStages.value || !form.stages.length
        ),
      }),
      confira: () => ({
        secundaria: voltarA('etapas'),
        principal: {
          ...salvar(),
          rotulo: t('CRM_KANBAN.PIPELINE_DRAWER.CREATE'),
        },
      }),
    };
    if (criar[view.value]) return criar[view.value]();
    // Editar: cada parte salva na própria tela; o resumo só fecha, sem cor.
    if (view.value === 'home')
      return {
        principal: {
          rotulo: t('CRM_FUNIL.FECHAR'),
          acao: fechar,
          neutro: true,
        },
      };
    if (view.value === 'ads-google') return rodapeGoogle();
    // Caixas e ações da etapa salvam na hora: só voltam. Enquanto uma caixa
    // está sendo ligada, a ação principal é a do cartão.
    if (['inboxes', 'stage-actions'].includes(view.value))
      return {
        principal: {
          rotulo: t('CRM_FUNIL.PRONTO'),
          icone: 'i-lucide-check',
          acao: pronto,
        },
      };
    // Tela aberta de dentro de outra volta com "Pronto"; as partes de um funil
    // existente abertas do resumo salvam com "Salvar".
    const voltaComPronto =
      !isEditing.value || pilha.value.at(-1)?.de !== 'home';
    return {
      perigo:
        view.value === 'stage'
          ? {
              rotulo: t('CRM_FUNIL.ETAPA.TIRAR'),
              acao: () => removeStage(selectedIndex.value),
              desabilitado: form.stages.length === 1 || apagandoEtapa.value,
            }
          : null,
      secundaria: { rotulo: t('CRM_FUNIL.CANCELAR'), acao: cancelar },
      principal: voltaComPronto
        ? {
            rotulo: t('CRM_FUNIL.PRONTO'),
            icone: 'i-lucide-check',
            acao: pronto,
            desabilitado:
              (view.value === 'stage' && !selectedStage.value?.name.trim()) ||
              (view.value === 'returns-detail' &&
                !aiPanel.value?.scheduleValid),
          }
        : salvar(),
    };
  });

  return { heroi, rodape };
};

import { computed, nextTick, ref, watch } from 'vue';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';
import { motivoDoErro } from './motivoDoErro';
import { avisar } from './useAvisoCrm';
import {
  avisoDoRestaurado,
  avisoDosDoisAbertos,
  ehVenda,
  nomeDoCliente,
} from './textosDoArquivado';

// O que a página do CRM faz com Arquivados (#2095, flag crm_arquivados): abrir os painéis, restaurar um card (com o
// cliente que já voltou), avisar onde o card foi parar, arquivar card e funil com o aviso de pronto. Fica fora da
// CrmKanbanPage para ela não crescer mais; a página só liga as peças. As ações da página (abrir card, ir para a
// Lista, recarregar) chegam por `ligar`, no fim do setup dela, porque são declaradas depois deste ponto.
export const FUNIS_ARQUIVADOS = '__funis_arquivados__';
const NAO_ARQUIVADO = 'crm.card_restore_not_archived';

export const useArquivadosNaPagina = ({ t, ligado, funilAtual }) => {
  let pagina = null;
  const ligar = acoes => {
    pagina = acoes;
  };
  const painelAberto = ref(false);
  const funisAbertos = ref(false);
  const totalDoFunil = ref(null);
  const totalDeFunis = ref(0);
  const conflito = ref(null);
  const conflitoOcupado = ref(false);
  const conflitoErro = ref('');
  const dialogoConflito = ref(null);
  const painel = ref(null);
  const restaurandoCard = ref(false);
  const erroRestaurarCard = ref('');
  const erroArquivarCard = ref('');

  const contar = async () => {
    const funilId = funilAtual()?.id;
    if (!ligado.value || !funilId) return;
    try {
      const [arquivados, funis] = await Promise.all([
        CrmArquivadosAPI.listar({ pipeline_id: funilId, per_page: 1 }),
        CrmArquivadosAPI.funisArquivados(),
      ]);
      totalDoFunil.value = arquivados.data.meta?.count ?? 0;
      totalDeFunis.value = (funis.data.payload || []).length;
    } catch {
      // Só a contagem do atalho: sem ela, o atalho mostra o painel do mesmo jeito.
      totalDoFunil.value = totalDoFunil.value ?? 0;
    }
  };
  watch(
    () => [ligado.value, funilAtual()?.id],
    () => contar(),
    { immediate: true }
  );

  const abrirPainel = () => {
    funisAbertos.value = false;
    painelAberto.value = true;
  };
  const abrirFunis = () => {
    painelAberto.value = false;
    funisAbertos.value = true;
  };

  const depoisDeMudar = async () => {
    await Promise.allSettled([pagina.recarregarVista(), contar()]);
  };

  // "Ver": a Lista do funil do card, na aba do desfecho, com o foco na linha dele.
  const verNaLista = async card => {
    painelAberto.value = false;
    pagina.fecharCard();
    await pagina.irParaALista(
      card.pipeline_id || card.pipeline?.id,
      card.status
    );
    await nextTick();
    document.querySelector(`[data-row-id="${card.id}"]`)?.focus();
  };

  const avisarRestaurado = (card, alvo) => {
    const funil = pagina.funilPorId(card.pipeline_id || card.pipeline?.id);
    const aviso = avisoDoRestaurado(t, {
      nome: nomeDoCliente(alvo) || nomeDoCliente(card),
      card,
      funil,
      retornosParados: Number(alvo.retornos_parados || 0),
    });
    let acao = null;
    if (aviso.lista)
      acao = {
        rotulo: t('CRM_ARQUIVADOS.VER'),
        executar: () => verNaLista(card),
      };
    else if (aviso.retornos)
      acao = {
        rotulo: t('CRM_ARQUIVADOS.AGENDAR_RETORNO'),
        executar: () => pagina.abrirCard(card, 'followups'),
      };
    avisar(aviso.texto, acao);
  };

  // Restaurar um card (linha de Arquivados, card arquivado aberto ou o "Desfazer"). 409 = o cliente tem outro card
  // aberto no mesmo funil: a janela de conflito decide.
  const restaurar = async (alvo, { forcar = false } = {}) => {
    // Quem pediu (o botão Restaurar): o foco volta para ele quando a janela de conflito fecha.
    const origem = document.activeElement;
    try {
      const { data } = await CrmArquivadosAPI.restaurar(alvo.id, {
        force: forcar,
      });
      const card = data.payload || data;
      avisarRestaurado(card, alvo);
      await depoisDeMudar();
      await pagina.atualizarCardAberto(card.id);
      return { restaurado: true };
    } catch (error) {
      // Segundo clique (ou outra pessoa restaurou antes): o card já voltou. É o que a pessoa queria; a tela só se
      // atualiza, sem erro.
      if (error?.response?.data?.error === NAO_ARQUIVADO) {
        await depoisDeMudar();
        await pagina.atualizarCardAberto(alvo.id);
        return { restaurado: true };
      }
      if (error?.response?.status === 409 && !forcar) {
        conflito.value = {
          alvo,
          nome: nomeDoCliente(alvo),
          funil:
            alvo.pipeline?.name ||
            pagina.funilPorId(alvo.pipeline_id)?.name ||
            '',
          aberto: error.response.data?.open_card || null,
          origem,
        };
        conflitoErro.value = '';
        await nextTick();
        dialogoConflito.value?.open();
        return { restaurado: false };
      }
      return {
        restaurado: false,
        erro: t('CRM_ARQUIVADOS.ERRO_RESTAURAR', {
          motivo: motivoDoErro(t, error),
        }),
      };
    }
  };

  const restaurarCardAberto = async card => {
    restaurandoCard.value = true;
    erroRestaurarCard.value = '';
    const resultado = await restaurar(card);
    restaurandoCard.value = false;
    erroRestaurarCard.value = resultado.erro || '';
  };

  // A janela de conflito fechou (Esc, ou depois de uma das duas escolhas): o foco volta para quem pediu, se ainda
  // existe; a linha restaurada já saiu da lista.
  const aoFecharConflito = () => {
    const origem = conflito.value?.origem;
    if (origem?.isConnected) origem.focus();
  };

  const abrirOAberto = () => {
    const id = conflito.value?.aberto?.id;
    dialogoConflito.value?.close();
    conflito.value = null;
    painelAberto.value = false;
    if (id) pagina.abrirCard({ id });
  };
  const restaurarMesmoAssim = async () => {
    if (!conflito.value) return;
    conflitoOcupado.value = true;
    conflitoErro.value = '';
    const resultado = await restaurar(conflito.value.alvo, { forcar: true });
    conflitoOcupado.value = false;
    if (resultado.erro) {
      conflitoErro.value = resultado.erro;
      return;
    }
    dialogoConflito.value?.close();
    conflito.value = null;
    painel.value?.recarregar();
  };

  // Depois de arquivar pela gaveta: o aviso com "Desfazer" e "Ver arquivados". `retornos`: quantos o arquivar parou,
  // para o aviso do restaurado dizer que eles não voltam. Se o Desfazer falhar, o motivo aparece num aviso novo.
  const avisarArquivado = (card, retornos = 0) => {
    const funil = pagina.funilPorId(card.pipeline_id);
    const venda = ehVenda(card.status, funil);
    const texto = [
      t('CRM_ARQUIVADOS.ARQUIVADO', { nome: nomeDoCliente(card) }),
      venda ? t('CRM_ARQUIVADOS.ARQUIVADO_VENDA') : '',
    ]
      .filter(Boolean)
      .join(' ');
    avisar(texto, [
      {
        rotulo: t('CRM_ARQUIVADOS.DESFAZER'),
        desfazer: true,
        executar: async () => {
          const resultado = await restaurar({
            ...card,
            retornos_parados: retornos,
          });
          if (resultado.erro) avisar(resultado.erro);
        },
      },
      { rotulo: t('CRM_ARQUIVADOS.VER_ARQUIVADOS'), executar: abrirPainel },
    ]);
  };
  const erroAoArquivar = error => {
    erroArquivarCard.value = t('CRM_ARQUIVADOS.ERRO_ARQUIVAR', {
      motivo: motivoDoErro(t, error),
    });
  };

  const funilArquivado = async ({
    funil,
    resposta,
    abertos,
    moveu,
    guardou,
    funilDestino,
    nomeDoDestino,
    caixas,
    funilDasCaixas,
    nomeDoFunilDasCaixas,
  }) => {
    await pagina.recarregarFunis(funilDestino);
    const partes = [t('CRM_ARQUIVADOS.FUNIL.ARQUIVADO', { funil: funil.name })];
    if (moveu)
      partes.push(
        t(
          'CRM_ARQUIVADOS.FUNIL.FORAM_PARA',
          { count: abertos, funil: nomeDoDestino },
          abertos
        )
      );
    const dois = moveu
      ? avisoDosDoisAbertos(t, pagina.juntar, resposta, nomeDoDestino)
      : null;
    if (dois) partes.push(dois);
    if (guardou)
      partes.push(
        t('CRM_ARQUIVADOS.FUNIL.FICARAM_GUARDADOS', { count: abertos }, abertos)
      );
    if (caixas.length)
      partes.push(
        funilDasCaixas
          ? t('CRM_ARQUIVADOS.FUNIL.CAIXAS_AGORA', {
              caixas: pagina.juntar(caixas),
              funil: nomeDoFunilDasCaixas,
            })
          : t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PARARAM', {
              caixas: pagina.juntar(caixas),
            })
      );
    avisar(partes.join(' '), {
      rotulo: t('CRM_ARQUIVADOS.VER_FUNIS_ARQUIVADOS'),
      executar: abrirFunis,
    });
    await contar();
  };

  const funilRestaurado = async ({ funil, abertos, caixas }) => {
    funisAbertos.value = false;
    await pagina.recarregarFunis(funil.id);
    const partes = [t('CRM_ARQUIVADOS.FUNIS.VOLTOU', { funil: funil.name })];
    if (abertos)
      partes.push(
        t('CRM_ARQUIVADOS.FUNIS.ABERTOS_VOLTARAM', { count: abertos }, abertos)
      );
    if (caixas.length)
      partes.push(
        t('CRM_ARQUIVADOS.FUNIS.CAIXAS_VOLTARAM', {
          caixas: pagina.juntar(caixas),
        })
      );
    avisar(partes.join(' '));
    await contar();
  };

  const opcaoDosFunisArquivados = computed(() => ({
    label: t('CRM_ARQUIVADOS.FUNIS.OPCAO', { count: totalDeFunis.value }),
    options: [
      {
        value: FUNIS_ARQUIVADOS,
        label: t('CRM_ARQUIVADOS.FUNIS.TITULO_N', {
          count: totalDeFunis.value,
        }),
      },
    ],
  }));

  return {
    ligar,
    painelAberto,
    funisAbertos,
    totalDoFunil,
    totalDeFunis,
    conflito,
    conflitoOcupado,
    conflitoErro,
    aoFecharConflito,
    dialogoConflito,
    painel,
    restaurandoCard,
    erroRestaurarCard,
    erroArquivarCard,
    opcaoDosFunisArquivados,
    contar,
    abrirPainel,
    abrirFunis,
    depoisDeMudar,
    restaurar,
    restaurarCardAberto,
    abrirOAberto,
    restaurarMesmoAssim,
    avisarArquivado,
    erroAoArquivar,
    funilArquivado,
    funilRestaurado,
  };
};

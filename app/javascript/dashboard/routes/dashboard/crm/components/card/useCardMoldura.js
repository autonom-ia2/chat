import { computed } from 'vue';

// #1423 — o cabeçalho e o rodapé de cada tela do card. Uma ação principal por
// tela, no mesmo lugar, e no máximo dois botões. Recebe da gaveta o estado e
// as ações (refs e funções).
const TELAS = {
  etapa: { chave: 'ETAPA', icone: 'i-lucide-columns-3' },
  negocio: { chave: 'NEGOCIO', icone: 'i-lucide-briefcase-business' },
  dono: { chave: 'DONO', icone: 'i-lucide-user-check' },
  contato: { chave: 'CONTATO', icone: 'i-lucide-contact-round' },
  empresa: { chave: 'EMPRESA', icone: 'i-lucide-building-2' },
  conversas: { chave: 'CONVERSAS', icone: 'i-lucide-messages-square' },
  'retorno-novo': { chave: 'RETORNO', icone: 'i-lucide-bell-plus' },
  agenda: { chave: 'AGENDA', icone: 'i-lucide-calendar-clock' },
  'reuniao-nova': { chave: 'REUNIAO_NOVA', icone: 'i-lucide-calendar-plus' },
  'link-agenda': { chave: 'LINK', icone: 'i-lucide-link' },
  origem: { chave: 'ORIGEM', icone: 'i-lucide-megaphone' },
  historico: { chave: 'HISTORICO', icone: 'i-lucide-history' },
};

export const useCardMoldura = ({
  t,
  tela,
  pilha,
  titulo,
  subtitulo,
  migalha,
  nome,
  jeito,
  etapa,
  contatoInicial,
  permissoes,
  estado,
  acoes,
}) => {
  const anterior = computed(() => pilha.value.at(-1));
  const voltarPara = computed(() => {
    const de = anterior.value;
    if (!de || de === 'resumo') return titulo.value;
    return jeito.texto(`${TELAS[de]?.chave || 'RESUMO'}.TELA`);
  });

  // O título do retorno novo diz o que está sendo marcado.
  const MODO_TITULO = {
    reminder_only: 'TITULO_LEMBRETE',
    snooze_conversation: 'TITULO_ESCONDER',
    auto_send_message: 'TITULO_MENSAGEM',
  };
  function tituloDa(nomeDaTela) {
    if (nomeDaTela !== 'retorno-novo') return 'TITULO';
    return MODO_TITULO[estado.modoRetorno.value] || 'TITULO';
  }
  // A reunião pelo Google/Microsoft avisa por e-mail, não pelo WhatsApp.
  function textoDa(nomeDaTela) {
    if (nomeDaTela === 'reuniao-nova' && estado.reuniaoExterna.value)
      return 'TEXTO_EXTERNA';
    return 'TEXTO';
  }

  const heroi = computed(() => {
    if (tela.value === 'criar-1' || tela.value === 'criar-2') {
      const primeiro = tela.value === 'criar-1';
      // #1498 — num funil de Atender, "Sobre o atendimento".
      let fim = jeito.atender.value ? '_ATENDER' : '';
      if (jeito.cobranca.value) fim = '_COBRANCA';
      return {
        voltar: primeiro
          ? (contatoInicial.value &&
              t('CRM_KANBAN.OPPORTUNITY.CONTEXT.BACK')) ||
            ''
          : t('CRM_CARD.CRIAR.PASSO_1'),
        migalha: [t('CRM_CARD.CRIAR.MIGALHA')],
        rotulo: t('CRM_CARD.CRIAR.ROTULO', { passo: primeiro ? 1 : 2 }),
        icone: primeiro ? 'i-lucide-user-plus' : 'i-lucide-briefcase-business',
        titulo: t(
          primeiro ? 'CRM_CARD.CRIAR.TITULO_1' : `CRM_CARD.CRIAR.TITULO_2${fim}`
        ),
        texto: t(
          primeiro ? 'CRM_CARD.CRIAR.TEXTO_1' : `CRM_CARD.CRIAR.TEXTO_2${fim}`
        ),
      };
    }
    const sub = TELAS[tela.value];
    if (!sub)
      return {
        voltar: '',
        migalha: migalha.value,
        // O topo diz em que etapa o negócio está; "Cliente" é só o selo de
        // quem já comprou, ao lado.
        rotulo: etapa.value || t('CRM_CARD.RESUMO.ROTULO'),
        icone: 'i-lucide-columns-3',
        titulo: titulo.value,
        texto: subtitulo.value,
      };
    return {
      voltar: voltarPara.value,
      migalha: [],
      rotulo: jeito.texto(`${sub.chave}.TELA`),
      icone:
        jeito.atender.value && sub.chave === 'NEGOCIO'
          ? 'i-lucide-message-square-text'
          : sub.icone,
      titulo: jeito.texto(`${sub.chave}.${tituloDa(tela.value)}`, {
        nome: nome.value,
      }),
      texto: jeito.texto(`${sub.chave}.${textoDa(tela.value)}`, {
        nome: nome.value,
      }),
    };
  });

  const neutro = rotulo => ({
    principal: { rotulo, acao: acoes.voltar, neutro: true },
  });

  const rodape = computed(() => {
    const p = permissoes;
    const e = estado;
    switch (tela.value) {
      // O resumo não tem rodapé: fechar já está no X do topo (e no Esc).
      case 'resumo':
        return null;
      case 'dono':
        if (!p.gerenciar.value) return neutro(t('CRM_CARD.VOLTAR'));
        return {
          secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: acoes.voltar },
          principal: {
            rotulo: t('CRM_CARD.SALVAR'),
            icone: 'i-lucide-check',
            acao: acoes.salvarDono,
            carregando: e.salvando.value,
            desabilitado: !e.donoSujo.value || e.salvando.value,
          },
        };
      case 'negocio':
        if (!p.gerenciar.value) return neutro(t('CRM_CARD.VOLTAR'));
        return {
          secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: acoes.voltar },
          principal: {
            rotulo: t('CRM_CARD.SALVAR'),
            icone: 'i-lucide-check',
            acao: acoes.salvarNegocio,
            carregando: e.salvando.value,
            desabilitado: !e.negocioValido.value || e.salvando.value,
          },
        };
      case 'contato':
      case 'empresa': {
        const cliente = e.cliente.value;
        if (cliente?.vinculando) return null;
        if (cliente?.editando)
          return {
            secundaria: {
              rotulo: t('CRM_CARD.CANCELAR'),
              acao: acoes.desfazerCliente,
            },
            principal: {
              rotulo: t('CRM_CARD.SALVAR'),
              icone: 'i-lucide-check',
              form: cliente.formId,
              carregando: cliente.salvando,
              desabilitado: cliente.salvando || !cliente.podeSalvar,
            },
          };
        if (cliente?.empresa)
          return {
            secundaria: {
              rotulo: t('CRM_CARD.CANCELAR'),
              acao: acoes.desfazerCliente,
            },
            principal: {
              rotulo: cliente.empresa.label,
              icone: cliente.empresa.destructive
                ? 'i-lucide-unlink'
                : 'i-lucide-check',
              form: cliente.empresa.formId,
              perigo: cliente.empresa.destructive,
              carregando: cliente.empresa.saving,
              desabilitado: cliente.empresa.disabled,
            },
          };
        return neutro(t('CRM_CARD.PRONTO'));
      }
      // Agenda: reunião e retornos. O azul é marcar um retorno.
      case 'agenda':
        if (!p.gerenciar.value) return neutro(t('CRM_CARD.VOLTAR'));
        return {
          secundaria: { rotulo: t('CRM_CARD.VOLTAR'), acao: acoes.voltar },
          principal: {
            rotulo: t('CRM_CARD.AGENDA.NOVO_LEMBRETE'),
            icone: 'i-lucide-bell-plus',
            acao: acoes.novoRetorno,
          },
        };
      case 'reuniao-nova':
        if (e.reuniaoMostrandoLink.value) return neutro(t('CRM_CARD.PRONTO'));
        return {
          secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: acoes.voltar },
          principal: {
            rotulo: t('CRM_CARD.REUNIAO_NOVA.MARCAR'),
            icone: 'i-lucide-calendar-check',
            acao: acoes.confirmarReuniao,
            carregando: e.salvandoReuniao.value,
            desabilitado: e.salvandoReuniao.value,
          },
        };
      case 'link-agenda':
        if (!e.link.value) return neutro(t('CRM_CARD.VOLTAR'));
        return {
          secundaria: { rotulo: t('CRM_CARD.VOLTAR'), acao: acoes.voltar },
          principal: e.link.value,
        };
      case 'retorno-novo':
        return {
          falta: e.salvandoRetorno.value ? '' : e.retornoFalta.value,
          secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: acoes.voltar },
          principal: {
            rotulo: t('CRM_CARD.RETORNO.CRIAR'),
            icone: 'i-lucide-check',
            acao: acoes.criarRetorno,
            carregando: e.salvandoRetorno.value,
            desabilitado: !e.retornoPronto.value || e.salvandoRetorno.value,
          },
        };
      case 'criar-1':
        return {
          secundaria: { rotulo: t('CRM_CARD.CANCELAR'), acao: acoes.fechar },
          principal: {
            rotulo: t('CRM_CARD.CONTINUAR'),
            icone: 'i-lucide-arrow-right',
            depois: true,
            acao: acoes.passo2,
            desabilitado: !e.criacao.value?.relacaoPronta,
          },
        };
      case 'criar-2':
        return {
          resumo: e.criacao.value?.summary || '',
          secundaria: { rotulo: t('CRM_CARD.VOLTAR'), acao: acoes.passo1 },
          principal: {
            rotulo: t('CRM_CARD.CRIAR.BOTAO'),
            icone: 'i-lucide-check',
            form: e.criacao.value?.formId,
            carregando: e.criacao.value?.sending,
            desabilitado: !e.criacao.value?.canSave,
          },
        };
      default:
        return neutro(t('CRM_CARD.PRONTO'));
    }
  });

  return { heroi, rodape };
};

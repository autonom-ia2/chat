import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { scheduleToUtc } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { getDeviseAuthHeaders } from 'dashboard/helper/deviseAuthHeaders';
import { diasAte } from './situacao';

// #2283 — as ações da linha, ligadas na API real:
// - "Feito": POST follow_ups/:id/complete só quando a faixa sai (10 s parada,
//   a pessoa troca de tela ou fecha a aba, com fetch keepalive); "Desfazer"
//   antes disso não chama nada (decisão 3).
// - "Combinar outro": POST follow_ups/:id/reschedule.
// - "Combinar retorno": POST follow_ups { card_id, due_at, timezone, title,
//   follow_up_type: task, automation_mode: reminder_only }.
// - "Passar para alguém" / "Ficar com este cliente": PATCH cards/:id
//   { owner_id } — só o dono do card; a conversa segue a Atribuição
//   (decisão 2).
// A linha não muda de grupo enquanto a faixa está na tela.
const L = 'CRM_LISTA_ACAO';

const contaDaUrl = () => window.location.pathname.split('/')[3];

const completarAoSair = followUpId => {
  const conta = contaDaUrl();
  const cabecalhos = getDeviseAuthHeaders();
  if (!conta || !cabecalhos) return;
  try {
    fetch(`/api/v1/accounts/${conta}/crm/follow_ups/${followUpId}/complete`, {
      method: 'POST',
      keepalive: true,
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...cabecalhos },
      body: '{}',
    }).catch(() => {});
  } catch (_) {
    // Saindo da página: não há a quem avisar. O retorno continua aberto.
  }
};

export const useAcoesDaLista = ({
  t,
  fuso,
  dados,
  faixas,
  anunciar,
  nomeDe,
  // Antes de a linha sair, guarda para onde o foco vai; devolve quem o move.
  focoDepois = () => () => {},
}) => {
  const avisarErro = () => useAlert(t(`${L}.ERROS.ACAO`));

  const feito = card => {
    const followUpId = card.next_follow_up_id;
    const nome = nomeDe(card);
    const texto = t(`${L}.FAIXA.FEITO`, { nome });
    faixas.abrir(card.id, {
      texto,
      desfazivel: true,
      aoSair: async ({ saindoDaPagina } = {}) => {
        if (saindoDaPagina) {
          completarAoSair(followUpId);
          return;
        }
        const moverFoco = focoDepois(card.id);
        dados.tirarLinha(card.id);
        moverFoco();
        try {
          await CrmKanbanAPI.completeFollowUp(followUpId);
          dados.atualizarContagem();
        } catch {
          avisarErro();
          dados.carregar();
        }
      },
    });
    anunciar(texto);
  };

  const desfazer = card => {
    if (faixas.desfazer(card.id))
      anunciar(t(`${L}.FAIXA.DESFEITO`, { nome: nomeDe(card) }));
  };

  // Faixa de confirmação (sem "Desfazer"): ao sair, a linha vira o card novo.
  const confirmar = (card, texto, mudancas) => {
    faixas.abrir(card.id, {
      texto,
      desfazivel: false,
      aoSair: () => dados.trocarLinha(card.id, mudancas),
    });
    anunciar(texto);
    dados.atualizarContagem();
  };

  // `quando`: "AAAA-MM-DDTHH:MM" escolhido no CampoQuando, lido no fuso da conta.
  // `formatado`: o mesmo horário por extenso, para a faixa.
  const combinar = async (card, { quando, formatado }) => {
    const dueAt = scheduleToUtc(quando, fuso());
    if (!dueAt || new Date(dueAt) <= new Date()) {
      useAlert(t(`${L}.ERROS.PASSOU`));
      return false;
    }
    const nome = nomeDe(card);
    const outro = Boolean(card.next_follow_up_id);
    try {
      const resposta = outro
        ? await CrmKanbanAPI.rescheduleFollowUp(card.next_follow_up_id, dueAt)
        : await CrmKanbanAPI.createFollowUp({
            card_id: card.id,
            due_at: dueAt,
            timezone: fuso(),
            title: t(`${L}.COMBINAR.TITULO_DO_RETORNO`, { nome }),
            follow_up_type: 'task',
            automation_mode: 'reminder_only',
          });
      const retorno = resposta.data?.payload || {};
      const hoje = diasAte(new Date(dueAt), new Date(), fuso()) === 0;
      confirmar(card, t(`${L}.FAIXA.COMBINOU`, { nome, quando: formatado }), {
        next_follow_up_id: retorno.id || card.next_follow_up_id,
        next_follow_up_due_at: dueAt,
        action_group: hoje ? 'retorno' : 'demais',
      });
      return true;
    } catch {
      avisarErro();
      return false;
    }
  };

  // `pessoa`: { id, name }. Eu mesmo = "Ficar com este cliente".
  const passar = async (card, pessoa, { eu }) => {
    try {
      const resposta = await CrmKanbanAPI.updateCard(card.id, {
        owner_id: pessoa.id,
      });
      const atualizado = resposta.data?.payload || {};
      const nome = nomeDe(card);
      const texto = eu
        ? t(`${L}.FAIXA.FICOU`, { nome })
        : t(`${L}.FAIXA.PASSOU`, { nome, pessoa: pessoa.name });
      confirmar(card, texto, {
        ...atualizado,
        owner_id: pessoa.id,
        action_group: 'demais',
      });
    } catch {
      avisarErro();
    }
  };

  return { feito, desfazer, combinar, passar };
};

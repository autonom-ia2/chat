// #2414 F6.3/F6.5 — as automações do motor novo no card e na etapa. Protótipo SÓ DA DEMO: esta branch não vai para
// a main. A fonte falsa só liga no build de desenvolvimento (`import.meta.env.DEV` vira `false` no build de produção)
// e só no funil que o seed da demo marcou (`metadata.demo_prototipo_2414 = { etapa_id }`). Fora disso, nada aparece.
//
// O formato é o da Automação livre (a receita com `gatilho { tipo, ... }` e `passos`), para as frases saírem do
// mesmo frases.js do editor, com o catálogo real. Aqui não há texto pronto de frase. Trocar pela API pede endpoints
// novos (o que roda num card, o histórico de execuções, parar num card) e não é trocar só este arquivo:
// - automacoesDaEtapa(etapaId) → [{ id, nome, ativa, receita: { gatilho, passos } }]
//   só as do motor novo com gatilho nesta etapa (entrou, saiu ou parado). As regras antigas da etapa vêm do store
//   real (crmKanban/fetchStageAutomations).
// - ligarNaEtapa(item, ativa) → ativa
// - automacoesDoCard(card) → [{ id, nome, receita, passoAtual, situacao: { tipo: 'espera', ate }, comecou, historico }]
//   `passoAtual` é o índice em `receita.passos`; `historico` é [{ em, passo }] com o índice de cada passo já feito.
//   Só card aberto: card ganho, perdido ou arquivado não tem automação rodando.
// - pararNoCard(card, item) → true
// `?demo=vazio` deixa tudo vazio, para ver os estados vazios.

export const MARCA_DA_DEMO = 'demo_prototipo_2414';

const SO_NO_DESENVOLVIMENTO = import.meta.env.DEV;

// A marca do seed no funil ({ etapa_id }), ou null fora da demo.
export const marcaDaDemo = funil => {
  const marca = funil?.metadata?.[MARCA_DA_DEMO];
  return SO_NO_DESENVOLVIMENTO && Number.isInteger(marca?.etapa_id)
    ? marca
    : null;
};

const D = 'AUTOMACAO_NO_CRM.DEMO';
const DIA = 86400000;

const depoisDe = (inicio, dias) =>
  new Date(new Date(inicio).getTime() + dias * DIA).toISOString();

const paraOResponsavel = { responsavel_do_card: true };

const receitasDaEtapa = (t, etapaId) => ({
  lembrete: {
    gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: etapaId },
    passos: [
      { id: 'p1', tipo: 'esperar', duracao: { valor: 3, unidade: 'dias' } },
      {
        id: 'p2',
        tipo: 'avisar',
        para: paraOResponsavel,
        texto: [t(`${D}.LEMBRETE_TEXTO`)],
      },
    ],
  },
  deNovo: {
    gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: etapaId },
    passos: [
      { id: 'p1', tipo: 'mensagem', texto: [t(`${D}.DE_NOVO_TEXTO`)] },
      { id: 'p2', tipo: 'esperar', duracao: { valor: 2, unidade: 'dias' } },
      {
        id: 'p3',
        tipo: 'avisar',
        para: paraOResponsavel,
        texto: [t(`${D}.DE_NOVO_AVISO`)],
      },
    ],
  },
  sumiu: {
    gatilho: { tipo: 'card.parado', etapa_id: etapaId, dias: 5 },
    passos: [
      {
        id: 'p1',
        tipo: 'avisar',
        para: paraOResponsavel,
        texto: [t(`${D}.SUMIU_TEXTO`)],
      },
    ],
  },
});

// Ligada ou desligada vale para a sessão inteira: desligar na etapa tira do card.
const ligadas = { 'motor-41': true, 'motor-42': true, 'motor-43': false };

export const criarFonteFalsa = ({ t, marca, vazio = false }) => {
  const etapaId = marca?.etapa_id;
  const daEtapa = id => !vazio && Boolean(marca) && Number(id) === etapaId;

  const automacoesDaEtapa = async id => {
    if (!daEtapa(id)) return [];
    const receitas = receitasDaEtapa(t, etapaId);
    return [
      ['motor-41', 'LEMBRETE', receitas.lembrete],
      ['motor-42', 'DE_NOVO', receitas.deNovo],
      ['motor-43', 'SUMIU', receitas.sumiu],
    ].map(([chave, nome, receita]) => ({
      id: chave,
      nome: t(`${D}.${nome}`),
      ativa: ligadas[chave],
      receita,
    }));
  };

  const ligarNaEtapa = async (item, ativa) => {
    ligadas[item.id] = ativa;
    return ativa;
  };

  // O card que entrou na etapa da demo: o lembrete espera os 3 dias; o "mandar de novo" já mandou a mensagem e
  // espera os 2 dias. As datas saem de quando o card entrou na etapa (o seed grava agora).
  const automacoesDoCard = async card => {
    if (card?.status !== 'open' || !daEtapa(card?.stage_id)) return [];
    const entrou = card.entered_stage_at || card.created_at;
    if (!entrou) return [];
    const receitas = receitasDaEtapa(t, etapaId);
    return [
      {
        id: 'motor-41',
        nome: t(`${D}.LEMBRETE`),
        receita: receitas.lembrete,
        passoAtual: 0,
        situacao: { tipo: 'espera', ate: depoisDe(entrou, 3) },
        comecou: entrou,
        historico: [],
      },
      {
        id: 'motor-42',
        nome: t(`${D}.DE_NOVO`),
        receita: receitas.deNovo,
        passoAtual: 1,
        situacao: { tipo: 'espera', ate: depoisDe(entrou, 2) },
        comecou: entrou,
        historico: [{ em: entrou, passo: 0 }],
      },
    ].filter(item => ligadas[item.id]);
  };

  return {
    automacoesDaEtapa,
    ligarNaEtapa,
    automacoesDoCard,
    pararNoCard: async () => true,
  };
};

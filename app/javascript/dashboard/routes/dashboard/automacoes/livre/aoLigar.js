import { todosOsPassos } from './receita';

// #2574 (F5.4) — o que a automação faz que pede confirmação antes de ligar:
// mandar mensagem aos clientes, avisar a equipe ou usar IA (paga na chave da
// conta). Sem nada disso, ela liga direto, como antes. Olha todos os passos,
// também os de dentro dos galhos.
const AOS_CLIENTES = ['mensagem', 'email'];
const DA_IA = ['decidir', 'extrair', 'escrever', 'resumir', 'para_cada'];

const mandaAosClientes = passo =>
  AOS_CLIENTES.includes(passo.tipo) ||
  (passo.tipo === 'campanha' && passo.faz === 'disparar') ||
  (passo.tipo === 'escrever' && passo.destino === 'mensagem');

// No WhatsApp, fora da janela a mensagem só sai com modelo aprovado, que a
// Meta cobra (#2468); a campanha sempre sai com modelo.
const usaModeloDaMeta = passo =>
  (passo.tipo === 'mensagem' && Boolean(passo.modelo)) ||
  (passo.tipo === 'campanha' && passo.faz === 'disparar');

export const oQueLigarFaz = receita => {
  const passos = todosOsPassos(receita?.passos || []);
  const manda = passos.some(mandaAosClientes);
  const avisa = passos.some(passo => passo.tipo === 'avisar');
  const ia = passos
    .filter(passo => DA_IA.includes(passo.tipo))
    .map(passo => passo.id);
  return {
    manda,
    avisa,
    ia,
    modeloDaMeta: passos.some(usaModeloDaMeta),
    pede: manda || avisa || ia.length > 0,
  };
};

// O custo da IA por execução, pela média de cada passo nos últimos 30 dias
// (CustosDaIa.por_passo): nunca chama a IA para estimar. Passo de IA que ainda
// não rodou deixa a soma incompleta: null, e a tela diz que o custo aparece
// depois da primeira vez.
export const custoPorExecucao = (idsDaIa, custosDosPassos) => {
  if (!idsDaIa.length) return null;
  const medias = idsDaIa.map(id => custosDosPassos?.[id]?.media);
  if (medias.some(media => typeof media !== 'number')) return null;
  return medias.reduce((soma, media) => soma + media, 0);
};

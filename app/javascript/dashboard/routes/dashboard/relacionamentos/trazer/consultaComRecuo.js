// #2896 — a espera entre uma pergunta e outra ao servidor, para quem acompanha
// uma lista sendo trazida (o andamento e o histórico). A espera cresce a cada
// pergunta, de 1,5 s até 5 s: lista grande demora minutos, e perguntar sempre
// no mesmo ritmo só gasta rede. Com a aba escondida a tarefa não roda: fica
// guardada e roda quando a aba volta.
export const INTERVALO_INICIAL_MS = 1500;
export const INTERVALO_MAXIMO_MS = 5000;

const FATOR_DO_RECUO = 1.5;
const ABA_MUDOU = 'visibilitychange';

// Uma tarefa por vez: agendar de novo troca a que estava esperando.
export const agendaComRecuo = ({
  inicial = INTERVALO_INICIAL_MS,
  maximo = INTERVALO_MAXIMO_MS,
  documento = globalThis.document,
} = {}) => {
  let relogio = null;
  let espera = inicial;
  let paraQuandoAAbaVoltar = null;

  const aoMudarAAba = () => {
    if (documento.hidden || !paraQuandoAAbaVoltar) return;
    const tarefa = paraQuandoAAbaVoltar;
    paraQuandoAAbaVoltar = null;
    documento.removeEventListener(ABA_MUDOU, aoMudarAAba);
    tarefa();
  };

  const cancelar = () => {
    clearTimeout(relogio);
    relogio = null;
    paraQuandoAAbaVoltar = null;
    documento?.removeEventListener(ABA_MUDOU, aoMudarAAba);
  };

  const rodar = tarefa => {
    relogio = null;
    if (!documento?.hidden) {
      tarefa();
      return;
    }
    paraQuandoAAbaVoltar = tarefa;
    documento.addEventListener(ABA_MUDOU, aoMudarAAba);
  };

  const agendar = tarefa => {
    cancelar();
    relogio = setTimeout(() => rodar(tarefa), espera);
    espera = Math.min(maximo, Math.round(espera * FATOR_DO_RECUO));
  };

  // A pessoa pediu de novo (ou começou outra lista): a espera volta ao começo.
  const recomecar = () => {
    cancelar();
    espera = inicial;
  };

  return { agendar, cancelar, recomecar };
};

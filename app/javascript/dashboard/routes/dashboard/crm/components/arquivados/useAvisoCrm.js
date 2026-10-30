import { ref } from 'vue';

// Aviso de pronto do CRM com ação (#2095, item 12 do protótipo): "Desfazer", "Ver", "Agendar retorno". O aviso
// global (useAlert) só tem link de rota e some em 2,5 s; este tem botão, fica 12 s quando tem ação (6 s sem) e
// para de contar enquanto o mouse ou o foco estão nele. Ctrl+Z (ou Cmd+Z) também desfaz enquanto ele aparece.
// O foco não pula para o aviso: quem usa leitor de tela ouve pela região "status" e continua onde estava.
export const DURACAO_COM_ACAO = 12000;
export const DURACAO_SIMPLES = 6000;
const PASSO = 250;
const MAXIMO = 2;

const avisos = ref([]);
let sequencia = 0;
let pausado = false;
let relogio = null;

const parar = () => {
  if (relogio) clearInterval(relogio);
  relogio = null;
};

const contar = () => {
  if (pausado) return;
  avisos.value = avisos.value
    .map(aviso => ({ ...aviso, resta: aviso.resta - PASSO }))
    .filter(aviso => aviso.resta > 0);
  if (!avisos.value.length) parar();
};

const ligarRelogio = () => {
  if (!relogio) relogio = setInterval(contar, PASSO);
};

// acoes: [{ rotulo, executar, desfazer? }] — `desfazer` liga o Ctrl+Z. Uma ação só também serve (objeto).
export const avisar = (mensagem, acoes = []) => {
  const lista = [acoes].flat().filter(Boolean);
  sequencia += 1;
  const aviso = {
    id: sequencia,
    mensagem,
    acoes: lista,
    resta: lista.length ? DURACAO_COM_ACAO : DURACAO_SIMPLES,
  };
  avisos.value = [...avisos.value.slice(-(MAXIMO - 1)), aviso];
  ligarRelogio();
  return aviso.id;
};

export const fecharAviso = id => {
  avisos.value = avisos.value.filter(aviso => aviso.id !== id);
  if (!avisos.value.length) parar();
};

export const executarAviso = (id, indice = 0) => {
  const aviso = avisos.value.find(item => item.id === id);
  fecharAviso(id);
  aviso?.acoes[indice]?.executar();
};

// O último aviso com "Desfazer" ainda na tela, para o Ctrl+Z.
export const desfazerPeloTeclado = () => {
  const aviso = [...avisos.value]
    .reverse()
    .find(item => item.acoes.some(acao => acao.desfazer));
  if (!aviso) return false;
  executarAviso(
    aviso.id,
    aviso.acoes.findIndex(acao => acao.desfazer)
  );
  return true;
};

export const pausarAvisos = valor => {
  pausado = valor;
};

// Só para os testes: volta ao estado inicial.
export const limparAvisos = () => {
  avisos.value = [];
  pausado = false;
  parar();
};

export const useAvisoCrm = () => ({
  avisos,
  avisar,
  fecharAviso,
  executarAviso,
  desfazerPeloTeclado,
  pausarAvisos,
});

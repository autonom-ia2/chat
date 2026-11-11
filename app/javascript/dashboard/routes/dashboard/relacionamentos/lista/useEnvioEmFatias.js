import { computed, ref } from 'vue';
import { useEnvio } from './useEnvio';

const ACAO = 'RELACIONAMENTOS.LISTA.ACAO';
const COMUM = 'RELACIONAMENTOS.COMUM';

// Os botões do diálogo depois que a ação começou: com gente faltando, "Tentar
// de novo com as que faltam" e "Fechar"; com tudo tentado, só "Pronto".
export const rotuloDeConfirmar = (t, resultado, antesDeComecar) => {
  if (!resultado) return antesDeComecar;
  return t(
    resultado.erro ? `${ACAO}.TENTAR_COM_AS_QUE_FALTAM` : `${ACAO}.PRONTO`
  );
};
export const rotuloDeCancelar = (t, resultado) =>
  t(resultado?.erro ? `${COMUM}.FECHAR` : `${COMUM}.CANCELAR`);

// #2894 — o envio de uma ação em grupo que a fonte manda em fatias (criar
// cards, etiquetar, apagar):
//  - `andamento` ({ feitas, total }) enquanto roda, para a tela dizer "50 de 120";
//  - `resultado` ({ feitas, deFora, faltam, erro }) somado. Se uma fatia falhou,
//    `erro` vem preenchido e o próximo envio manda só `faltam`;
//  - `fechar`: o diálogo fechou. Entrega a quem usa (`aoConcluir(faltam)`) uma
//    vez só e recomeça do zero. No meio do trabalho, pede para parar depois da
//    fatia em voo e entrega quando ela voltar: fechar não deixa a ação seguindo
//    escondida.
// `contagem` é o nome da contagem da ação na fonte (criados, aplicadas, apagadas).
export const useEnvioEmFatias = ({ contagem, mensagemDeErro, aoConcluir }) => {
  const { enviando, enviar } = useEnvio(mensagemDeErro);
  const andamento = ref(null);
  const resultado = ref(null);
  let fechouNoMeio = false;

  const terminou = computed(
    () => Boolean(resultado.value) && !resultado.value.erro
  );

  const somado = novo => ({
    feitas: (resultado.value?.feitas ?? 0) + novo[contagem],
    deFora: [...(resultado.value?.deFora ?? []), ...novo.deFora],
    faltam: novo.faltam,
    erro: novo.erro,
  });

  const entregar = () => {
    if (!resultado.value) return;
    const { faltam } = resultado.value;
    resultado.value = null;
    aoConcluir(faltam);
  };

  // `acao({ pessoas, aoAndar, deveParar })` é a escrita da fonte. Na primeira
  // vez vai com as pessoas marcadas; depois de parar no meio, só com quem falta.
  const enviarOQueFalta = async (pessoas, acao) => {
    const lote = resultado.value ? resultado.value.faltam : pessoas;
    fechouNoMeio = false;
    andamento.value = { feitas: 0, total: lote.length };
    const novo = await enviar(() =>
      acao({
        pessoas: lote,
        aoAndar: passo => {
          andamento.value = passo;
        },
        deveParar: () => fechouNoMeio,
      })
    );
    andamento.value = null;
    if (novo) resultado.value = somado(novo);
    const feito = novo ? resultado.value : null;
    if (fechouNoMeio) entregar();
    return feito;
  };

  const fechar = () => {
    if (enviando.value) fechouNoMeio = true;
    else entregar();
  };

  const recomecar = () => {
    resultado.value = null;
  };

  return {
    enviando,
    andamento,
    resultado,
    terminou,
    enviarOQueFalta,
    fechar,
    recomecar,
  };
};

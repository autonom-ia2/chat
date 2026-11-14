// #2898 — de onde "Ajustar renovações" e "Resultados das renovações" leem e
// gravam. Mesmo molde de carteiraFonte.js:
//   1. fonte real: o servidor (fonte/renovacoesFonteReal.js);
//   2. demonstração: com `?demo=<estado>` e só no ambiente de desenvolvimento.
//      Tudo é inventado, e o que é salvo fica só na memória.
// `peca` é o `?demo-carteira=` de fonte/modoCarteira.js: carregando, erro e os
// dois estados do funil que parou de servir (arquivado, apagado). O
// `import.meta.env.DEV` vira `false` no build de produção: o ramo some e os
// dados fictícios nem entram no pacote.
import { semOFunil } from '../carteira/ajustesDaRenovacao';
import { funilParou } from '../carteira/funilDasRenovacoes';
import { esperar } from './listaFonte';
import { PECA_FUNIL_APAGADO, PECA_FUNIL_ARQUIVADO } from './modoCarteira';
import {
  DEMO_CARREGANDO,
  DEMO_FORA_DO_SEGMENTO,
  DEMO_SEM_SEGUROS,
  esperarParaSempre,
} from './modoDemo';
import { renovacoesFonteReal } from './renovacoesFonteReal';
import { diasParaTerminar, estaValendo } from './selosDoSeguro';

const CARREGAR_DEMO = import.meta.env.DEV
  ? async () => {
      const [carteira, ajustes, resultados] = await Promise.all([
        import('../demo/carteira.js'),
        import('../demo/carteiraAjustes.js'),
        import('../demo/carteiraResultados.js'),
      ]);
      return { carteira, ajustes, resultados };
    }
  : null;

export const ATRASO_DAS_RENOVACOES_MS = 300;
const ESTADOS_SEM_SEGURO = ['vazio', DEMO_SEM_SEGUROS, DEMO_FORA_DO_SEGMENTO];
// Como o servidor diz que o funil escolhido parou de servir (`escolha`).
const ESCOLHA_QUE_PAROU = new Map([
  [PECA_FUNIL_ARQUIVADO, 'funil_arquivado'],
  [PECA_FUNIL_APAGADO, 'sumiu'],
]);

const erroDaDemo = () =>
  Object.assign(new Error('A demonstração pediu o erro desta peça.'), {
    name: 'ERRO_DA_DEMO',
  });

const fonteDemo = ({ estado, peca, carregarDemo, atraso }) => {
  const semSeguro = ESTADOS_SEM_SEGURO.includes(estado);

  const demo = async () => {
    if (estado === DEMO_CARREGANDO || peca === 'carregando') {
      return esperarParaSempre();
    }
    await esperar(atraso);
    if (peca === 'erro') throw erroDaDemo();
    return carregarDemo();
  };
  const daCarteira = (dados, agora) =>
    semSeguro ? [] : dados.carteira.segurosDaCarteira(agora);

  return {
    usaDemo: true,
    // As escolhas de agora e o que a tela precisa para mostrá-las: os funis da
    // conta e em quantos dias cada seguro termina (a linha "com N dias, X
    // seguros entram"). A conta sem seguro ainda não escolheu onde ficam as
    // renovações. Como no servidor, `escolha` diz como está a escolha do funil,
    // e o funil que parou de servir não vem em `ajustes`; quem salva outro
    // funil sai desse estado.
    async ajustes() {
      const dados = await demo();
      const agora = Date.now();
      const guardados = dados.ajustes.ajustesDaDemo(semSeguro);
      const parou = dados.ajustes.salvouNaDemo()
        ? undefined
        : ESCOLHA_QUE_PAROU.get(peca);
      const resposta = {
        ajustes: parou ? semOFunil(guardados) : guardados,
        escolha: parou ?? (guardados.funilId ? 'feita' : 'nunca_feita'),
        funis: dados.ajustes.FUNIS_DA_DEMO,
        vencimentos: daCarteira(dados, agora)
          .filter(seguro => estaValendo(seguro, agora))
          .map(seguro => diasParaTerminar(seguro, agora)),
        semPermissao: false,
      };
      return { ...resposta, funilParou: funilParou(resposta) };
    },
    async salvar(novos) {
      const dados = await demo();
      return dados.ajustes.salvarAjustesNaDemo(novos);
    },
    async resultados() {
      const dados = await demo();
      const agora = Date.now();
      return dados.resultados.resultadosDaDemo(daCarteira(dados, agora), agora);
    },
  };
};

export const renovacoesFonte = ({
  demo = null,
  peca = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DAS_RENOVACOES_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, peca, carregarDemo, atraso })
    : renovacoesFonteReal();

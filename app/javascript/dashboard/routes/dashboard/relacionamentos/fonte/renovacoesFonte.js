// #2897 — de onde "Ajustar renovações" (Tela 13) e "Resultados das renovações"
// (Tela 14) leem e gravam. Mesmo molde de carteiraFonte.js:
//   1. fonte real: ainda não existe; todo método diz `FONTE_REAL_PENDENTE`;
//   2. demonstração: com `?demo=<estado>` e só no ambiente de desenvolvimento.
//      Tudo é inventado, e o que é salvo fica só na memória.
// `peca` é o `?demo-carteira=` (carregando, erro), `caso` o `?caso=` e
// `cotacaoDesligada` o `?cotacao=desligada` (fonte/modoCarteira.js).
import { erroFonteRealPendente, esperar } from './listaFonte';
import { aggerLigadoNaDemo } from './modoCarteira';
import { DEMO_CARREGANDO, esperarParaSempre } from './modoDemo';
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
const ESTADOS_SEM_SEGURO = ['vazio', 'sem-seguros', 'fora-do-segmento'];
// O seguro que serve de exemplo nas prévias das mensagens.
const SEGURO_DE_EXEMPLO = 1;

const erroDaDemo = () =>
  Object.assign(new Error('A demonstração pediu o erro desta peça.'), {
    name: 'ERRO_DA_DEMO',
  });

const fonteDemo = ({
  estado,
  peca,
  caso,
  cotacaoDesligada,
  carregarDemo,
  atraso,
}) => {
  const semSeguro = ESTADOS_SEM_SEGURO.includes(estado);
  const aggerLigado = aggerLigadoNaDemo(estado);
  let falhouUmaVez = false;

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
    // conta, em quantos dias cada seguro termina (a linha "com N dias, X
    // seguros entram"), quem atende sozinho e o exemplo das prévias.
    async ajustes() {
      const dados = await demo();
      const agora = Date.now();
      const exemplo = dados.carteira.seguroPorId(SEGURO_DE_EXEMPLO, agora);
      return {
        ajustes: dados.ajustes.ajustesDaDemo(),
        funis: dados.ajustes.FUNIS_DA_DEMO,
        vencimentos: daCarteira(dados, agora)
          .filter(seguro => estaValendo(seguro, agora))
          .map(seguro => diasParaTerminar(seguro, agora)),
        aggerLigado,
        cotaSozinha: aggerLigado && !cotacaoDesligada,
        // A conta cota sem conversar com a pessoa ("Sozinho" em "Quem faz a
        // cotação?"). `?caso=ajustes_sem_sozinho`: a conta que não cota assim.
        cotaSemConversa: caso !== 'ajustes_sem_sozinho',
        // `?caso=cotacao_sem_agente`: a conta sem quem atenda sozinho.
        agente:
          caso === 'cotacao_sem_agente' ? null : dados.ajustes.AGENTE_DA_DEMO,
        semPermissao: caso === 'sem_permissao_de_funil',
        exemplo: {
          nome: exemplo.pessoa.name.split(' ')[0],
          tipo: exemplo.tipo,
          termina: exemplo.termina,
        },
      };
    },
    // `?caso=ajustes_nao_salvou` falha uma vez; a nova tentativa passa.
    async salvar(novos) {
      const dados = await demo();
      if (caso === 'ajustes_nao_salvou' && !falhouUmaVez) {
        falhouUmaVez = true;
        throw erroDaDemo();
      }
      return dados.ajustes.salvarAjustesNaDemo(novos);
    },
    async resultados() {
      const dados = await demo();
      const agora = Date.now();
      return dados.resultados.resultadosDaDemo(daCarteira(dados, agora), agora);
    },
  };
};

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    ajustes: pendente,
    salvar: pendente,
    resultados: pendente,
  };
};

export const renovacoesFonte = ({
  demo = null,
  peca = null,
  caso = null,
  cotacaoDesligada = false,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DAS_RENOVACOES_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({
        estado: demo,
        peca,
        caso,
        cotacaoDesligada,
        carregarDemo,
        atraso,
      })
    : fonteReal();

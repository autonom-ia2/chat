// G18 (#2671) — o passo "em outro registro" na tela. Os passos de dentro dele
// rodam num registro ligado ao alvo (o contato guardado num campo, ou os outros
// cards do mesmo contato), cada registro na sua vez. Aqui ficam: em que registro
// o ramo roda (é ele que diz quais dados os passos de dentro podem usar), a
// frase da linha e o "pronto" da peça do painel. A régua de verdade é a do
// servidor (Autonomia::Automacao::EmOutroRegistro).
import { tipoCriado } from './catalogo';
import {
  OUTRO_REGISTRO,
  RAIZ,
  acharPasso,
  galhosDe,
  idDaLista,
  naMesmaExecucao,
  registroPronto,
} from './receita';

export { registroPronto };

const O = 'AUTOMACAO_LIVRE.OUTRO_REGISTRO';

export const TIPO = OUTRO_REGISTRO;
// G49: `criado_no_passo`, o contato ou o card que um passo anterior criou.
export const LIGACOES = [
  'contato_do_campo',
  'cards_do_contato',
  'criado_no_passo',
];
export const USOS = ['conversa', 'contato'];
export const SITUACOES = ['open', 'won', 'lost'];

// O tipo do registro em que o ramo roda, como no servidor (alvo_do_ramo). No
// `criado_no_passo` (G49), o do registro que o passo escolhido cria.
export const alvoDoRamo = (passo, passos = []) => {
  const registro = passo?.registro || {};
  if (registro.de === 'cards_do_contato') return 'Crm::Card';
  if (registro.de === 'criado_no_passo')
    return tipoCriado(acharPasso(passos, registro.passo));
  return registro.usar === 'contato' ? 'Contact' : 'Conversation';
};

// A lista ('raiz' ou '<passo>:<ramo>') em que o passo `id` está; null se não
// achar.
export const listaDoPasso = (passos, id, listaId = RAIZ) => {
  const lista = passos || [];
  if (lista.some(passo => passo.id === id)) return listaId;
  return lista.reduce(
    (achada, passo) =>
      achada ||
      galhosDe(passo).reduce(
        (dentro, galho) =>
          dentro ||
          listaDoPasso(galho.passos, id, idDaLista(passo.id, galho.ramo)),
        null
      ),
    null
  );
};

// Em que registro os passos da lista rodam: o do ramo do "em outro registro"
// que a contém (mesmo dentro de um "se" dentro dele); null = o alvo do
// gatilho. O id do passo vem antes do último ":" (o ramo não tem ":").
export const alvoDaLista = (passos, listaId) => {
  if (!listaId || listaId === RAIZ) return null;
  const dono = acharPasso(passos, listaId.slice(0, listaId.lastIndexOf(':')));
  if (!dono) return null;
  if (dono.tipo === TIPO) return alvoDoRamo(dono, passos);
  return alvoDaLista(passos, listaDoPasso(passos, dono.id));
};

// Os passos da execução em que a lista roda (#2679 × G18): dentro do ramo do
// "em outro registro", os do ramo (a execução filha); fora, os da receita sem
// os ramos dele. É de onde vêm os textos da IA que o passo pode ler.
export const passosDaExecucao = (passos, listaId) => {
  if (!listaId || listaId === RAIZ) return naMesmaExecucao(passos);
  const dono = acharPasso(passos, listaId.slice(0, listaId.lastIndexOf(':')));
  if (!dono) return naMesmaExecucao(passos);
  if (dono.tipo === TIPO) return naMesmaExecucao(dono.passos || []);
  return passosDaExecucao(passos, listaDoPasso(passos, dono.id));
};

// `campo`: o nome do campo que guarda o contato, já em palavras; no
// `criado_no_passo` (G49), o nome do registro criado ("Card criado…").
export const fraseDoOutroRegistro = (passo, t, campo = '') => {
  const registro = passo.registro || {};
  if (registro.de === 'contato_do_campo')
    return t(
      `${O}.FRASE.${registro.usar === 'contato' ? 'CONTATO' : 'CONVERSA'}`,
      {
        campo: campo || '…',
      }
    );
  if (registro.de === 'criado_no_passo')
    return t(`${O}.FRASE.CRIADO`, { registro: campo || '…' });
  if (registro.de !== 'cards_do_contato') return t(`${O}.FRASE.SEM_LIGACAO`);
  const filtros = [
    ...(registro.situacao || []).map(valor =>
      t(`${O}.SITUACOES.${valor.toUpperCase()}`)
    ),
    ...(registro.funil_id ? [t(`${O}.FRASE.NO_FUNIL`)] : []),
  ];
  const frase = t(
    `${O}.FRASE.${registro.mais_recente ? 'CARD_MAIS_RECENTE' : 'CARDS'}`
  );
  return [frase, ...filtros].join(' · ');
};

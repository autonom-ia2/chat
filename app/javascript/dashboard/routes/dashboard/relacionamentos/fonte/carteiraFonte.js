// #2897 — de onde a carteira de seguros lê e grava (molde: listaFonte.js e
// fichaFonte.js). A tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real: o servidor (fonte/carteiraFonteReal.js);
//   2. demonstração: com `?demo=<estado>` e só no ambiente de desenvolvimento.
//      Os dados são inventados (demo/carteira.js), a escrita só fica na memória
//      e tudo demora um instante, como a rede.
// `peca` é o `?demo-carteira=` (fonte/modoCarteira.js): muda só esta fonte
// (carregando, erro, vazio). O `import.meta.env.DEV` vira `false` no build de
// produção: o ramo some e a carteira fictícia nem entra no pacote.
import { carteiraFonteReal } from './carteiraFonteReal';
import {
  ABA_SEGUROS,
  GRUPOS_DE_SEGUROS,
  GRUPO_PADRAO_DE_SEGUROS,
  seguroPertenceAoGrupo,
} from './gruposDeSeguros';
import { POR_PAGINA, combinaComBusca, esperar } from './listaFonte';
import {
  DEMO_CARREGANDO,
  DEMO_FORA_DO_SEGMENTO,
  DEMO_SEM_SEGUROS,
  esperarParaSempre,
} from './modoDemo';
import {
  diasParaTerminar,
  estaValendo,
  porUrgencia,
  seloDoSeguro,
} from './selosDoSeguro';
import { NAO_ACHEI } from '../ficha/falhas';

const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/carteira.js')
  : null;

export const ATRASO_DA_CARTEIRA_MS = 300;
const PRIMEIRA_PAGINA = 1;
const LOCALE_DA_ORDEM_ALFABETICA = 'pt-BR';

export const ORDENS_DE_SEGUROS = {
  VENCE_PRIMEIRO: 'vence_primeiro',
  NOME: 'nome',
  MAIS_NOVOS: 'mais_novos',
};

// O que a gaveta "Mais filtros" da aba Seguros filtra. `cuida` (#2898) é o id
// de quem cuida da renovação do seguro.
export const FILTROS_DE_SEGUROS_VAZIOS = Object.freeze({
  tipo: '',
  seguradora: '',
  cuida: '',
});

export const contarFiltrosDeSeguros = (filtros = {}) =>
  Object.keys(FILTROS_DE_SEGUROS_VAZIOS).filter(chave => filtros[chave]).length;

// ---- ordem, busca e filtros da demonstração ---------------------------------

// Quem ainda vale vem antes, do que termina mais cedo ao mais tarde; depois os
// outros, do que terminou há menos tempo ao mais antigo.
const venceAntes = agora => (a, b) => {
  const valeA = estaValendo(a, agora);
  const valeB = estaValendo(b, agora);
  if (valeA !== valeB) return valeA ? -1 : 1;
  return valeA ? a.termina - b.termina : b.termina - a.termina;
};

// Como no servidor: o que começou há menos tempo primeiro; sem data de início,
// por último.
const comecouDepois = (a, b) => {
  if (a.comeca === null || b.comeca === null) {
    return Number(a.comeca === null) - Number(b.comeca === null);
  }
  return b.comeca - a.comeca;
};

const ordenador = (ordem, agora) =>
  ({
    [ORDENS_DE_SEGUROS.NOME]: (a, b) =>
      a.segurado.nome.localeCompare(
        b.segurado.nome,
        LOCALE_DA_ORDEM_ALFABETICA
      ),
    [ORDENS_DE_SEGUROS.MAIS_NOVOS]: comecouDepois,
  })[ordem] ?? venceAntes(agora);

// Como no servidor: letras buscam no nome da pessoa, no do segurado, no número
// e no bem; só número busca no número da apólice.
const camposDoSeguro = seguro => ({
  textos: [seguro.pessoa.name, seguro.segurado.nome, seguro.numero, seguro.bem],
  numeros: [seguro.numero],
});

const passaNosFiltros = (seguro, { tipo, seguradora, cuida } = {}) =>
  (!tipo || seguro.tipo === tipo) &&
  (!seguradora || seguro.seguradora === seguradora) &&
  (!cuida || seguro.renovacao?.cuidaId === cuida);

const passaNaConsulta =
  ({ busca = '', filtros = {} } = {}) =>
  seguro =>
    combinaComBusca(busca, camposDoSeguro(seguro)) &&
    passaNosFiltros(seguro, filtros);

const unicos = lista => [...new Set(lista.filter(Boolean))].sort();

// Como no servidor (Carteira::OpcoesDeFiltro): quem cuida de alguma renovação
// da carteira, uma vez cada, pelo nome.
const quemCuida = seguros =>
  [
    ...new Map(
      seguros
        .map(seguro => seguro.renovacao)
        .filter(renovacao => renovacao?.cuidaId)
        .map(({ cuidaId, cuida }) => [cuidaId, { id: cuidaId, nome: cuida }])
    ).values(),
  ].sort((a, b) => a.nome.localeCompare(b.nome, LOCALE_DA_ORDEM_ALFABETICA));

const empresaSegurada = seguro =>
  seguro.segurado.tipo === 'empresa' ? seguro.segurado.id : null;

// A lista de pessoas, como no servidor (Carteira::ResumoPorPessoa): quantos
// seguros a pessoa tem e o selo, o tipo e os dias do que mais pede atenção.
// Quem não tem seguro não entra.
const resumoDosSeguros = (seguros, agora) => {
  const [urgente] = porUrgencia(seguros, agora);
  return urgente
    ? {
        quantos: seguros.length,
        selo: seloDoSeguro(urgente, agora),
        tipo: urgente.tipo,
        dias: diasParaTerminar(urgente, agora),
      }
    : null;
};

// ---- demonstração -----------------------------------------------------------

const ESTADOS_SEM_SEGURO = ['vazio', DEMO_SEM_SEGUROS, DEMO_FORA_DO_SEGMENTO];
const ESCRITAS = [
  'corrigir',
  'cancelar',
  'voltarAAtivo',
  'guardarPdf',
  'tirarPdf',
  // #2898 — como a renovação terminou e a apólice nova escrita à mão.
  'renovou',
  'naoRenovou',
  'desfazerDesfecho',
  'apoliceNova',
];
// O "PDF" da demonstração: uma página em branco do navegador.
const PDF_DA_DEMO = 'about:blank';
const ARQUIVO_DA_DEMO = { name: 'apolice-de-exemplo.pdf' };

const erroDaDemo = () =>
  Object.assign(new Error('A demonstração pediu o erro desta peça.'), {
    name: 'ERRO_DA_DEMO',
  });

const naoAchei = () =>
  Object.assign(new Error('Este seguro não está mais aqui.'), {
    name: NAO_ACHEI,
  });

const fonteDemo = ({ estado, peca, carregarDemo, atraso }) => {
  const semSeguro = ESTADOS_SEM_SEGURO.includes(estado) || peca === 'vazio';

  const demo = async () => {
    if (estado === DEMO_CARREGANDO || peca === 'carregando') {
      return esperarParaSempre();
    }
    await esperar(atraso);
    if (peca === 'erro') throw erroDaDemo();
    return (await carregarDemo()).demoDaCarteira;
  };
  const daCarteira = async agora =>
    semSeguro ? (await demo(), []) : (await demo()).segurosDaCarteira(agora);
  // O seguro pedido, ou a falha `NAO_ACHEI`, como o servidor.
  const umSeguro = async id => {
    const dados = await demo();
    if (semSeguro || !dados.seguroPorId(id)) throw naoAchei();
    return dados;
  };

  const achar = async ({
    grupo = GRUPO_PADRAO_DE_SEGUROS,
    busca = '',
    ordem = ORDENS_DE_SEGUROS.VENCE_PRIMEIRO,
    filtros = {},
  } = {}) => {
    const agora = Date.now();
    return (await daCarteira(agora))
      .filter(seguro =>
        seguroPertenceAoGrupo(seguro, grupo || GRUPO_PADRAO_DE_SEGUROS, agora)
      )
      .filter(passaNaConsulta({ busca, filtros }))
      .sort(ordenador(ordem, agora));
  };

  const escrita =
    nome =>
    async (id, ...resto) =>
      (await umSeguro(id))[nome](id, ...resto);

  return {
    usaDemo: true,
    async resumo() {
      const agora = Date.now();
      const seguros = await daCarteira(agora);
      return {
        total: seguros.length,
        vence7: seguros.filter(seguro =>
          seguroPertenceAoGrupo(seguro, 'vence_7_dias', agora)
        ).length,
      };
    },
    // `aba` vem de quem usa a lista (lista/useLista.js) e aqui não muda nada.
    async contagens(aba, consulta = {}) {
      const agora = Date.now();
      const lista = (await daCarteira(agora)).filter(passaNaConsulta(consulta));
      return Object.fromEntries(
        GRUPOS_DE_SEGUROS.map(({ id }) => [
          id,
          lista.filter(seguro => seguroPertenceAoGrupo(seguro, id, agora))
            .length,
        ])
      );
    },
    async listar(pedido = {}) {
      const { pagina = PRIMEIRA_PAGINA } = pedido;
      const achados = await achar(pedido);
      const inicio = (pagina - PRIMEIRA_PAGINA) * POR_PAGINA;
      return {
        itens: achados.slice(inicio, inicio + POR_PAGINA),
        total: achados.length,
        temMais: inicio + POR_PAGINA < achados.length,
      };
    },
    async opcoesDeFiltro() {
      const seguros = await daCarteira(Date.now());
      return {
        tipos: unicos(seguros.map(seguro => seguro.tipo)),
        seguradoras: unicos(seguros.map(seguro => seguro.seguradora)),
        cuida: quemCuida(seguros),
      };
    },
    // Como no servidor: os seguros em que a pessoa é o contato, inclusive
    // aqueles em que o segurado é a empresa dela.
    async daPessoa(id) {
      const agora = Date.now();
      const dela = (await daCarteira(agora)).filter(
        seguro => seguro.pessoaId === id
      );
      return porUrgencia(dela, agora);
    },
    async daEmpresa(id) {
      const agora = Date.now();
      const dela = (await daCarteira(agora)).filter(
        seguro => empresaSegurada(seguro) === id
      );
      return porUrgencia(dela, agora);
    },
    // A lista de pessoas: o selo de seguro de cada pessoa da página (`ids`).
    async resumoPorPessoa(ids = []) {
      const agora = Date.now();
      const seguros = await daCarteira(agora);
      return Object.fromEntries(
        ids
          .map(id => [
            id,
            resumoDosSeguros(
              seguros.filter(seguro => seguro.pessoaId === id),
              agora
            ),
          ])
          .filter(([, resumo]) => resumo)
      );
    },
    seguro: async id => (await umSeguro(id)).seguroPorId(id),
    historia: async id => (await umSeguro(id)).historiaDoSeguro(id),
    ...Object.fromEntries(ESCRITAS.map(nome => [nome, escrita(nome)])),
    // #2899 (E6.2) — a demonstração não lê PDF (o resumo dela não liga a
    // leitura): ler devolve "nada mudou" e guardar o lido guarda o PDF.
    async lerPdf(id) {
      await umSeguro(id);
      return { leituraId: 0, outraApolice: false, mudancas: [] };
    },
    guardarPdfLido: async id =>
      (await umSeguro(id)).guardarPdf(id, ARQUIVO_DA_DEMO),
    async pdf(id) {
      await umSeguro(id);
      return PDF_DA_DEMO;
    },
  };
};

export const carteiraFonte = ({
  demo = null,
  peca = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_CARTEIRA_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, peca, carregarDemo, atraso })
    : carteiraFonteReal();

export { ABA_SEGUROS };

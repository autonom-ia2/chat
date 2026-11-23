import CustomViewsAPI from 'dashboard/api/customViews';
import { FILTROS_VAZIOS } from '../lista/filtros';
import {
  MODELOS,
  OPERADORES,
  TIPOS,
  paraOServidor,
} from '../lista/informacoes';
import { VISOES } from './gruposDeCompra';

// #3168 — "Meus grupos": o que a pessoa da equipe guardou com um nome. No
// servidor são `custom_filters` de contato (filter_type: contact), os mesmos
// dos Segmentos da lista de contatos de hoje, de cada pessoa da equipe, com
// `query = { payload, relacionamentos: { visao, grupo, busca, filtros } }`: o
// `payload` (as linhas de "Por outra informação") a tela antiga ainda lê; o
// `relacionamentos` é o que esta lista reaplica. Segmento salvo pela tela
// antiga (sem `relacionamentos`) não aparece aqui.
// Cada grupo: { id, nome, visao, grupo, busca, filtros } — o que a pessoa via
// quando guardou (a visão de onde veio, a pílula, a busca e os filtros). Nada
// aqui muta o que devolveu antes. Na demonstração os grupos ficam na memória até
// a página recarregar, e `?guardados=exemplo` começa com três inventados.
export const GUARDADOS_DE_EXEMPLO = 'exemplo';

const condicao = (id, chave, tipo, como, valor) => ({
  id,
  chave,
  tipo,
  modelo: MODELOS.PADRAO,
  como,
  valor,
});

const deExemplo = (nome, { grupo = 'todos', filtros }) => ({
  nome,
  visao: VISOES.CONVERSA,
  grupo,
  busca: '',
  filtros: { ...FILTROS_VAZIOS, ...filtros },
});

const EXEMPLOS = [
  deExemplo('Clientes de Campinas', {
    grupo: 'clientes',
    filtros: { cidade: 'Campinas' },
  }),
  deExemplo('Sumiram há mais de 90 dias', {
    filtros: {
      condicoes: [
        condicao(
          1,
          'last_activity_at',
          TIPOS.DATA,
          OPERADORES.HA_MAIS_DE_DIAS,
          '90'
        ),
      ],
    },
  }),
  deExemplo('Vieram da feira', { filtros: { etiqueta: 'feira' } }),
];

let guardados = [];
let proximoId = 1;
let comecouComExemplo = false;

const novoGrupo = dados => {
  const grupo = { ...dados, id: `guardado_${proximoId}` };
  proximoId += 1;
  return grupo;
};

export const esquecerGruposGuardados = () => {
  guardados = [];
  proximoId = 1;
  comecouComExemplo = false;
};

const TIPO = 'contact';

const doServidor = ({ id, name, query }) => {
  const salvo = query?.relacionamentos;
  if (!salvo) return null;
  return {
    id: String(id),
    nome: name,
    visao: salvo.visao ?? VISOES.CONVERSA,
    grupo: salvo.grupo ?? 'todos',
    busca: salvo.busca ?? '',
    filtros: { ...FILTROS_VAZIOS, ...salvo.filtros },
  };
};

const paraGuardar = ({ nome, visao, grupo, busca, filtros }) => ({
  custom_filter: {
    name: nome,
    filter_type: TIPO,
    query: {
      payload: paraOServidor(filtros?.condicoes, filtros?.juntar),
      relacionamentos: { visao, grupo, busca, filtros },
    },
  },
});

const doServidorFonte = () => ({
  async listar() {
    const { data } = await CustomViewsAPI.getCustomViewsByFilterType(TIPO);
    return data.map(doServidor).filter(Boolean);
  },
  async criar(dados) {
    const { data } = await CustomViewsAPI.create(paraGuardar(dados));
    return doServidor(data);
  },
  // `grupo`: o grupo inteiro, já com a mudança (useMeusGrupos junta os dois).
  async mudar(id, grupo) {
    const { data } = await CustomViewsAPI.update(id, paraGuardar(grupo));
    return doServidor(data);
  },
  async apagar(id) {
    await CustomViewsAPI.deleteCustomViews(id, TIPO);
  },
});

// `demo`: na demonstração, os grupos da memória; fora dela, os do servidor.
export const gruposGuardadosFonte = ({
  demo = false,
  exemplo = false,
} = {}) => {
  if (!demo) return doServidorFonte();

  if (exemplo && !comecouComExemplo) {
    comecouComExemplo = true;
    guardados = [...guardados, ...EXEMPLOS.map(novoGrupo)];
  }
  return {
    async listar() {
      return guardados;
    },
    async criar(dados) {
      const grupo = novoGrupo(dados);
      guardados = [...guardados, grupo];
      return grupo;
    },
    async mudar(id, mudancas) {
      guardados = guardados.map(grupo =>
        grupo.id === id ? { ...grupo, ...mudancas } : grupo
      );
      return guardados.find(grupo => grupo.id === id);
    },
    async apagar(id) {
      guardados = guardados.filter(grupo => grupo.id !== id);
    },
  };
};

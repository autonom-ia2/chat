import { FILTROS_VAZIOS } from '../lista/filtros';
import { MODELOS, OPERADORES, TIPOS } from '../lista/informacoes';
import { VISOES } from './gruposDeCompra';

// #3168 — "Meus grupos": o que a pessoa da equipe guardou com um nome. No
// servidor eles serão `custom_filters` de contato (filter_type: contact), como
// os Segmentos de hoje, com `query = { payload, relacionamentos: { visao,
// grupo, busca, filtros } }`; essa leitura chega junto com o servidor das
// condições. Por enquanto só
// existe a da demonstração: os grupos ficam na memória até a página recarregar.
// Cada grupo: { id, nome, visao, grupo, busca, filtros } — o que a pessoa via
// quando guardou (a visão de onde veio, a pílula, a busca e os filtros). Nada
// aqui muta o que devolveu antes. `?guardados=exemplo` começa com três grupos
// inventados.
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

export const gruposGuardadosFonte = ({ exemplo = false } = {}) => {
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

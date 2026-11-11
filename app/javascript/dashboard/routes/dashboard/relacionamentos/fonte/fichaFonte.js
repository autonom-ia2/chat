// #2894 — de onde a ficha de Relacionamentos lê e grava (molde: listaFonte.js). A
// tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real (#2895): lê pelas leituras da ficha
//      (dashboard/api/relacionamentos.js) e escreve pelos endpoints que o painel
//      já tem (contato, nota, empresa). Depois de escrever, relê a pessoa ou a
//      empresa pela leitura da ficha e devolve isso. O que o servidor recusa
//      ganha nome (ficha/falhas.js): 404 é NAO_ACHEI, 401 e 403 são SEM_ACESSO;
//      o resto sobe como veio;
//   2. demonstração: com `?demo=<estado>` (modoDemo.js) e só no ambiente de
//      desenvolvimento. Os dados são inventados (demo/ficha.js), a escrita só
//      fica na memória e tudo demora um instante, como a rede.
// O `import.meta.env.DEV` vira `false` no build de produção: o ramo some e os
// dados fictícios nem entram no pacote.
import CompanyAPI from 'dashboard/api/companies';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { NAO_ACHEI, SEM_ACESSO } from '../ficha/falhas';
import { demoCarregando, esperarParaSempre } from './modoDemo';

const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/ficha.js')
  : null;

export const ATRASO_DA_FICHA_MS = 300;

// O que cada método devolve quando a conta está vazia (?demo=vazio): ninguém
// existe, então toda leitura volta sem nada e toda escrita diz "não achei".
const LEITURAS = {
  pessoa: null,
  conversas: [],
  cards: [],
  notas: [],
  arquivos: [],
  origem: null,
  empresa: null,
  pessoasDaEmpresa: [],
  conversasDaEmpresa: [],
  cardsDaEmpresa: [],
};
const ESCRITAS = [
  'salvar',
  'salvarEmpresa',
  'marcarCliente',
  'desmarcarCliente',
  'guardarNota',
  'liberarMensagens',
];
const METODOS = [...Object.keys(LEITURAS), ...ESCRITAS];

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const naoAchei = () =>
  Object.assign(new Error('Não achei esta pessoa.'), { name: NAO_ACHEI });

// As leituras que abrem a ficha: em `?demo=carregando` nenhuma resposta chega.
const LEITURAS_DA_FICHA = ['pessoa', 'empresa'];

const fonteDemo = ({ estado, carregarDemo, atraso }) => {
  const metodo =
    nome =>
    async (...argumentos) => {
      if (LEITURAS_DA_FICHA.includes(nome) && demoCarregando()) {
        return esperarParaSempre();
      }
      await esperar(atraso);
      if (estado === 'vazio') {
        if (nome in LEITURAS) return LEITURAS[nome];
        throw naoAchei();
      }
      const { demoDaFicha } = await carregarDemo();
      return demoDaFicha[nome](...argumentos);
    };
  return {
    usaDemo: true,
    ...Object.fromEntries(METODOS.map(nome => [nome, metodo(nome)])),
  };
};

// ---- fonte real ------------------------------------------------------------

const NOME_DO_ERRO = new Map([
  [404, NAO_ACHEI],
  [401, SEM_ACESSO],
  [403, SEM_ACESSO],
]);

const comNome = falha => {
  const nome = NOME_DO_ERRO.get(falha?.response?.status);
  return nome
    ? Object.assign(new Error(falha.message, { cause: falha }), { name: nome })
    : falha;
};

// `pedido()` é uma ida ao servidor: devolve o corpo da resposta.
const noServidor = async pedido => {
  try {
    return (await pedido()).data;
  } catch (falha) {
    throw comNome(falha);
  }
};

const lerPessoa = id => noServidor(() => RelacionamentosAPI.pessoa(id));
const lerEmpresa = id => noServidor(() => RelacionamentosAPI.empresa(id));

// A nota como o contato devolve (id, content, user, created_at), no formato que
// a lista de notas mostra.
const notaDaTela = nota => ({
  id: nota.id,
  autor: nota.user?.name ?? null,
  quando: nota.created_at,
  texto: nota.content,
});

// O CNPJ mora em `additional_attributes` (o servidor junta com o que já havia).
// Site e CNPJ apagados vão como `null`: no banco os dois são únicos por conta
// quando não são nulos, e texto vazio em duas empresas bateria uma na outra.
const corpoDaEmpresa = ({ name, cnpj, domain }) => ({
  company: {
    name,
    domain: domain || null,
    additional_attributes: { cnpj: cnpj || null },
  },
});

const fonteReal = () => ({
  usaDemo: false,
  pessoa: lerPessoa,
  conversas: id => noServidor(() => RelacionamentosAPI.conversasDaPessoa(id)),
  cards: id => noServidor(() => RelacionamentosAPI.cardsDaPessoa(id)),
  notas: id => noServidor(() => RelacionamentosAPI.notasDaPessoa(id)),
  arquivos: id => noServidor(() => RelacionamentosAPI.arquivosDaPessoa(id)),
  origem: id => noServidor(() => RelacionamentosAPI.origemDaPessoa(id)),
  empresa: lerEmpresa,
  pessoasDaEmpresa: id =>
    noServidor(() => RelacionamentosAPI.pessoasDaEmpresa(id)),
  conversasDaEmpresa: id =>
    noServidor(() => RelacionamentosAPI.conversasDaEmpresa(id)),
  cardsDaEmpresa: id => noServidor(() => RelacionamentosAPI.cardsDaEmpresa(id)),
  // `dados` já vem no formato do contato (ficha/informacoes.js).
  async salvar(id, dados) {
    await noServidor(() => ContactAPI.update(id, dados));
    return lerPessoa(id);
  },
  async marcarCliente(id) {
    await noServidor(() => ContactAPI.markCustomer(id));
    return lerPessoa(id);
  },
  async desmarcarCliente(id) {
    await noServidor(() => ContactAPI.removeCustomer(id));
    return lerPessoa(id);
  },
  async liberarMensagens(id) {
    await noServidor(() => ContactAPI.removeOptOut(id));
    return lerPessoa(id);
  },
  async guardarNota(id, texto) {
    return notaDaTela(
      await noServidor(() => ContactNotesAPI.create(id, texto))
    );
  },
  async salvarEmpresa(id, dados) {
    await noServidor(() => CompanyAPI.update(id, corpoDaEmpresa(dados)));
    return lerEmpresa(id);
  },
});

export const fichaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_FICHA_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso })
    : fonteReal();

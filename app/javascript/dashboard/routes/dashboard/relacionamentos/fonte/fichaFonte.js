// #2894 — de onde a ficha de Relacionamentos lê e grava (molde: listaFonte.js). A
// tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real (#2895): lê pelas leituras da ficha
//      (dashboard/api/relacionamentos.js) e escreve pelos endpoints que o painel
//      já tem (contato, nota, empresa). Depois de escrever, relê a pessoa ou a
//      empresa pela leitura da ficha e devolve isso. O que o servidor recusa
//      ganha nome (ficha/falhas.js): 404 é NAO_ACHEI, 401 e 403 são SEM_ACESSO;
//      o resto sobe como veio;
//      #3071 — e as ações que vieram da ficha antiga: juntar com outra pessoa
//      (actions/contact_merge: a pessoa da ficha fica, a outra é absorvida),
//      bloquear e desbloquear (o PATCH do contato, campo `blocked`), apagar
//      (DELETE contacts/:id), pôr e tirar etiqueta (contacts/:id/labels/alterar,
//      só o que mudou), apagar nota e marcar "não quer mensagens" (opt_out);
//      #3075 — salvar grava o pedido inteiro da gaveta (fonte/gravarPessoa.js:
//      empresa nova, foto e campos que saem) e `buscarEmpresas` acha as
//      empresas da conta para a escolha da gaveta;
//   2. demonstração: com `?demo=<estado>` (modoDemo.js) e só no ambiente de
//      desenvolvimento. Os dados são inventados (demo/ficha.js), a escrita só
//      fica na memória e tudo demora um instante, como a rede.
// O `import.meta.env.DEV` vira `false` no build de produção: o ramo some e os
// dados fictícios nem entram no pacote.
import AccountActionsAPI from 'dashboard/api/accountActions';
import CompanyAPI from 'dashboard/api/companies';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import ContactAPI from 'dashboard/api/contacts';
import EtiquetasDoContatoAPI from 'dashboard/api/etiquetasDoContato';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { NAO_ACHEI, SEM_ACESSO } from '../ficha/falhas';
import { alterarPessoa, buscarEmpresas } from './gravarPessoa';
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
  etiquetasDaConta: [],
  buscarPessoas: [],
  buscarEmpresas: [],
};
const ESCRITAS = [
  'salvar',
  'salvarEmpresa',
  'marcarCliente',
  'desmarcarCliente',
  'guardarNota',
  'liberarMensagens',
  'marcarNaoQuer',
  'bloquear',
  'desbloquear',
  'apagar',
  'juntar',
  'alterarEtiquetas',
  'apagarNota',
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

// #3075 — como `noServidor` (abaixo), para quem já devolve o que interessa
// (fonte/gravarPessoa.js).
const comNomeNaFalha = async acao => {
  try {
    return await acao();
  } catch (falha) {
    throw comNome(falha);
  }
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

// Para escolher com quem juntar: a busca da lista nova (nome, telefone, e-mail,
// empresa, CPF), sem a própria pessoa.
const buscarPessoas = async (termo, semId) => {
  const { itens } = await noServidor(() =>
    RelacionamentosAPI.pessoas({ busca: termo })
  );
  return itens.filter(item => item.id !== semId);
};

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
  // `pedido` vem da gaveta (ficha/informacoes.js#pedidoParaSalvar).
  async salvar(id, pedido) {
    await comNomeNaFalha(() => alterarPessoa(id, pedido));
    return lerPessoa(id);
  },
  buscarEmpresas: termo => comNomeNaFalha(() => buscarEmpresas(termo)),
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
  async marcarNaoQuer(id) {
    await noServidor(() => ContactAPI.markOptOut(id));
    return lerPessoa(id);
  },
  async bloquear(id) {
    await noServidor(() => ContactAPI.update(id, { blocked: true }));
    return lerPessoa(id);
  },
  async desbloquear(id) {
    await noServidor(() => ContactAPI.update(id, { blocked: false }));
    return lerPessoa(id);
  },
  async apagar(id) {
    await noServidor(() => ContactAPI.delete(id));
  },
  // A pessoa da ficha (`id`) fica; a escolhida (`outraId`) é absorvida.
  async juntar(id, outraId) {
    await noServidor(() => AccountActionsAPI.merge(id, outraId));
    return lerPessoa(id);
  },
  // As etiquetas da conta, com a cor, como a lista lê (acoesDaListaFonte.js).
  async etiquetasDaConta() {
    const { data } = await LabelsAPI.get(true);
    return data.payload
      .map(({ title, color }) => ({ nome: title, cor: color }))
      .sort((a, b) => a.nome.localeCompare(b.nome));
  },
  buscarPessoas,
  // Só o que mudou: { por, tirar }. O servidor aplica sobre a lista que está
  // gravada, e a etiqueta que outra pessoa pôs no meio-tempo não some.
  async alterarEtiquetas(id, mudanca) {
    await noServidor(() => EtiquetasDoContatoAPI.alterar(id, mudanca));
    return lerPessoa(id);
  },
  async apagarNota(id, notaId) {
    await noServidor(() => ContactNotesAPI.delete(id, notaId));
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

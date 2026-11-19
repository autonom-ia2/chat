// #3075 — grava o que a gaveta "Alterar informações" pediu (o pedido de
// ficha/informacoes.js#pedidoParaSalvar), pelos endpoints que o painel já tem,
// na ficha e na lista ("Nova pessoa" e "Editar"):
//  1. empresa nova: antes de cadastrar, procura o nome exato entre as empresas
//     da conta (sem diferença de maiúscula e de espaço nas pontas) e, se achar,
//     usa a que existe; senão cadastra pelo nome (POST companies). A pessoa vai
//     com o `company_id` dela;
//  2. a pessoa: cria (POST contacts) ou altera (PATCH contacts/:id);
//  3. a foto nova vai num PATCH só com o arquivo; "tirar a foto" é o
//     DELETE contacts/:id/avatar;
//  4. os campos personalizados esvaziados saem de verdade
//     (POST contacts/:id/destroy_custom_attributes), como o "Apagar" da antiga.
// Devolve o contato criado ou alterado (o que o servidor respondeu ao passo 2).
//
// Quando um passo falha depois de outro já ter gravado, a falha sobe como
// `GravouEmParte` (com a `response` da original, para quem lê o 422), levando a
// `retomada`: { empresa, pessoa, contato }. `empresa` ({ id, nome }) é a que já
// está cadastrada; `pessoa` é o contato já gravado e `contato`, o que foi
// mandado nele. Quem tenta de novo passa a `retomada` de volta, e só repete o
// que falta: não cadastra outra empresa, não cria a pessoa de novo e não manda
// o contato outra vez se ele não mudou. Sem nada gravado, a falha sobe como
// veio.
import CompanyAPI from 'dashboard/api/companies';
import ContactAPI from 'dashboard/api/contacts';

export const GRAVOU_EM_PARTE = 'GravouEmParte';

const gravouEmParte = (falha, retomada) =>
  Object.assign(
    new Error(falha?.message ?? GRAVOU_EM_PARTE, { cause: falha }),
    {
      name: GRAVOU_EM_PARTE,
      response: falha?.response,
      retomada,
    }
  );

// Sobe a falha com o que já ficou gravado, ou como veio se nada ficou.
const comRetomada = async (passo, retomada) => {
  try {
    return await passo();
  } catch (falha) {
    if (!retomada.empresa && !retomada.pessoa) throw falha;
    throw gravouEmParte(falha, retomada);
  }
};

const chaveDoNome = nome =>
  String(nome ?? '')
    .trim()
    .toLocaleLowerCase();
const mesmoNome = (a, b) => chaveDoNome(a) === chaveDoNome(b);

const acharPeloNome = async nome => {
  const { data } = await CompanyAPI.search(nome.trim());
  return (data.payload ?? []).find(empresa => mesmoNome(empresa.name, nome));
};

const cadastrarEmpresa = async nome => {
  const achada = await acharPeloNome(nome);
  if (achada) return { id: achada.id, nome: achada.name };
  const { data } = await CompanyAPI.create({ company: { name: nome.trim() } });
  return { id: data.payload.id, nome: data.payload.name };
};

const empresaDoPedido = async (pedido, retomada) => {
  if (!pedido.empresaNova) return null;
  if (retomada?.empresa && mesmoNome(retomada.empresa.nome, pedido.empresaNova))
    return retomada.empresa;
  return cadastrarEmpresa(pedido.empresaNova);
};

const contatoComEmpresa = (contato, empresa) =>
  empresa
    ? {
        ...contato,
        company_id: empresa.id,
        additional_attributes: {
          ...contato.additional_attributes,
          company_name: empresa.nome,
        },
      }
    : contato;

const comArquivo = arquivo => {
  const corpo = new FormData();
  corpo.append('avatar', arquivo);
  return corpo;
};

const depoisDeGravar = async (id, { foto, apagar = [] }) => {
  if (foto?.arquivo) await ContactAPI.update(id, comArquivo(foto.arquivo));
  if (foto?.tirar) await ContactAPI.destroyAvatar(id);
  if (apagar.length) await ContactAPI.destroyCustomAttributes(id, apagar);
};

// Os passos 2 a 4, com o que a tentativa anterior já gravou. `id`: o da pessoa
// que já existe (na criação, o que o servidor devolver).
const gravarComPassos = async (pedido, retomada, gravarContato, id = null) => {
  const empresa = await empresaDoPedido(pedido, retomada);
  const contato = contatoComEmpresa(pedido.contato, empresa);
  const enviado = JSON.stringify(contato);
  const jaFoi = Boolean(retomada?.pessoa) && retomada.contato === enviado;
  const feito = { empresa, pessoa: null, contato: null };
  const pessoa = jaFoi
    ? retomada.pessoa
    : await comRetomada(() => gravarContato(contato), feito);
  await comRetomada(() => depoisDeGravar(id ?? pessoa.id, pedido), {
    empresa,
    pessoa,
    contato: enviado,
  });
  return pessoa;
};

const criarContato = async contato => {
  const { data } = await ContactAPI.create(contato);
  return data.payload.contact;
};

const alterarContato = id => async contato => {
  const { data } = await ContactAPI.update(id, contato);
  return data.payload;
};

// A pessoa que a tentativa anterior já criou é alterada, não criada de novo.
export const criarPessoa = (pedido, retomada = null) =>
  retomada?.pessoa
    ? gravarComPassos(
        pedido,
        retomada,
        alterarContato(retomada.pessoa.id),
        retomada.pessoa.id
      )
    : gravarComPassos(pedido, retomada, criarContato);

export const alterarPessoa = (id, pedido, retomada = null) =>
  gravarComPassos(pedido, retomada, alterarContato(id), id);

// A busca de empresas da conta para a escolha da gaveta: { id, nome }.
export const buscarEmpresas = async termo => {
  const { data } = await CompanyAPI.search(termo);
  return (data.payload ?? []).map(({ id, name }) => ({ id, nome: name }));
};

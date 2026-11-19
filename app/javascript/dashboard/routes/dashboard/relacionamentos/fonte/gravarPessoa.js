// #3075 — grava o que a gaveta "Alterar informações" pediu (o pedido de
// ficha/informacoes.js#pedidoParaSalvar), pelos endpoints que o painel já tem,
// na ficha e na lista ("Nova pessoa" e "Editar"):
//  1. empresa nova: cadastra pelo nome (POST companies) e a pessoa vai com o
//     `company_id` dela;
//  2. a pessoa: cria (POST contacts) ou altera (PATCH contacts/:id);
//  3. a foto nova vai num PATCH só com o arquivo; "tirar a foto" é o
//     DELETE contacts/:id/avatar;
//  4. os campos personalizados esvaziados saem de verdade
//     (POST contacts/:id/destroy_custom_attributes), como o "Apagar" da antiga.
// Devolve o contato criado ou alterado (o que o servidor respondeu ao passo 2).
// O que o servidor recusa sobe como veio.
import CompanyAPI from 'dashboard/api/companies';
import ContactAPI from 'dashboard/api/contacts';

const cadastrarEmpresa = async nome => {
  const { data } = await CompanyAPI.create({ company: { name: nome } });
  return data.payload;
};

const comEmpresaNova = async pedido => {
  if (!pedido.empresaNova) return pedido.contato;
  const empresa = await cadastrarEmpresa(pedido.empresaNova);
  return {
    ...pedido.contato,
    company_id: empresa.id,
    additional_attributes: {
      ...pedido.contato.additional_attributes,
      company_name: empresa.name,
    },
  };
};

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

export const criarPessoa = async pedido => {
  const contato = await comEmpresaNova(pedido);
  const { data } = await ContactAPI.create(contato);
  const criada = data.payload.contact;
  await depoisDeGravar(criada.id, pedido);
  return criada;
};

export const alterarPessoa = async (id, pedido) => {
  const contato = await comEmpresaNova(pedido);
  const { data } = await ContactAPI.update(id, contato);
  await depoisDeGravar(id, pedido);
  return data.payload;
};

// A busca de empresas da conta para a escolha da gaveta: { id, nome }.
export const buscarEmpresas = async termo => {
  const { data } = await CompanyAPI.search(termo);
  return (data.payload ?? []).map(({ id, name }) => ({ id, nome: name }));
};

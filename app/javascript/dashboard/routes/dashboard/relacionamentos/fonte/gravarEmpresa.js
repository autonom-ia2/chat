// #3078 — grava o que a gaveta da empresa pediu (o pedido de
// ficha/informacoesDaEmpresa.js#pedidoDaEmpresa), pelos endpoints de empresas
// que o painel já tem (Enterprise), na ficha ("Alterar informações") e na lista
// ("Nova empresa"):
//  1. a empresa: cria (POST companies) ou altera (PATCH companies/:id);
//  2. a foto nova vai num PATCH só com o arquivo; "tirar a foto" é o
//     DELETE companies/:id/avatar;
//  3. os campos personalizados esvaziados saem de verdade
//     (POST companies/:id/destroy_custom_attributes), como na ficha antiga.
// Devolve a empresa como o servidor respondeu ao passo 1.
//
// Quando a foto ou um campo que sai falha depois de a empresa ficar gravada, a
// falha sobe como `GravouEmParte` (o mesmo nome de fonte/gravarPessoa.js), com
// a `response` da original e a `retomada`: { empresa }. Quem tenta de novo passa
// a `retomada` de volta: a empresa nova que já foi criada é alterada, não
// criada outra vez.
import CompanyAPI from 'dashboard/api/companies';
import { GRAVOU_EM_PARTE } from './gravarPessoa';

const gravouEmParte = (falha, empresa) =>
  Object.assign(
    new Error(falha?.message ?? GRAVOU_EM_PARTE, { cause: falha }),
    { name: GRAVOU_EM_PARTE, response: falha?.response, retomada: { empresa } }
  );

const comArquivo = arquivo => {
  const corpo = new FormData();
  corpo.append('company[avatar]', arquivo);
  return corpo;
};

const depoisDeGravar = async (id, { foto, apagar = [] }) => {
  if (foto?.arquivo) await CompanyAPI.update(id, comArquivo(foto.arquivo));
  if (foto?.tirar) await CompanyAPI.destroyAvatar(id);
  if (apagar.length) await CompanyAPI.destroyCustomAttributes(id, apagar);
};

const gravarComPassos = async (pedido, gravar) => {
  const { data } = await gravar({ company: pedido.empresa });
  const empresa = data.payload;
  try {
    await depoisDeGravar(empresa.id, pedido);
  } catch (falha) {
    throw gravouEmParte(falha, empresa);
  }
  return empresa;
};

export const alterarEmpresa = (id, pedido) =>
  gravarComPassos(pedido, corpo => CompanyAPI.update(id, corpo));

// A empresa que a tentativa anterior já criou é alterada, não criada de novo.
export const criarEmpresa = (pedido, retomada = null) =>
  retomada?.empresa
    ? alterarEmpresa(retomada.empresa.id, pedido)
    : gravarComPassos(pedido, corpo => CompanyAPI.create(corpo));

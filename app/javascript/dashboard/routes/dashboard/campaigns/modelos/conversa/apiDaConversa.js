// A camada de dados da conversa (#1716), no mesmo formato da dos Modelos
// (../api/modelosWhatsapp.js), mas pelas rotas de quem atende a caixa
// (Whatsapp::Templates::ConversationAssetsPolicy), sem a tela de Modelos.
// Erros da API chegam como ErroDaApi { codigo, mensagem (já traduzida), status }.
import api from 'dashboard/api/whatsappConversationAssets';
import { ErroDaApi, produtoDaApi } from '../api/adaptadorHttp';

const chamar = async promessa => {
  try {
    const { data } = await promessa;
    return data;
  } catch (erro) {
    throw new ErroDaApi(erro);
  }
};

// { nome, produtos } | null (sem catálogo ou com a flag desligada: 404).
const obterCatalogo = async caixa => {
  try {
    const { catalog } = await chamar(api.getCatalog(caixa));
    return catalog
      ? { nome: catalog.name, produtos: catalog.product_count }
      : null;
  } catch (erro) {
    if (erro.status === 404) return null;
    throw erro;
  }
};

const listarProdutos = async (caixa, { busca = '', depois = '' } = {}) => {
  const { payload, meta } = await chamar(
    api.getProducts(caixa, { search: busca.trim(), after: depois })
  );
  return { produtos: payload.map(produtoDaApi), depois: meta?.after || '' };
};

// Os escolhidos relidos do catálogo, na hora de enviar (o que saiu não volta).
const conferirProdutos = async (caixa, ids) => {
  if (!ids.length) return [];
  const { payload } = await chamar(api.getProducts(caixa, { ids }));
  return payload.map(produtoDaApi);
};

// A foto do computador para um cartão: { referencia, nome }.
const subirArquivoDaCampanha = async (caixa, arquivo) => {
  const subido = await chamar(api.uploadPhoto(caixa, arquivo));
  return { referencia: subido.blob_signed_id, nome: subido.file_name };
};

// O perfil do modelo: { fields, card_media }.
const lerPerfil = (caixa, template) =>
  chamar(
    api.getTemplate(caixa, {
      name: template.name,
      language: template.language,
    })
  );

export default {
  obterCatalogo,
  listarProdutos,
  conferirProdutos,
  subirArquivoDaCampanha,
  lerPerfil,
};

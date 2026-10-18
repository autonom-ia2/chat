// O perfil do modelo no Chat2You (#1330), para a conversa (#1716): os campos
// que o contato preenche sozinho (`fields`, como na campanha) e a galeria do
// modelo — as fotos aprovadas de cada cartão, guardadas no perfil
// (`card_media`, com a miniatura e a referência do arquivo). Uma leitura, pela
// rota de quem atende a caixa; sem resposta, a tela segue sem preencher e sem galeria, e
// avisa (`falhou`) para a pessoa tentar de novo.
import api from './apiDaConversa';

export const perfilDaApi = perfil => {
  const galeria = (perfil?.card_media || [])
    .filter(midia => midia.preview_url && midia.blob_signed_id)
    .map(midia => ({
      url: midia.preview_url,
      referencia: midia.blob_signed_id,
      nome: midia.file_name,
      cartao: midia.card_index,
    }));
  return { campos: perfil?.fields || {}, galeria, falhou: false };
};

export const lerPerfilDoModelo = async (caixa, template) => {
  try {
    return perfilDaApi(await api.lerPerfil(caixa, template));
  } catch {
    return { ...perfilDaApi(null), falhou: true };
  }
};

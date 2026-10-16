// O perfil do modelo no Chat2You (#1330), para a conversa (#1716): os campos
// que o contato preenche sozinho (`fields`, como na campanha) e a galeria do
// modelo — as fotos aprovadas de cada cartão, guardadas no perfil
// (`card_media`, com a miniatura e a referência do arquivo). Uma leitura da
// lista da caixa; sem resposta, a tela segue sem preencher e sem galeria, e
// avisa (`falhou`) para a pessoa tentar de novo.
import api from 'dashboard/api/whatsappTemplates';

const mesmoModelo = (item, template) =>
  item.name === template.name &&
  String(item.language || '').toLowerCase() ===
    String(template.language || '').toLowerCase();

export const perfilDaLista = (lista, template) => {
  const item = (lista || []).find(modelo => mesmoModelo(modelo, template));
  const galeria = (item?.card_media || [])
    .filter(midia => midia.preview_url && midia.blob_signed_id)
    .map(midia => ({
      url: midia.preview_url,
      referencia: midia.blob_signed_id,
      nome: midia.file_name,
      cartao: midia.card_index,
    }));
  return { campos: item?.fields || {}, galeria, falhou: false };
};

export const lerPerfilDoModelo = async (caixa, template) => {
  try {
    const { data } = await api.getTemplates(caixa);
    return perfilDaLista(data?.payload, template);
  } catch {
    return { ...perfilDaLista([], template), falhou: true };
  }
};

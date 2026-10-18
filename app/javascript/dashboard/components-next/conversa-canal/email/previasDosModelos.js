// Prévias dos modelos de e-mail na janela de escolher (#1786): pedidas e compiladas uma
// vez por modelo, divididas entre todos os cartões enquanto a página estiver aberta.
import ModelosDeEmailAPI from 'dashboard/api/modelosDeEmail';
import { montarModelo } from './modeloDeEmail';

const previas = new Map();

export const previaDoModelo = id => {
  if (!previas.has(id)) {
    previas.set(
      id,
      ModelosDeEmailAPI.previa(id)
        .then(({ data }) => montarModelo({ mjml: data.mjml, html: data.html }))
        .catch(erro => {
          previas.delete(id);
          throw erro;
        })
    );
  }
  return previas.get(id);
};

// Prévias dos modelos de e-mail na janela de escolher (#1786): pedidas e compiladas uma
// vez por modelo, divididas entre todos os cartões enquanto a página estiver aberta.
// No máximo POR_VEZ compilações ao mesmo tempo: uma conta com 40 modelos não trava a aba.
import ModelosDeEmailAPI from 'dashboard/api/modelosDeEmail';
import { montarModelo } from './modeloDeEmail';

const POR_VEZ = 3;
const previas = new Map();
const fila = [];
let rodando = 0;

const proxima = () => {
  if (rodando >= POR_VEZ || !fila.length) return;
  const { tarefa, resolver, recusar } = fila.shift();
  rodando += 1;
  tarefa()
    .then(resolver, recusar)
    .finally(() => {
      rodando -= 1;
      proxima();
    });
};

const naFila = tarefa =>
  new Promise((resolver, recusar) => {
    fila.push({ tarefa, resolver, recusar });
    proxima();
  });

export const previaDoModelo = id => {
  if (!previas.has(id)) {
    previas.set(
      id,
      naFila(() =>
        ModelosDeEmailAPI.previa(id).then(({ data }) =>
          montarModelo({ mjml: data.mjml, html: data.html })
        )
      ).catch(erro => {
        previas.delete(id);
        throw erro;
      })
    );
  }
  return previas.get(id);
};

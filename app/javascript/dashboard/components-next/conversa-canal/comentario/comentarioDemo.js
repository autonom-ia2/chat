// PROTÓTIPO (#2215): adaptador falso só para a demo de aprovação. Sai na implementação.
// Estados por ?demo=: permissao | apagado | escondido | anuncio | so-ver (padrão: comentário do post, tudo liberado).
const espera = () =>
  new Promise(resolve => {
    setTimeout(resolve, 600);
  });

const modo = () => new URLSearchParams(window.location.search).get('demo');

const RAFA = {
  autor: '@rafa.lopes',
  texto: 'Golpe! Paguei e ninguém me atende!!',
  onde: 'anuncio',
};
const MARINA = {
  autor: '@marina.costa',
  texto:
    'Quanto custa o plano para família de 4 pessoas? Tem carência para consulta?',
  onde: 'post',
};

const comentario = id => ({
  id: '17900000000000001',
  ...(String(id) === '23' ? RAFA : MARINA),
  quando: new Date(Date.now() - 42 * 60 * 1000).toISOString(),
  escondido: modo() === 'escondido',
  respostas: [],
});

export const apiDemo = {
  async get(id) {
    await espera();
    if (modo() === 'permissao')
      return { data: { status: 'needs_permission', pode_liberar: true } };
    if (modo() === 'apagado') return { data: { status: 'apagado' } };
    const soVer = modo() === 'so-ver';
    return {
      data: {
        status: 'ok',
        comentario: comentario(id),
        pode: { responder: !soVer, esconder: !soVer, apagar: !soVer },
      },
    };
  },
  async responder(_id, content) {
    await espera();
    return { data: { resposta: { id: `r${Date.now()}`, texto: content } } };
  },
  async esconder(_id, hidden) {
    await espera();
    return { data: { escondido: hidden } };
  },
  async apagar() {
    await espera();
    return { data: { status: 'apagado' } };
  },
};

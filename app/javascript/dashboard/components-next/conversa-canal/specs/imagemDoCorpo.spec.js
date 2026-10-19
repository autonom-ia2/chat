import { abrirImagemDoCorpo } from '../email/imagemDoCorpo';

// #1869, conversa 320: a foto do iPhone veio dentro do corpo (<img>), não como anexo.
const clicar = html => {
  const corpo = document.createElement('div');
  corpo.innerHTML = html;
  const alvo = corpo.querySelector('[data-alvo]');
  abrirImagemDoCorpo({ target: alvo });
};

describe('imagem dentro do corpo do e-mail', () => {
  beforeEach(() => {
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });
  afterEach(() => vi.restoreAllMocks());

  it('clicar na foto abre a imagem inteira numa aba nova', () => {
    const src = `${window.location.origin}/rails/active_storage/blobs/redirect/x/image0.jpeg`;
    clicar(`<p>RV</p><img data-alvo src="${src}" alt="image0.jpeg">`);
    expect(window.open).toHaveBeenCalledWith(
      src,
      '_blank',
      'noopener,noreferrer'
    );
  });

  it('imagem dentro de link segue o link; texto e endereço que não é web não abrem', () => {
    clicar(
      '<a href="https://x.test"><img data-alvo src="https://x.test/a.png"></a>'
    );
    clicar('<p data-alvo>texto</p>');
    clicar('<img data-alvo src="data:image/png;base64,AAAA">');
    expect(window.open).not.toHaveBeenCalled();
  });
});

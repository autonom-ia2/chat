import { htmlDoTextoComImagens } from '../email/imagemNoTextoDoEmail';

// #1942 — imagem que o Chatwoot põe dentro do texto puro do e-mail vira imagem; o resto
// continua texto.
const URL_DA_IMAGEM = `${window.location.origin}/rails/active_storage/blobs/redirect/abc/image0.jpeg`;
const COM_IMAGEM = `Esse é um teste\n\n<img src="${URL_DA_IMAGEM}" alt="image0.jpeg">`;
const ler = html => {
  const div = document.createElement('div');
  div.innerHTML = html;
  return div;
};

describe('htmlDoTextoComImagens', () => {
  it('a tag do Chatwoot vira <img>; o texto fica, com as quebras de linha', () => {
    const div = ler(htmlDoTextoComImagens(COM_IMAGEM));
    const img = div.querySelector('img');
    expect(img.getAttribute('src')).toBe(URL_DA_IMAGEM);
    expect(img.getAttribute('alt')).toBe('image0.jpeg');
    expect(div.textContent).toBe('Esse é um teste');
    expect(div.querySelectorAll('br')).toHaveLength(2);
  });

  it('sem imagem, nada: o texto segue como texto', () => {
    expect(htmlDoTextoComImagens('Oi\nTudo bem?')).toBe('');
    expect(htmlDoTextoComImagens('')).toBe('');
  });

  it('o resto não vira HTML: endereço entre "<>" e tag escrita pela pessoa ficam texto', () => {
    const texto = `De: Ana <ana@x.com>\n<b>negrito</b> <script>x</script>\n<img src="${URL_DA_IMAGEM}" alt="a.png">`;
    const div = ler(htmlDoTextoComImagens(texto));
    expect(div.querySelector('b, script')).toBeNull();
    expect(div.textContent).toContain('De: Ana <ana@x.com>');
    expect(div.textContent).toContain('<b>negrito</b> <script>x</script>');
    expect(div.querySelectorAll('img')).toHaveLength(1);
  });

  it('formato incompleto ou endereço com aspas: fica texto', () => {
    expect(htmlDoTextoComImagens(`<img src="${URL_DA_IMAGEM}">`)).toBe('');
    expect(
      htmlDoTextoComImagens(
        `<img src="${URL_DA_IMAGEM}" onerror="alert(1)" alt="y">`
      )
    ).toBe('');
    expect(
      htmlDoTextoComImagens(`<img src="${URL_DA_IMAGEM}" alt="a" b="c">`)
    ).toBe('');
  });

  it('tag escrita pelo remetente fora dos arquivos do painel fica texto (sem pixel)', () => {
    const pixel = '<img src="https://rastreio.test/p.gif" alt="x">';
    const outraRota = `<img src="${window.location.origin}/api/v1/profile" alt="x">`;
    expect(htmlDoTextoComImagens(pixel)).toBe('');
    expect(htmlDoTextoComImagens(outraRota)).toBe('');
    const div = ler(htmlDoTextoComImagens(`${pixel}\n${COM_IMAGEM}`));
    expect(div.querySelectorAll('img')).toHaveLength(1);
    expect(div.textContent).toContain(pixel);
  });
});

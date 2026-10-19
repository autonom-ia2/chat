// Citação de e-mails que o extrator do Chatwoot não reconhece (#1786): o histórico que
// o iPhone/Apple Mail põe em <blockquote type="cite"> e o bloco "De: / Enviado: / Para:"
// do Outlook em qualquer idioma (o extrator só procura "From:" e "Sent:" em inglês).
// Lê a estrutura do HTML (DOM), sem regex. Devolve o HTML sem a citação e se achou.
import DOMPurify from 'dompurify';

// Outlook marca o começo da resposta citada com estes ids (web, Windows e Mac).
const INICIOS_DO_OUTLOOK = [
  '#divRplyFwdMsg',
  '#appendonsend',
  '#mail-editor-reference-message-container',
];
// No Outlook para Windows o bloco "De:" vem numa div com este fio no topo.
const FIO_DO_OUTLOOK = 'border-top:solid #e1e1e1';

const semEspacos = texto =>
  String(texto || '')
    .split(' ')
    .join('')
    .toLowerCase();

// Tira o elemento e tudo o que vem depois dele no mesmo nível (o resto é a citação).
const cortarDaqui = elemento => {
  let atual = elemento;
  while (atual) {
    const proximo = atual.nextSibling;
    atual.remove();
    atual = proximo;
  }
};

export const semCitacaoDosLeitores = html => {
  const raiz = document.createElement('div');
  raiz.innerHTML = DOMPurify.sanitize(String(html || ''));
  let achou = false;

  raiz.querySelectorAll('blockquote[type="cite"]').forEach(bloco => {
    achou = true;
    bloco.remove();
  });

  const inicio =
    INICIOS_DO_OUTLOOK.map(seletor => raiz.querySelector(seletor)).find(
      Boolean
    ) ||
    [...raiz.querySelectorAll('div[style]')].find(div =>
      semEspacos(div.getAttribute('style')).includes(semEspacos(FIO_DO_OUTLOOK))
    );
  if (inicio) {
    achou = true;
    cortarDaqui(inicio);
  }

  return { html: raiz.innerHTML, achou };
};

// #2858 F2 — a busca da vitrine: por trecho de texto, sem acento e sem diferença de maiúscula, com método de string
// (sem regex). Todas as palavras digitadas precisam estar no texto do cartão (nome, apoio, o que faz e o grupo). A
// busca pelo sentido ficaria com o modelo; por ora medimos as buscas que não acham nada (`criarRegistroDeBusca`).

const ACENTOS_INICIO = 0x300;
const ACENTOS_FIM = 0x36f;

export const semAcento = texto =>
  [...String(texto ?? '').normalize('NFD')]
    .filter(caractere => {
      const codigo = caractere.charCodeAt(0);
      return codigo < ACENTOS_INICIO || codigo > ACENTOS_FIM;
    })
    .join('')
    .toLowerCase();

export const palavrasDaBusca = busca =>
  semAcento(busca).trim().split(' ').filter(Boolean);

// `textoDe(ferramenta)`: o texto do cartão (a tela junta os textos do i18n). Sem palavra, todas.
export const filtrarFerramentas = (ferramentas, busca, textoDe) => {
  const palavras = palavrasDaBusca(busca);
  if (!palavras.length) return ferramentas;
  return ferramentas.filter(ferramenta => {
    const texto = semAcento(textoDe(ferramenta));
    return palavras.every(palavra => texto.includes(palavra));
  });
};

export const MINIMO_DE_LETRAS = 3;
export const ESPERA_DA_BUSCA = 1500;

// A busca sem resultado vai ao servidor uma vez por termo, depois de a pessoa parar de digitar. Termo curto (menos de
// três letras) não conta: é a pessoa no meio da palavra. `registrar(termo)` é a chamada ao servidor.
export const criarRegistroDeBusca = ({
  registrar,
  espera = ESPERA_DA_BUSCA,
  minimo = MINIMO_DE_LETRAS,
}) => {
  const registrados = new Set();
  let relogio = null;

  const cancelar = () => {
    if (relogio) window.clearTimeout(relogio);
    relogio = null;
  };

  // Chamar a cada mudança da busca: `semResultado` diz se o termo atual não achou nenhum cartão.
  const observar = (busca, semResultado) => {
    cancelar();
    const termo = String(busca ?? '').trim();
    const chave = palavrasDaBusca(termo).join(' ');
    if (!semResultado || chave.length < minimo || registrados.has(chave)) {
      return;
    }
    relogio = window.setTimeout(async () => {
      relogio = null;
      registrados.add(chave);
      // Falhou: o termo volta a valer, e a próxima busca igual tenta de novo.
      const registrou = await registrar(termo);
      if (registrou === false) registrados.delete(chave);
    }, espera);
  };

  return { observar, cancelar };
};

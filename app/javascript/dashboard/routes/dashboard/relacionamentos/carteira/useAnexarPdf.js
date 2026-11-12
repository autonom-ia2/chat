// #2897 — guardar o PDF de um seguro: a pessoa escolhe (ou solta) o arquivo e
// ele já sobe. O PDF só fica guardado; nada é lido dele. Fala com a fonte e
// guarda o estado; o diálogo só desenha. Arquivo grande demais nem é enviado
// (carteira/useLimiteDoPdf.js). Quando o servidor recusa, a frase sai do código
// da recusa (carteira/recusas.js) e nunca traz o nome do arquivo.
import { ref } from 'vue';
import { ARQUIVO_GRANDE, chaveDaRecusa, codigoDaRecusa } from './recusas';
import { useLimiteDoPdf } from './useLimiteDoPdf';

const NAO_GUARDOU = 'RELACIONAMENTOS_CARTEIRA.PDF.NAO_GUARDOU';

export const useAnexarPdf = fonte => {
  const cabe = useLimiteDoPdf();
  const seguro = ref(null);
  // A chave do catálogo da frase de erro; vazia quando não há erro.
  const erro = ref('');
  const guardando = ref(false);

  const comecar = alvo => {
    seguro.value = alvo;
    erro.value = '';
  };

  // O arquivo pode ser enviado? Quando não pode, a frase fica em `erro`.
  const conferir = arquivo => {
    const cabeAqui = cabe(arquivo);
    erro.value = cabeAqui ? '' : chaveDaRecusa(ARQUIVO_GRANDE, NAO_GUARDOU);
    return cabeAqui;
  };

  // Devolve o seguro como ficou, ou null se não deu.
  const guardar = async arquivo => {
    if (!conferir(arquivo)) return null;
    guardando.value = true;
    try {
      return await fonte.guardarPdf(seguro.value.id, arquivo);
    } catch (falha) {
      erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_GUARDOU);
      return null;
    } finally {
      guardando.value = false;
    }
  };

  return { seguro, erro, guardando, comecar, conferir, guardar };
};

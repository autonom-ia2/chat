// #2897 — os PDFs das apólices: escolher (vários de uma vez) e acompanhar a
// leitura ("Lendo 12 de 40…"). Quando termina, `aoLer` recebe o que foi achado.
import { onScopeDispose, ref } from 'vue';
import { acompanhar } from './acompanhar';
import { soApolices } from './arquivosDeApolice';

export const INTERVALO_DA_LEITURA_MS = 600;

export const ERROS_DOS_PDFS = {
  NENHUM: '',
  NENHUM_PDF: 'NENHUM_PDF',
  NAO_LEU: 'NAO_LEU',
};

export const useLeituraDePdfs = ({
  fonte,
  aoLer,
  intervalo = INTERVALO_DA_LEITURA_MS,
}) => {
  const arquivos = ref([]);
  const lendo = ref(false);
  const lidos = ref(0);
  const erro = ref(ERROS_DOS_PDFS.NENHUM);
  let vigia = null;

  const parar = () => {
    vigia?.parar();
    vigia = null;
  };

  // Do que a pessoa soltou, ficam os PDFs e as fotos; sem nenhum, a tela diz.
  const escolher = soltos => {
    const servem = soApolices(soltos).map(({ name }) => ({ name }));
    erro.value = servem.length
      ? ERROS_DOS_PDFS.NENHUM
      : ERROS_DOS_PDFS.NENHUM_PDF;
    if (servem.length) arquivos.value = servem;
  };

  const usarExemplo = async () => {
    escolher(await fonte.pdfsDeExemplo());
  };

  const escolherOutros = () => {
    arquivos.value = [];
    erro.value = ERROS_DOS_PDFS.NENHUM;
  };

  const falhou = () => {
    lendo.value = false;
    erro.value = ERROS_DOS_PDFS.NAO_LEU;
  };

  const ler = async () => {
    parar();
    lendo.value = true;
    lidos.value = 0;
    erro.value = ERROS_DOS_PDFS.NENHUM;
    try {
      const { leituraId } = await fonte.lerPdfs(arquivos.value);
      vigia = acompanhar({
        intervalo,
        consultar: () => fonte.andamentoDosPdfs(leituraId),
        aoChegar: andamento => {
          lidos.value = andamento.lidos;
          if (!andamento.leitura) return false;
          lendo.value = false;
          aoLer(andamento.leitura);
          return true;
        },
        aoFalhar: falhou,
      });
    } catch {
      falhou();
    }
  };

  onScopeDispose(parar);

  return {
    arquivos,
    lendo,
    lidos,
    erro,
    escolher,
    usarExemplo,
    escolherOutros,
    ler,
  };
};

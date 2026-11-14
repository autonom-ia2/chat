import { ref } from 'vue';
import { useAnexarPdf, ETAPAS } from '../../carteira/useAnexarPdf';
import { leituraDePdf } from '../../carteira/leituraDePdf';
import {
  ETAPAS_DOS_PDFS,
  useLeituraDePdfs,
} from '../../carteira/useLeituraDePdfs';
import { recusa } from './apoio';

// #2899 (E6) — a leitura de PDF na tela: anexar e ver o que mudou (E6.2), a
// pergunta "a conta lê PDF?" (decisão D4) e o caminho de "Trazer por PDFs"
// (E6.4). As fontes são de mentira: nada aqui fala com o servidor nem com IA.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
vi.mock('dashboard/api/relacionamentosTrazerPdfs', () => ({ default: {} }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({ maximumFileUploadSize: 40 }),
}));

const SEGURO = { id: 7, temPdf: false };
const ARQUIVO = { name: 'apolice.pdf', size: 10 };

const mudanca = (campo, usar, extra = {}) => ({
  campo,
  antes: 'a',
  noPdf: 'b',
  corrigidoAMao: false,
  confira: false,
  usar,
  ...extra,
});

describe('useAnexarPdf com a leitura', () => {
  const comFonte = fonte => {
    const pdf = useAnexarPdf(fonte);
    pdf.comecar(SEGURO);
    return pdf;
  };

  it('guarda direto quando o PDF não diz nada diferente', async () => {
    const fonte = {
      lerPdf: vi.fn().mockResolvedValue({
        leituraId: 3,
        outraApolice: false,
        mudancas: [],
      }),
      guardarPdfLido: vi.fn().mockResolvedValue({ id: 7, temPdf: true }),
    };
    const pdf = comFonte(fonte);

    expect(await pdf.ler(ARQUIVO)).toEqual({ id: 7, temPdf: true });
    expect(fonte.guardarPdfLido).toHaveBeenCalledWith(7, 3, []);
  });

  it('mostra o que mudou só com o que o servidor escolheu, e a pessoa troca', async () => {
    const fonte = {
      lerPdf: vi.fn().mockResolvedValue({
        leituraId: 3,
        outraApolice: false,
        mudancas: [
          mudanca('termina', true),
          mudanca('valor', false, { confira: true }),
        ],
      }),
      guardarPdfLido: vi.fn().mockResolvedValue({ id: 7 }),
    };
    const pdf = comFonte(fonte);

    expect(await pdf.ler(ARQUIVO)).toBeNull();
    expect(pdf.etapa.value).toBe(ETAPAS.MUDOU);
    expect(pdf.escolhidos.value).toEqual(['termina']);

    pdf.trocarEscolha('termina');
    pdf.trocarEscolha('valor');
    await pdf.guardarLido(pdf.escolhidos.value);
    expect(fonte.guardarPdfLido).toHaveBeenCalledWith(7, 3, ['valor']);
  });

  it('falha ao guardar o que foi lido: volta ao começo com a frase, em vez de ficar lendo', async () => {
    const fonte = {
      lerPdf: vi.fn().mockResolvedValue({
        leituraId: 3,
        outraApolice: false,
        mudancas: [],
      }),
      guardarPdfLido: vi.fn().mockRejectedValue(recusa('leitura_expirou')),
    };
    const pdf = comFonte(fonte);

    expect(await pdf.ler(ARQUIVO)).toBeNull();
    expect(pdf.etapa.value).toBe(ETAPAS.SOLTAR);
    expect(pdf.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.LEITURA_EXPIROU'
    );
  });

  it('a resposta de leitura de um seguro nunca preenche a tela de outro', async () => {
    let responder;
    const fonte = {
      lerPdf: vi.fn().mockReturnValue(
        new Promise(resolve => {
          responder = resolve;
        })
      ),
      guardarPdfLido: vi.fn(),
    };
    const pdf = comFonte(fonte);

    const pendente = pdf.ler(ARQUIVO);
    pdf.comecar({ id: 8, temPdf: false });
    responder({
      leituraId: 3,
      outraApolice: false,
      mudancas: [mudanca('termina', true)],
    });

    expect(await pendente).toBeNull();
    expect(pdf.etapa.value).toBe(ETAPAS.SOLTAR);
    expect(pdf.mudancas.value).toEqual([]);
    expect(fonte.guardarPdfLido).not.toHaveBeenCalled();
  });

  it('recusa o PDF que não é apólice com a frase dele e não guarda nada', async () => {
    const fonte = {
      lerPdf: vi.fn().mockRejectedValue(recusa('nao_e_apolice')),
      guardarPdfLido: vi.fn(),
      guardarPdf: vi.fn(),
    };
    const pdf = comFonte(fonte);

    await pdf.ler(ARQUIVO);
    expect(pdf.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.NAO_E_APOLICE'
    );
    expect(pdf.naoLido.value).toBeNull();
    expect(fonte.guardarPdfLido).not.toHaveBeenCalled();
    expect(fonte.guardarPdf).not.toHaveBeenCalled();
  });

  it('o PDF que não deu para ler pode ser guardado sem leitura', async () => {
    const fonte = {
      lerPdf: vi.fn().mockRejectedValue(recusa('nao_deu_para_ler')),
      guardarPdf: vi.fn().mockResolvedValue({ id: 7, temPdf: true }),
    };
    const pdf = comFonte(fonte);

    await pdf.ler(ARQUIVO);
    expect(pdf.etapa.value).toBe(ETAPAS.SOLTAR);
    expect(pdf.naoLido.value).toBe(ARQUIVO);
    expect(await pdf.guardar(pdf.naoLido.value)).toEqual({
      id: 7,
      temPdf: true,
    });
  });
});

describe('leituraDePdf (D4)', () => {
  it('só diz sim com leituraDePdf: true no resumo', async () => {
    const resumo = valor => ({ resumo: vi.fn().mockResolvedValue(valor) });

    expect(await leituraDePdf({ fonte: resumo({ leituraDePdf: true }) })).toBe(
      true
    );
    expect(await leituraDePdf({ fonte: resumo({ total: 1, vence7: 0 }) })).toBe(
      false
    );
    expect(
      await leituraDePdf({
        fonte: { resumo: vi.fn().mockRejectedValue(new Error('rede')) },
      })
    ).toBe(false);
    expect(
      await leituraDePdf({ demo: true, fonte: resumo({ leituraDePdf: true }) })
    ).toBe(false);
  });
});

describe('useLeituraDePdfs', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('envia, espera a leitura, confere e traz', async () => {
    const lendo = { id: 9, estado: 'lendo', total: 2, lidos: 1 };
    const lida = { id: 9, estado: 'lida', total: 2, lidos: 2, seguros: 2 };
    const fonte = {
      enviar: vi.fn().mockResolvedValue({ id: 9 }),
      lote: vi.fn().mockResolvedValueOnce(lendo).mockResolvedValue(lida),
      trazer: vi.fn().mockResolvedValue({ estado: 'trazendo', porcentagem: 0 }),
      andamento: vi.fn().mockResolvedValue({
        estado: 'trazida',
        seguros: 2,
        pessoas: 1,
        pessoasNovas: 1,
      }),
    };
    const aoMudarLote = vi.fn();
    const leitura = useLeituraDePdfs(fonte, { aoMudarLote });

    await leitura.enviar([ARQUIVO, ARQUIVO]);
    expect(aoMudarLote).toHaveBeenCalledWith(9);
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.LENDO);

    await vi.advanceTimersByTimeAsync(2000);
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.CONFERIR);

    await leitura.trazer();
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.PRONTO);
    expect(leitura.andamento.value.seguros).toBe(2);
  });

  it('falha ao acompanhar a leitura: fica o erro, e "tentar de novo" retoma o mesmo lote', async () => {
    const lendo = { id: 9, estado: 'lendo', total: 2, lidos: 1 };
    const fonte = {
      lote: vi
        .fn()
        .mockResolvedValueOnce(lendo)
        .mockRejectedValueOnce(new Error('rede'))
        .mockResolvedValue({ id: 9, estado: 'lida', total: 2, lidos: 2 }),
    };
    const leitura = useLeituraDePdfs(fonte);

    await leitura.abrir(9);
    await vi.advanceTimersByTimeAsync(2000);
    expect(leitura.semAcompanhar.value).toBe(true);
    expect(leitura.erro.value).toBe('RELACIONAMENTOS_CARTEIRA.PDFS.NAO_DEU');
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.LENDO);

    await leitura.tentarDeNovo();
    expect(fonte.lote).toHaveBeenLastCalledWith(9);
    expect(leitura.semAcompanhar.value).toBe(false);
    expect(leitura.erro.value).toBe('');
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.CONFERIR);
  });

  it('no "Trazendo", a falha do acompanhamento e o lote parado pedem o Trazer de novo', async () => {
    const parada = { estado: 'trazendo', porcentagem: 40, seguros: 2 };
    const fonte = {
      lote: vi.fn().mockResolvedValue({ id: 9, estado: 'trazendo' }),
      andamento: vi
        .fn()
        .mockResolvedValueOnce(parada)
        .mockResolvedValue(parada),
      trazer: vi.fn().mockResolvedValue(parada),
    };
    const leitura = useLeituraDePdfs(fonte);

    await leitura.abrir(9);
    expect(leitura.parado.value).toBe(false);
    await vi.advanceTimersByTimeAsync(11 * 60 * 1000);
    expect(leitura.parado.value).toBe(true);

    await leitura.tentarDeNovo();
    expect(fonte.trazer).toHaveBeenCalledWith(9);
    expect(leitura.parado.value).toBe(false);

    fonte.andamento.mockRejectedValue(new Error('rede'));
    await vi.advanceTimersByTimeAsync(2000);
    expect(leitura.semAcompanhar.value).toBe(true);
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.TRAZENDO);
  });

  it('um segundo envio enquanto o primeiro corre é ignorado: nunca dois lotes', async () => {
    const fonte = {
      enviar: vi.fn().mockResolvedValue({ id: 9 }),
      lote: vi.fn().mockResolvedValue({ id: 9, estado: 'lida' }),
    };
    const leitura = useLeituraDePdfs(fonte);

    await Promise.all([leitura.enviar([ARQUIVO]), leitura.enviar([ARQUIVO])]);
    expect(fonte.enviar).toHaveBeenCalledTimes(1);
  });

  it('diz a frase da recusa quando nada está pronto para trazer', async () => {
    const fonte = {
      lote: vi.fn().mockResolvedValue({ id: 9, estado: 'lida' }),
      trazer: vi.fn().mockRejectedValue(recusa('nada_para_trazer')),
    };
    const leitura = useLeituraDePdfs(fonte);

    await leitura.abrir(9);
    await leitura.trazer();
    expect(leitura.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.NADA_PARA_TRAZER'
    );
    expect(leitura.etapa.value).toBe(ETAPAS_DOS_PDFS.CONFERIR);
  });
});

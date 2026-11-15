import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import EntradaDeFora from '../../components/carteira/EntradaDeFora.vue';
import SeloDoSeguro from '../../components/carteira/SeloDoSeguro.vue';
import PalavrasSimples from '../../components/carteira/renovacao/PalavrasSimples.vue';
import { doCampoDeData } from '../../carteira/formatosDoSeguro';
import { DO_RODAPE, rodapeDoSeguro } from '../../carteira/rodapeDoSeguro';
import {
  PASSOS_DE_FORA,
  QUER,
  useSeguroDeFora,
} from '../../carteira/useSeguroDeFora';
import { aoMeioDia, daCarteira, recusa, textoDe } from './apoio';

// #2899 (E6.5 e E6.6) — o seguro de outra corretora (ler o PDF, conferir, dizer
// se quer o lembrete, guardar e desfazer) e o seguro em palavras simples
// (escrever, alterar, mandar só no clique, copiar quando não dá para mandar),
// com o texto de verdade em pt_BR. A fonte é de mentira; nada vai ao servidor.
const { LIMITE_EM_MB } = vi.hoisted(() => ({ LIMITE_EM_MB: 40 }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { maximumFileUploadSize: LIMITE_EM_MB } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));

withFullI18n('pt_BR');

const PESSOA = 23;
const ANEXO = 31;
const LIDA = {
  leituraId: 5,
  lido: {
    tipo: 'auto',
    seguradora: 'Seguradora Exemplo',
    termina: aoMeioDia(2027, 3, 10),
    corretora: null,
  },
  tambem: [
    { campo: 'numero', valor: 'EX-000222', confira: false },
    { campo: 'valor', valor: 1250, confira: true },
  ],
};

const fonteDeFora = (mudar = {}) => ({
  usaDemo: false,
  arquivosDeFora: vi.fn().mockResolvedValue([
    {
      id: ANEXO,
      nome: 'apolice-de-outra.pdf',
      quando: aoMeioDia(2026, 11, 2),
    },
  ]),
  lerDeFora: vi.fn().mockResolvedValue(LIDA),
  guardarDeFora: vi
    .fn()
    .mockResolvedValue({ id: 70, deFora: true, lembreteAceitoEm: 1 }),
  apagarDeFora: vi.fn().mockResolvedValue(undefined),
  ...mudar,
});

describe('useSeguroDeFora', () => {
  const usar = fonte => useSeguroDeFora({ fonte, pessoaId: () => PESSOA });

  it('lê o PDF da conversa e enche o formulário; o que não foi achado fica vazio', async () => {
    const fonte = fonteDeFora();
    const seguro = usar(fonte);

    await seguro.abrir();
    expect(seguro.passo.value).toBe(PASSOS_DE_FORA.ARQUIVO);
    expect(seguro.arquivos.value).toHaveLength(1);

    await seguro.ler({ anexoId: ANEXO });

    expect(fonte.lerDeFora).toHaveBeenCalledWith(PESSOA, { anexoId: ANEXO });
    expect(seguro.passo.value).toBe(PASSOS_DE_FORA.LIDO);
    expect(seguro.formulario.value).toEqual({
      tipo: 'auto',
      seguradora: 'Seguradora Exemplo',
      termina: '2027-03-10',
      corretora: '',
    });
    expect(seguro.naoAchou.value).toEqual(['corretora']);
  });

  it('sem a resposta do lembrete não guarda; o valor a conferir só vai quando a pessoa diz que está certo', async () => {
    const fonte = fonteDeFora();
    const seguro = usar(fonte);
    await seguro.ler({ anexoId: ANEXO });

    expect(await seguro.guardar()).toBeNull();
    expect(seguro.falta.value.quer).toBe(true);
    expect(fonte.guardarDeFora).not.toHaveBeenCalled();

    seguro.responder(QUER.SIM);
    seguro.trocarConfirmado('valor');
    await seguro.guardar();

    expect(fonte.guardarDeFora).toHaveBeenCalledWith(PESSOA, {
      leituraId: 5,
      querLembrete: true,
      campos: {
        tipo: 'auto',
        seguradora: 'Seguradora Exemplo',
        termina: doCampoDeData('2027-03-10'),
        corretora: '',
      },
      confirmados: ['valor'],
    });
  });

  it('o PDF que não é apólice não oferece ler de novo; a falha da leitura oferece e diz o que fazer', async () => {
    const lerDeFora = vi
      .fn()
      .mockRejectedValueOnce(recusa('nao_e_apolice'))
      .mockRejectedValueOnce(recusa('nao_deu_para_ler'))
      .mockResolvedValueOnce(LIDA);
    const seguro = usar(fonteDeFora({ lerDeFora }));

    await seguro.ler({ anexoId: ANEXO });
    expect(seguro.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.NAO_E_APOLICE'
    );
    expect(seguro.podeTentarDeNovo.value).toBe(false);

    await seguro.ler({ anexoId: ANEXO });
    expect(seguro.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.DE_FORA.NAO_DEU_PARA_LER'
    );
    expect(seguro.podeTentarDeNovo.value).toBe(true);

    seguro.tentarDeNovo();
    await flushPromises();
    expect(lerDeFora).toHaveBeenCalledTimes(3);
    expect(seguro.passo.value).toBe(PASSOS_DE_FORA.LIDO);
  });

  it('o seguro repetido e o texto comprido demais têm frase própria', async () => {
    const guardarDeFora = vi
      .fn()
      .mockRejectedValueOnce(recusa('seguro_de_fora_repetido'))
      .mockRejectedValueOnce(recusa('texto_longo'));
    const seguro = usar(fonteDeFora({ guardarDeFora }));
    await seguro.ler({ anexoId: ANEXO });
    seguro.responder(QUER.NAO);

    await seguro.guardar();
    expect(seguro.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.SEGURO_DE_FORA_REPETIDO'
    );

    await seguro.guardar();
    expect(seguro.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.DE_FORA.TEXTO_LONGO'
    );
  });
});

describe('EntradaDeFora', () => {
  const montar = fonte =>
    mount(EntradaDeFora, {
      props: { pessoaId: PESSOA, fonte, nome: 'Marina Exemplo de Souza' },
      attachTo: document.body,
    });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('do PDF da conversa ao seguro guardado com o lembrete, e o Desfazer apaga', async () => {
    const fonte = fonteDeFora();
    const peca = montar(fonte);

    await peca.find(daCarteira('entrada-de-fora')).trigger('click');
    await flushPromises();
    expect(peca.text()).toContain('Qual é o PDF do seguro?');
    expect(document.activeElement.textContent).toContain(
      'Qual é o PDF do seguro?'
    );

    await peca.find(daCarteira('de-fora-arquivo')).trigger('click');
    await flushPromises();
    expect(peca.text()).toContain('O que eu li no PDF');
    expect(peca.text()).toContain('Marina quer o lembrete da renovação?');
    const confira = peca.find(daCarteira('esta-certo'));
    expect(confira.attributes('role')).toBe('switch');
    expect(confira.attributes('aria-checked')).toBe('false');
    expect(confira.attributes('aria-labelledby')).toBeTruthy();

    await peca.find(daCarteira('guardar-seguro-de-fora')).trigger('click');
    await flushPromises();
    expect(peca.text()).toContain('Diga se Marina quer o lembrete.');
    expect(fonte.guardarDeFora).not.toHaveBeenCalled();

    await peca.findAll('[role="radio"]')[0].trigger('click');
    await peca.find(daCarteira('guardar-seguro-de-fora')).trigger('click');
    await flushPromises();

    expect(fonte.guardarDeFora).toHaveBeenCalledWith(
      PESSOA,
      expect.objectContaining({ querLembrete: true, confirmados: [] })
    );
    expect(peca.text()).toContain(
      'Seguro de outra corretora guardado na ficha, com o lembrete da renovação.'
    );
    expect(peca.emitted('mudou')).toHaveLength(1);

    await peca.find(daCarteira('desfazer')).trigger('click');
    await flushPromises();

    expect(fonte.apagarDeFora).toHaveBeenCalledWith(70);
    expect(peca.text()).toContain('Desfeito. O seguro saiu da ficha.');
  });

  it('a lista de PDFs que falha oferece Tentar de novo', async () => {
    const arquivosDeFora = vi
      .fn()
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce([]);
    const peca = montar(fonteDeFora({ arquivosDeFora }));

    await peca.find(daCarteira('entrada-de-fora')).trigger('click');
    await flushPromises();
    const tentar = peca
      .findAll('button')
      .find(botao => botao.text() === 'Tentar de novo');
    await tentar.trigger('click');
    await flushPromises();

    expect(arquivosDeFora).toHaveBeenCalledTimes(2);
    expect(peca.text()).toContain('Qual é o PDF do seguro?');
  });
});

describe('PalavrasSimples', () => {
  const TEXTO = 'Oi, Marina!\nÉ o seguro do seu carro.';
  const VALE = 'Vale o que está escrito na sua apólice.';
  const palavrasDe = (texto, envio = 'conversa', enviadoEm = null) => ({
    texto,
    enviadoEm,
    vale: VALE,
    envio,
  });
  const fontePalavras = (mudar = {}) => ({
    palavras: vi.fn().mockResolvedValue(palavrasDe(null)),
    escreverPalavras: vi.fn().mockResolvedValue(palavrasDe(TEXTO)),
    salvarPalavras: vi
      .fn()
      .mockImplementation((_id, texto) => Promise.resolve(palavrasDe(texto))),
    enviarPalavras: vi
      .fn()
      .mockResolvedValue(
        palavrasDe(TEXTO, 'conversa', aoMeioDia(2026, 11, 15))
      ),
    ...mudar,
  });
  const montar = fonte =>
    mount(PalavrasSimples, {
      props: { seguroId: 7, fonte, nome: 'Marina' },
      attachTo: document.body,
    });

  afterEach(() => {
    document.body.innerHTML = '';
    vi.clearAllMocks();
  });

  it('escreve só no clique, mostra o texto com a frase do fim e manda só no clique de Enviar', async () => {
    const fonte = fontePalavras();
    const peca = montar(fonte);
    await flushPromises();

    expect(fonte.escreverPalavras).not.toHaveBeenCalled();
    expect(fonte.enviarPalavras).not.toHaveBeenCalled();
    expect(textoDe(peca, daCarteira('escrever-palavras'))).toBe(
      'Escrever para Marina'
    );

    await peca.find(daCarteira('escrever-palavras')).trigger('click');
    await flushPromises();
    expect(textoDe(peca, daCarteira('previa-das-palavras'))).toBe(
      `${TEXTO}\n\n${VALE}`
    );
    expect(fonte.enviarPalavras).not.toHaveBeenCalled();

    await peca.find(daCarteira('enviar-palavras')).trigger('click');
    await flushPromises();
    expect(fonte.enviarPalavras).toHaveBeenCalledWith(7);
    expect(peca.emitted('mudou')).toHaveLength(1);
    expect(peca.find(daCarteira('palavras-enviadas')).exists()).toBe(true);
  });

  it('alterar guarda o texto da pessoa; vazio não sai da tela', async () => {
    const fonte = fontePalavras({
      palavras: vi.fn().mockResolvedValue(palavrasDe(TEXTO)),
    });
    const peca = montar(fonte);
    await flushPromises();

    await peca.find(daCarteira('alterar-palavras')).trigger('click');
    await peca.find('textarea').setValue('   ');
    await peca.find(daCarteira('salvar-palavras')).trigger('click');
    await flushPromises();
    expect(peca.text()).toContain('Escreva o texto antes de salvar.');
    expect(fonte.salvarPalavras).not.toHaveBeenCalled();

    await peca.find('textarea').setValue('Oi, Marina!\nTexto ajustado.');
    await peca.find(daCarteira('salvar-palavras')).trigger('click');
    await flushPromises();
    expect(fonte.salvarPalavras).toHaveBeenCalledWith(
      7,
      'Oi, Marina!\nTexto ajustado.'
    );
    expect(textoDe(peca, daCarteira('previa-das-palavras'))).toContain(
      'Texto ajustado.'
    );
  });

  it('sem conversa não há botão de enviar desligado: diz por quê e oferece copiar', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    const fonte = fontePalavras({
      palavras: vi.fn().mockResolvedValue(palavrasDe(TEXTO, 'sem_conversa')),
    });
    const peca = montar(fonte);
    await flushPromises();

    expect(peca.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    expect(textoDe(peca, daCarteira('palavras-sem-envio'))).toContain(
      'Marina não tem conversa aqui.'
    );

    await peca.find(daCarteira('copiar-palavras')).trigger('click');
    await flushPromises();
    expect(writeText).toHaveBeenCalledWith(`${TEXTO}\n\n${VALE}`);
    expect(useAlert).toHaveBeenCalledWith('Texto copiado.');
  });

  it('a conversa que fechou entre abrir e enviar passa a oferecer copiar', async () => {
    const fonte = fontePalavras({
      palavras: vi.fn().mockResolvedValue(palavrasDe(TEXTO)),
      enviarPalavras: vi.fn().mockRejectedValue(recusa('fora_da_janela')),
    });
    const peca = montar(fonte);
    await flushPromises();

    await peca.find(daCarteira('enviar-palavras')).trigger('click');
    await flushPromises();

    expect(peca.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    expect(peca.find(daCarteira('copiar-palavras')).exists()).toBe(true);
    expect(textoDe(peca, daCarteira('erro-das-palavras'))).toContain(
      'Copie o texto e mande por outro caminho.'
    );
    expect(peca.emitted('mudou')).toBeUndefined();
  });

  it('escrever que falha vira Tentar de novo', async () => {
    const fonte = fontePalavras({
      escreverPalavras: vi
        .fn()
        .mockRejectedValue(recusa('nao_deu_para_escrever')),
    });
    const peca = montar(fonte);
    await flushPromises();

    await peca.find(daCarteira('escrever-palavras')).trigger('click');
    await flushPromises();

    expect(textoDe(peca, daCarteira('erro-das-palavras'))).toBe(
      'Não consegui escrever o texto agora. Tente de novo.'
    );
    expect(textoDe(peca, daCarteira('escrever-palavras'))).toBe(
      'Tentar de novo'
    );
  });
});

describe('o seguro de outra corretora no selo e no rodapé', () => {
  const SEGURO = {
    id: 9,
    tipo: 'auto',
    seguradora: 'Seguradora Exemplo',
    termina: aoMeioDia(2027, 3, 10),
    selo: 'ativo',
    dias: 115,
    temPdf: true,
    canceladoEm: null,
  };

  it('ganha o selo "De outra corretora" ao lado do selo de sempre', () => {
    const comSelo = mount(SeloDoSeguro, {
      props: { seguro: { ...SEGURO, deFora: true } },
    });
    const semSelo = mount(SeloDoSeguro, {
      props: { seguro: { ...SEGURO, deFora: false } },
    });

    expect(textoDe(comSelo, daCarteira('selo-de-fora'))).toBe(
      'De outra corretora'
    );
    expect(semSelo.find(daCarteira('selo-de-fora')).exists()).toBe(false);
  });

  it('no fim do "⋯" o seguro de fora se apaga; o da carteira se cancela', () => {
    const agora = aoMeioDia(2026, 11, 15) * 1000;
    const deFora = rodapeDoSeguro({ ...SEGURO, deFora: true }, { agora });
    const daCorretora = rodapeDoSeguro({ ...SEGURO, deFora: false }, { agora });

    expect(deFora.menu.at(-1)).toBe(DO_RODAPE.APAGAR_DE_FORA);
    expect(deFora.menu).not.toContain(DO_RODAPE.MARCAR_CANCELADO);
    expect(daCorretora.menu.at(-1)).toBe(DO_RODAPE.MARCAR_CANCELADO);
  });
});

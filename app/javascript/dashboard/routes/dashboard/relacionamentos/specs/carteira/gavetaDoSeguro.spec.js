import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import { baixarArquivo } from '../../carteira/exportarHistoria';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { pessoaPorId } from '../../demo/base';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import {
  esquecerAjustesDaDemo,
  salvarAjustesNaDemo,
} from '../../demo/carteiraAjustes';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  textoDe,
} from './apoio';

// A gaveta do seguro (#2897, telas 4 e 15) com a carteira fictícia e o texto de
// verdade em pt_BR: a frase e o próximo passo de cada situação, marcar como
// cancelado com desfazer, a história, e carregando, erro e "não está mais aqui".
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('../../carteira/exportarHistoria', async importOriginal => ({
  ...(await importOriginal()),
  baixarArquivo: vi.fn(),
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const EM_RENOVACAO = 1;
const ATIVO_COM_ENDOSSO = 2;
const RENOVADO = 102;
const VENCIDO = 103;
const CANCELADO = 101;
const PARCELA_ATRASADA = 108;
const APOLICE_NOVA = 109;
const PESSOA_DA_APOLICE_NOVA = 48;
const NAO_EXISTE = 9999;

const fonteDaDemo = (opcoes = {}) =>
  carteiraFonte({ demo: 'cheio', atraso: 0, ...opcoes });

let aberta;
const abrir = async (apoliceId, fonte = fonteDaDemo()) => {
  aberta = mount(GavetaDoSeguro, {
    attachTo: document.body,
    props: { apoliceId, fonte },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const acao = w => w.get(daCarteira('gaveta-acao'));
const abrirMenu = async w => {
  await w.get(`${daCarteira('mais-do-seguro')} button`).trigger('click');
};

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  esquecerAjustesDaDemo();
  vi.clearAllMocks();
});

describe('gaveta do seguro: uma frase e um próximo passo por situação', () => {
  it('em renovação: diz quando vence, o que já foi feito e o que falta', async () => {
    const w = await abrir(EM_RENOVACAO);

    expect(textoDe(w, '[data-view-title]')).toBe('Auto · Seguradora Atlântica');
    const frase = textoDe(w, daCarteira('frase-do-seguro'));
    expect(frase).toContain('Vence em 18 dias.');
    expect(frase).toContain('As opções já foram enviadas. Falta a resposta.');
    // Nada de nome de mecanismo na frase de gente.
    expect(frase).not.toContain('Opções enviadas');
    expect(textoDe(w, daCarteira('situacao-da-renovacao'))).toBe(
      'As opções já foram enviadas. Falta a resposta.'
    );
    expect(textoDe(w, daCarteira('quem-cuida'))).toBe(
      'Quem cuida: Bia Lunardelli'
    );
    expect(textoDe(w, daCarteira('renovacao'))).not.toContain('Funil');
    expect(acao(w).text()).toBe('Abrir a renovação');
    expect(w.findAll(daCarteira('gaveta-acao'))).toHaveLength(1);
    // No rodapé, o "⋯" tem a altura dos vizinhos.
    ['gaveta-acao', 'corrigir', 'mais-do-seguro'].forEach(marca => {
      const botao = w.get(daCarteira(marca));
      const gatilho = botao.element.matches('button')
        ? botao
        : botao.get('button');
      expect(gatilho.classes()).toContain('h-12');
    });
    // O número da apólice não quebra no hífen.
    const numero = w.get(
      `[data-dado="numero"] ${daCarteira('numero-da-apolice')}`
    );
    expect(numero.text()).toBe('AT-000451');
    expect(numero.classes()).toContain('whitespace-nowrap');

    // "Abrir a renovação" passa a vez à gaveta da renovação deste seguro.
    await acao(w).trigger('click');
    expect(w.emitted('abrirRenovacao')).toEqual([[EM_RENOVACAO]]);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('o foco vai ao título da gaveta que já nasce aberta', async () => {
    const w = await abrir(EM_RENOVACAO);
    expect(document.activeElement).toBe(w.get('[data-view-title]').element);
  });

  it('ativo com PDF: o passo é ver o PDF, e o endosso aparece na história', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);

    expect(acao(w).text()).toBe('Ver PDF');
    expect(w.find(daCarteira('renovacao')).exists()).toBe(false);
    expect(textoDe(w, '[data-passo="endosso"]')).toContain(
      'Endosso · Valor do seguro: R$ 610,00 → R$ 640,00'
    );
  });

  it('renovado: falta a apólice nova, e o valor avisa que pode ter mudado', async () => {
    const w = await abrir(RENOVADO);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain(
      'Falta a apólice nova.'
    );
    expect(acao(w).text()).toBe('Anexar a apólice nova');
    expect(w.get('[data-dado="valor"]').get(daCarteira('confira')).text()).toBe(
      'Pode ter mudado'
    );
  });

  it('vencido: diz há quanto tempo e o motivo, e chama para conversar', async () => {
    const w = await abrir(VENCIDO);

    const frase = textoDe(w, daCarteira('frase-do-seguro'));
    expect(frase).toContain('Venceu há 12 dias e não foi renovado.');
    expect(frase).toContain('Motivo: achou caro.');
    expect(acao(w).text()).toMatch('Conversar com ');
  });

  it('parcela atrasada: avisar passa pela conferência; depois de enviar, o aviso e a história', async () => {
    const w = await abrir(PARCELA_ATRASADA);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain(
      'está em aberto. Avise antes que o seguro seja cancelado.'
    );
    expect(acao(w).text()).toBe('Avisar Karina');
    expect(w.find(`${daCarteira('avisar-parcela')} button`).element).toBe(
      acao(w).element
    );

    // A mensagem aparece como chega no WhatsApp: nada sai antes do "Enviar".
    await acao(w).trigger('click');
    const previa = w.get(daCarteira('previa-envio'));
    expect(previa.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Avisar Karina da parcela'
    );
    expect(previa.text()).toContain(
      'É assim que a mensagem chega no WhatsApp.'
    );
    const bolha = textoDe(w, daCarteira('previa-de-mensagem'));
    expect(bolha).toMatch('Oi, Karina! A parcela de ');
    expect(bolha).toContain(
      ' do seu seguro Auto está em aberto. Quer que eu te mande o boleto de novo?'
    );
    expect(
      w.findAll('[data-dialogo-falso] button').map(botao => botao.text())
    ).toEqual(['Voltar', 'Enviar']);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toBe('');
    expect(w.find('[data-passo="parcela_avisada"]').exists()).toBe(false);

    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentar();

    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    const aviso = w.get(daCarteira('aviso-vivo'));
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('Mensagem enviada a Karina.');
    expect(w.emitted('mudou')).toHaveLength(1);
    expect(textoDe(w, '[data-passo="parcela_avisada"]')).toContain(
      'Aviso da parcela enviado. · Você'
    );
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('parcela atrasada: "Voltar" fecha a conferência e nada sai', async () => {
    const w = await abrir(PARCELA_ATRASADA);

    await acao(w).trigger('click');
    await w.get('[data-dialogo-falso] button').trigger('click');
    await assentar();

    expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toBe('');
    expect(w.emitted('mudou')).toBeUndefined();
  });

  it.each([
    [{ phone_number: null }, 'Karina está sem telefone. A mensagem não chega.'],
    [
      { opted_out_at: 1 },
      'Karina pediu para não receber mensagens. Avise na conversa.',
    ],
    [
      { blocked: true },
      'Alguém da equipe bloqueou Karina. A mensagem não sai.',
    ],
  ])(
    'parcela atrasada, pessoa %j: o clique diz por que não dá e não abre a conferência',
    async (daPessoa, frase) => {
      const fonte = fonteDaDemo();
      const w = await abrir(PARCELA_ATRASADA, {
        ...fonte,
        seguro: async id => {
          const seguro = await fonte.seguro(id);
          return { ...seguro, pessoa: { ...seguro.pessoa, ...daPessoa } };
        },
      });
      expect(acao(w).attributes('disabled')).toBeUndefined();

      await acao(w).trigger('click');

      const alerta = w.get(daCarteira('alerta-da-gaveta'));
      expect(alerta.attributes('role')).toBe('alert');
      expect(alerta.text()).toBe(frase);
      expect(acao(w).attributes('aria-describedby')).toBe(
        alerta.attributes('id')
      );
      expect(w.find(daCarteira('previa-envio')).exists()).toBe(false);
      expect(w.emitted('mudou')).toBeUndefined();
    }
  );

  it('cancelado: o menu oferece voltar a ativo, não cancelar de novo', async () => {
    const w = await abrir(CANCELADO);

    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Cancelado em');
    await abrirMenu(w);
    expect(w.find(daCarteira('voltar-a-ativo')).exists()).toBe(true);
    expect(w.find(daCarteira('marcar-cancelado')).exists()).toBe(false);
  });
});

describe('gaveta do seguro: marcar como cancelado', () => {
  it('cancela sem perguntar de novo, avisa e deixa desfazer', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);

    await abrirMenu(w);
    await w.get(daCarteira('marcar-cancelado')).trigger('click');
    await assentar();

    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain(
      'Seguro marcado como cancelado.'
    );
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Cancelado em');
    expect(w.emitted('mudou')).toHaveLength(1);

    await w.get(daCarteira('desfazer')).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Desfeito.');
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('frase-do-seguro'))).toContain('Vale até');
    expect(w.emitted('mudou')).toHaveLength(2);
  });

  it('a região do aviso já está na gaveta antes de haver aviso', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);
    const aviso = w.get(daCarteira('aviso-vivo'));
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('');
  });

  it('quando a fonte falha, diz que não conseguiu e não oferece desfazer', async () => {
    const fonte = fonteDaDemo();
    const w = await abrir(ATIVO_COM_ENDOSSO, {
      ...fonte,
      cancelar: () => Promise.reject(new Error('fora do ar')),
    });

    await abrirMenu(w);
    await w.get(daCarteira('marcar-cancelado')).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain(
      'Não consegui fazer isso. Tente de novo.'
    );
    expect(w.find(daCarteira('desfazer')).exists()).toBe(false);
    expect(w.emitted('mudou')).toBeUndefined();
  });
});

describe('gaveta do seguro: a história', () => {
  it('conta a renovação inteira, do mais novo ao mais antigo', async () => {
    const w = await abrir(EM_RENOVACAO);

    const passos = w
      .findAll(daCarteira('item-da-historia'))
      .map(item => item.attributes('data-passo'));
    expect(passos).toEqual([
      'cliente_respondeu',
      'proposta_enviada',
      'proposta_pronta',
      'respondeu_algo_mudou',
      'card_nasceu',
      'chegou_agger',
    ]);
    expect(textoDe(w, '[data-passo="proposta_pronta"]')).toContain(
      'Proposta pronta: Seguradora Atlântica, R$ 2.980,80 por ano. · Subiu 8%. · Robô de renovação'
    );
    expect(textoDe(w, '[data-passo="proposta_enviada"]')).toContain(
      'Proposta enviada · Bia Lunardelli'
    );
  });

  it('"Ver resumo" (o que saiu foi o resumo) e "Exportar" funcionam e dizem o que fizeram', async () => {
    const w = await abrir(EM_RENOVACAO);

    // O que saiu não foi a proposta oficial: o link diz "Ver resumo".
    expect(w.get(daCarteira('ver-proposta')).text()).toBe('Ver resumo');
    await w.get(daCarteira('ver-proposta')).trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Abrindo o resumo da cotação');

    await w.get(daCarteira('exportar')).trigger('click');
    const [nome, conteudo] = baixarArquivo.mock.calls[0];
    expect(nome).toBe('historia-AT-000451.csv');
    expect(conteudo).toContain('"Data";"Hora";"O que aconteceu";"Quem fez"');
    expect(conteudo).toContain('Chegou do Agger.');
    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Arquivo baixado.');
  });

  it('se só a história falhar, o resto do seguro continua na tela', async () => {
    const fonte = fonteDaDemo();
    const falhas = { vezes: 1 };
    const w = await abrir(EM_RENOVACAO, {
      ...fonte,
      historia: id => {
        if (falhas.vezes === 0) return fonte.historia(id);
        falhas.vezes -= 1;
        return Promise.reject(new Error('fora do ar'));
      },
    });

    expect(w.find(daCarteira('historia-erro')).exists()).toBe(true);
    expect(w.find(daCarteira('exportar')).exists()).toBe(false);
    expect(acao(w).text()).toBe('Abrir a renovação');

    await w.get(`${daCarteira('historia-erro')} button`).trigger('click');
    await assentar();
    expect(w.findAll(daCarteira('item-da-historia'))).toHaveLength(6);
  });
});

describe('gaveta do seguro: carregando, erro e seguro que sumiu', () => {
  it('carregando: o esqueleto, sem botão no rodapé', async () => {
    const w = await abrir(EM_RENOVACAO, fonteDaDemo({ peca: 'carregando' }));

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
  });

  it('erro: a frase e "Tentar de novo" dentro da gaveta', async () => {
    const w = await abrir(EM_RENOVACAO, fonteDaDemo({ peca: 'erro' }));

    const erro = w.get(`${daCarteira('gaveta-seguro')} ${doBlocoA('erro')}`);
    expect(erro.text()).toContain(
      'Não consegui abrir este seguro. Tente de novo.'
    );
    expect(w.find(daCarteira('gaveta-acao')).exists()).toBe(false);
  });

  it('seguro que não existe mais: diz isso e volta para a lista', async () => {
    const w = await abrir(NAO_EXISTE);

    const vazio = w.get(daCarteira('seguro-nao-esta'));
    expect(vazio.text()).toContain('Este seguro não está mais aqui.');
    await vazio.get('button').trigger('click');
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('Esc fecha a gaveta', async () => {
    const w = await abrir(EM_RENOVACAO);
    await w.get('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('sem seguro pedido, a gaveta não existe', async () => {
    const w = await abrir(null);
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });
});

describe('gaveta do seguro: o que ia sair sozinho e não saiu fica na história', () => {
  const NAO_SAIU = 'O WhatsApp não deixou sair agora. A equipe foi avisada.';
  const SEM_PROPOSTA = 111;
  const linha = (w, tipo) => textoDe(w, `[data-passo="${tipo}"]`);

  it.each([
    [
      'aviso_nao_saiu',
      SEM_PROPOSTA,
      'aviso_nao_saiu',
      `O aviso de 7 dias não saiu. ${NAO_SAIU}`,
    ],
    [
      'algo_mudou_nao_saiu',
      SEM_PROPOSTA,
      'algo_mudou_nao_saiu',
      `A pergunta “Algo mudou?” não saiu. ${NAO_SAIU}`,
    ],
    [
      'palavras_nao_saiu',
      APOLICE_NOVA,
      'palavras_nao_saiu',
      `“Seu seguro em palavras simples” não saiu. ${NAO_SAIU}`,
    ],
    [
      'proposta_nao_saiu',
      112,
      'proposta_nao_saiu',
      `A proposta não saiu. ${NAO_SAIU}`,
    ],
  ])(
    '%s: a linha diz o que não saiu e por quê',
    async (caso, id, tipo, frase) => {
      const w = await abrir(id, fonteDaDemo({ caso }));

      expect(linha(w, tipo)).toContain(frase);
      // Sem o caso, a linha não existe.
      aberta.unmount();
      const semCaso = await abrir(id);
      expect(semCaso.find(`[data-passo="${tipo}"]`).exists()).toBe(false);
    }
  );

  it('o aviso que não saiu é o mais recente que já devia ter saído (30, 15 ou 7 dias)', async () => {
    // O seguro 1 vence em 18 dias: o aviso que já devia ter saído é o de 30.
    const w = await abrir(
      EM_RENOVACAO,
      fonteDaDemo({ caso: 'aviso_nao_saiu' })
    );

    expect(linha(w, 'aviso_nao_saiu')).toContain(
      'O aviso de 30 dias não saiu.'
    );
  });
});

describe('gaveta do seguro: seu seguro em palavras simples', () => {
  const palavras = w => w.get(daCarteira('palavras-simples'));

  it('só a apólice nova tem o texto', async () => {
    const w = await abrir(ATIVO_COM_ENDOSSO);

    expect(w.find(daCarteira('palavras-simples')).exists()).toBe(false);
  });

  it('mostra o texto como a pessoa vai ler e envia com um botão que diz o nome', async () => {
    const w = await abrir(APOLICE_NOVA);
    const primeiroNome = pessoaPorId(PESSOA_DA_APOLICE_NOVA).name.split(' ')[0];

    expect(palavras(w).get('h3').text()).toBe('Seu seguro em palavras simples');
    const previa = textoDe(w, daCarteira('previa-de-mensagem'));
    expect(previa).toContain(
      `Oi, ${primeiroNome}! Seu seguro Auto com a Seguradora Atlântica começou em `
    );
    expect(previa).toContain(
      'O que ele cobre: batida, roubo e furto, vidros e guincho.'
    );
    expect(previa).toContain(
      'Se acontecer alguma coisa: me chame aqui no WhatsApp. Eu te digo o que fazer.'
    );
    expect(previa).toContain('Vale o que está escrito na sua apólice.');
    expect(w.get(daCarteira('enviar-palavras')).text()).toBe(
      `Enviar a ${primeiroNome}`
    );

    await w.get(daCarteira('enviar-palavras')).trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Texto enviado a ');
    expect(textoDe(w, daCarteira('palavras-enviado'))).toContain('Enviado em ');
    expect(w.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    // O que foi enviado fica guardado, e abre quando se pede.
    const ver = w.get(daCarteira('ver-palavras-enviadas'));
    expect(ver.text()).toBe('Ver o que foi enviado');
    expect(ver.attributes('aria-expanded')).toBe('false');
    expect(w.find(daCarteira('previa-de-mensagem')).exists()).toBe(false);
    await ver.trigger('click');
    expect(ver.attributes('aria-expanded')).toBe('true');
    expect(textoDe(w, daCarteira('previa-de-mensagem'))).toContain(
      'Vale o que está escrito na sua apólice.'
    );
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('alterar o texto: Salvar fica sempre ligado e diz o que falta; a última frase não se altera', async () => {
    const w = await abrir(APOLICE_NOVA);

    await w.get(daCarteira('alterar-palavras')).trigger('click');
    await assentar();
    const campo = w.get(`${daCarteira('texto-das-palavras')} textarea`);
    expect(document.activeElement).toBe(campo.element);
    expect(campo.element.value).toContain('O que ele cobre: batida');
    expect(campo.element.value).not.toContain('Vale o que está escrito');
    const salvar = w.get(daCarteira('salvar-palavras'));
    expect(salvar.attributes('disabled')).toBeUndefined();

    await campo.setValue('   ');
    await salvar.trigger('click');
    expect(palavras(w).get('[role="alert"]').text()).toBe(
      'Escreva o texto da mensagem.'
    );
    expect(w.getComponent(TextArea).props('messageType')).toBe('error');
    expect(document.activeElement).toBe(campo.element);

    await campo.setValue('Seu carro está coberto. Qualquer coisa, me chame.');
    await salvar.trigger('click');
    await assentar();

    expect(textoDe(w, daCarteira('aviso-vivo'))).toContain('Texto salvo.');
    const previa = textoDe(w, daCarteira('previa-de-mensagem'));
    expect(previa).toContain(
      'Seu carro está coberto. Qualquer coisa, me chame.'
    );
    expect(previa).toContain('Vale o que está escrito na sua apólice.');
    expect(previa).not.toContain('O que ele cobre');
  });

  it('o texto que se altera e o texto mostrado como enviado são o mesmo', async () => {
    const w = await abrir(APOLICE_NOVA);

    await w.get(daCarteira('alterar-palavras')).trigger('click');
    await assentar();
    const campo = w.get(`${daCarteira('texto-das-palavras')} textarea`);
    const oQueSeAltera = campo.element.value;

    // Apagar e desistir ("Voltar") não muda o texto: ao alterar de novo, ele
    // está lá como antes.
    await campo.setValue('   ');
    await w.get(daCarteira('voltar-das-palavras')).trigger('click');
    await w.get(daCarteira('alterar-palavras')).trigger('click');
    await assentar();
    expect(
      w.get(`${daCarteira('texto-das-palavras')} textarea`).element.value
    ).toBe(oQueSeAltera);

    await w.get(daCarteira('salvar-palavras')).trigger('click');
    await assentar();
    await w.get(daCarteira('enviar-palavras')).trigger('click');
    await assentar();
    await w.get(daCarteira('ver-palavras-enviadas')).trigger('click');

    expect(w.get(`${daCarteira('previa-de-mensagem')} p`).text()).toBe(
      `${oQueSeAltera}\nVale o que está escrito na sua apólice.`
    );
  });

  it('alterar o texto: o campo abre do tamanho do texto e cresce ao digitar, sem rolagem interna', async () => {
    // O jsdom não mede altura: o teste diz quanto o texto ocupa.
    let alturaDoTexto = 240;
    const medida = vi
      .spyOn(HTMLTextAreaElement.prototype, 'scrollHeight', 'get')
      .mockImplementation(() => alturaDoTexto);
    const w = await abrir(APOLICE_NOVA);

    await w.get(daCarteira('alterar-palavras')).trigger('click');
    await assentar();
    const campo = w.get(`${daCarteira('texto-das-palavras')} textarea`);
    expect(campo.element.style.height).toBe('240px');
    // Sem teto de altura: nada fica escondido atrás de uma rolagem do campo.
    expect(campo.element.style.maxHeight).toBe('none');

    alturaDoTexto = 320;
    await campo.setValue(`${campo.element.value}\nMais uma linha.`);
    await assentar();
    expect(campo.element.style.height).toBe('320px');
    medida.mockRestore();
  });

  it('enquanto lê a apólice e quando não consegue escrever, diz isso no lugar do texto', async () => {
    const lendo = await abrir(
      APOLICE_NOVA,
      fonteDaDemo({ caso: 'palavras_lendo' })
    );
    expect(lendo.get(daCarteira('palavras-lendo')).text()).toBe(
      'Lendo a apólice para escrever…'
    );
    expect(lendo.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    lendo.unmount();

    const erro = await abrir(
      APOLICE_NOVA,
      fonteDaDemo({ caso: 'palavras_erro' })
    );
    const aviso = erro.get(daCarteira('palavras-erro'));
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toContain(
      'Não consegui escrever o texto. Tente de novo.'
    );
    expect(aviso.get('button').text()).toBe('Tentar de novo');
  });

  it('o texto que ia sair sozinho e não saiu: o bloco diz por quê e chama para conversar', async () => {
    const w = await abrir(
      APOLICE_NOVA,
      fonteDaDemo({ caso: 'palavras_nao_saiu' })
    );

    expect(textoDe(w, daCarteira('palavras-nao-saiu'))).toBe(
      'O WhatsApp não deixou sair agora. A equipe foi avisada.'
    );
    expect(w.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    const conversar = w.get(daCarteira('conversar-sobre-as-palavras'));
    expect(conversar.text()).toBe('Conversar');
    await conversar.trigger('click');
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining(pessoaPorId(PESSOA_DA_APOLICE_NOVA).name)
    );
    aberta.unmount();

    // O que já foi enviado continua dito como enviado.
    salvarAjustesNaDemo({ palavras: 'sozinho' });
    const enviado = await abrir(
      APOLICE_NOVA,
      fonteDaDemo({ caso: 'palavras_nao_saiu' })
    );
    expect(enviado.find(daCarteira('palavras-nao-saiu')).exists()).toBe(false);
    expect(enviado.find(daCarteira('palavras-enviado')).exists()).toBe(true);
  });

  it('quem escolheu que sai sozinho só vê que já foi; quem escolheu não mandar não vê nada', async () => {
    salvarAjustesNaDemo({ palavras: 'sozinho' });
    const sozinho = await abrir(APOLICE_NOVA);
    expect(textoDe(sozinho, daCarteira('palavras-enviado'))).toContain(
      'Enviado sozinho em '
    );
    expect(sozinho.find(daCarteira('enviar-palavras')).exists()).toBe(false);
    expect(sozinho.find(daCarteira('ver-palavras-enviadas')).exists()).toBe(
      true
    );
    sozinho.unmount();

    salvarAjustesNaDemo({ palavras: 'nao_mandar' });
    const semTexto = await abrir(APOLICE_NOVA);
    expect(semTexto.find(daCarteira('palavras-simples')).exists()).toBe(false);
  });
});

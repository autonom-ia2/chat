import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import { daCarteira, doBlocoA, textoDe } from './apoio';
import {
  abrirTrazer,
  assentarBem,
  carregarDemonstracaoDeTrazer,
  clicar,
  contador,
  emFoco,
  fecharTrazer,
  ligarRelogio,
  passar,
  passarPelasRenovacoes,
  problema,
} from './apoioDeTrazer';

// "Trazer" na conta de seguros (#2897): a escolha de como trazer (Tela 8) e a
// planilha com seguros (Tela 9), pela página de verdade, com o texto em pt_BR.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relacionamentos_trazer' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query && !destino.name) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
// As fontes de demonstração sem as esperas de rede.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    trazerFonte: opcoes =>
      real.trazerFonte({ ...opcoes, atraso: 0, atrasoDaLeitura: 0 }),
  };
});
vi.mock('../../fonte/trazerSegurosFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    trazerSegurosFonte: opcoes =>
      real.trazerSegurosFonte({ ...opcoes, atraso: 0 }),
  };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();
const abrir = query => abrirTrazer(rota, query);

// O título e a linha de apoio de um cartão de "como trazer".
const doCartao = (w, como) =>
  w
    .findAll(`${daCarteira(`cartao-${como}`)} [data-texto-do-cartao] > span`)
    .map(parte => parte.text());

const TITULO_DA_ESCOLHA = 'Como você quer trazer as pessoas e os seguros?';
const DURACAO_DE_TRAZER_MS = 8000;

// Da escolha até a conferência da planilha de exemplo.
const irAteConferir = async query => {
  const w = await abrir({ como: 'planilha', ...query });
  await w.get(doBlocoA('usar-exemplo')).trigger('click');
  await assentarBem();
  await clicar(w, 'tem-seguros');
  await passarPelasRenovacoes(w);
  return w;
};

beforeAll(carregarDemonstracaoDeTrazer, 60000);
beforeEach(ligarRelogio);
afterEach(() => {
  fecharTrazer();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe('Tela 8: como você quer trazer?', () => {
  it('na conta de seguros a entrada é a escolha: três cartões, cada um com o seu ícone, e mais nada para apertar', async () => {
    const w = await abrir();

    expect(w.get('h1').text()).toBe(TITULO_DA_ESCOLHA);
    expect(doCartao(w, 'planilha')).toEqual([
      'Planilha',
      'Excel ou CSV, com os seguros ou só as pessoas.',
    ]);
    expect(doCartao(w, 'pdfs')).toEqual([
      'PDFs das apólices',
      'Arraste os PDFs. Eu leio cada um.',
    ]);
    expect(doCartao(w, 'agger')).toEqual([
      'Agger',
      'Para quem usa o Agger: traga direto e mantenha em dia sozinho.',
    ]);
    // Cada cartão é um botão de verdade (Enter e Espaço são do navegador), com
    // um ícone próprio que o leitor de tela não lê.
    const icones = ['planilha', 'pdfs', 'agger'].map(como => {
      const cartao = w.get(daCarteira(`cartao-${como}`));
      expect(cartao.element.tagName).toBe('BUTTON');
      expect(cartao.attributes('type')).toBe('button');
      expect(cartao.attributes('role')).toBeUndefined();
      const icone = cartao.get('[data-icone]');
      expect(icone.attributes('aria-hidden')).toBe('true');
      return icone.attributes('data-icone');
    });
    expect(icones).toEqual(['planilha', 'pdfs', 'agger']);
    expect(
      w.get(daCarteira('cartoes-de-como')).attributes('aria-labelledby')
    ).toBe(w.get('h1').attributes('id'));
    // Clicar no cartão já avança: não há "Continuar" nem aviso de escolha.
    expect(w.find(daCarteira('continuar-como')).exists()).toBe(false);
    expect(w.find(daCarteira('falta-escolher')).exists()).toBe(false);
    // As etapas do topo e a área de soltar só vêm depois da escolha.
    expect(w.find('ol').exists()).toBe(false);
    expect(w.find(doBlocoA('soltar-arquivo')).exists()).toBe(false);
    expect(w.get(`${doBlocoA('historico')} h2`).text()).toBe(
      'O que você já trouxe'
    );
  });

  it('clicar no cartão já avança: a escolha vai para o endereço e abre o passo daquele jeito', async () => {
    const w = await abrir();

    await clicar(w, 'cartao-planilha');

    expect(roteador.push).toHaveBeenCalledWith({
      query: { demo: 'sem-seguros', como: 'planilha' },
    });
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(w.get(doBlocoA('soltar-arquivo')).text()).toContain(
      'Se tiver os seguros, melhor.'
    );
    expect(emFoco()).toBe(w.get('h1').element);

    await clicar(w, 'voltar-a-escolha');
    expect(w.get('h1').text()).toBe(TITULO_DA_ESCOLHA);
  });

  it('na conta cheia o Agger já está ligado e o histórico mostra o que veio dele', async () => {
    const w = await abrir({ demo: 'cheio' });

    expect(doCartao(w, 'agger')).toEqual([
      'Agger',
      'Sua conta já está ligada ao Agger.',
    ]);
    const doAgger = w.get('[data-lista="seguros-do-agger"]');
    expect(doAgger.text()).toContain('Agger');
    expect(doAgger.text()).toContain('156 seguros');
    expect(textoDe(w, daCarteira('agger-historico'))).toBe(
      'busca todo dia · última hoje, 06:10 · 2 seguros novos'
    );
    const daPlanilha = w.get('[data-lista="seguros-da-planilha"]');
    expect(daPlanilha.text()).toContain('Carteira 2026.xlsx');
    expect(daPlanilha.text()).toContain('12 seguros');
    // As listas de pessoas do bloco A continuam no mesmo histórico.
    expect(w.get('[data-lista="trazida-antiga-1"]').text()).toContain(
      '132 pessoas'
    );
  });

  it('carregando mostra o esqueleto; erro, a frase e Tentar de novo', async () => {
    const carregando = await abrir({ 'demo-carteira': 'carregando' });
    expect(carregando.find(daCarteira('carregando')).exists()).toBe(true);
    expect(carregando.find(daCarteira('continuar-como')).exists()).toBe(false);
    fecharTrazer();

    const comErro = await abrir({ 'demo-carteira': 'erro' });
    expect(comErro.get(daCarteira('erro')).text()).toContain(
      'Não consegui abrir. Tente de novo.'
    );
    expect(comErro.get(`${daCarteira('erro')} button`).text()).toBe(
      'Tentar de novo'
    );
  });

  it('conta de outro segmento: "Trazer minha lista" de sempre, sem a escolha', async () => {
    const w = await abrir({ demo: 'fora-do-segmento' });

    expect(w.find(daCarteira('como-trazer')).exists()).toBe(false);
    expect(w.find(daCarteira('trazer')).exists()).toBe(false);
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(w.find(doBlocoA('soltar-arquivo')).exists()).toBe(true);
    expect(w.get(`${doBlocoA('historico')} h2`).text()).toBe(
      'Listas que você já trouxe'
    );
  });
});

describe('Tela 9: planilha com seguros', () => {
  it('pergunta se a planilha tem os seguros; "Sim" leva à conferência', async () => {
    const w = await abrir({ como: 'planilha' });
    await w.get(doBlocoA('usar-exemplo')).trigger('click');
    await assentarBem();

    expect(w.get('h1').text()).toBe(
      'Achei números de apólice nesta planilha. Ela tem os seguros dessas pessoas?'
    );
    expect(emFoco()).toBe(w.get('h1').element);
    await clicar(w, 'tem-seguros');

    // Primeira vez da conta: antes de conferir, onde ficam as renovações.
    expect(w.get('h1').text()).toBe('Onde ficam as renovações?');
    expect(emFoco()).toBe(w.get('h1').element);
    await passarPelasRenovacoes(w);

    expect(w.get('h1').text()).toBe('Achei 168 seguros de 120 pessoas.');
    expect(contador(w, 'PRONTOS')).toBe('164 prontos');
    expect(contador(w, 'PRECISAM')).toBe('4 precisam de você');
    // "Já estavam aqui" é uma frase de apoio, sem repetir o número do título.
    expect(w.find('[data-contador="JA_ESTAVAM"]').exists()).toBe(false);
    expect(textoDe(w, daCarteira('ja-estavam-aqui'))).toBe(
      'As 120 pessoas já estavam aqui.'
    );
    expect(w.get(daCarteira('efeito-renovacao')).text()).toBe(
      'Amanhã cedo, 22 seguros que vencem em até 60 dias entram em renovação.'
    );
    expect(w.get(daCarteira('trazer-seguros')).text()).toBe(
      'Trazer 164 seguros'
    );
    expect(w.get(daCarteira('planilha-conferir')).text()).toContain(
      'Você pode desfazer quando quiser.'
    );
  });

  it('conferir: a ação principal fica numa barra sempre à vista e os blocos vêm na ordem de quem decide', async () => {
    const w = await irAteConferir();

    const barra = w.get(daCarteira('barra-de-trazer'));
    expect(barra.classes()).toContain('sticky');
    expect(barra.classes()).toContain('bottom-0');
    // No celular a barra respeita a área segura de baixo.
    expect(
      barra
        .classes()
        .some(classe => classe.includes('env(safe-area-inset-bottom)'))
    ).toBe(true);
    // E deixa livre o canto do botão do menu do app (abaixo de `md`).
    expect(barra.classes()).toEqual(
      expect.arrayContaining(['ps-20', 'md:ps-8'])
    );
    expect(barra.get(daCarteira('trazer-seguros')).text()).toBe(
      'Trazer 164 seguros'
    );
    expect(barra.get(daCarteira('voltar-do-conferir')).text()).toBe('Voltar');
    expect(barra.get(daCarteira('sossego')).text()).toBe(
      'Você pode desfazer quando quiser.'
    );

    // Números, aviso da renovação, o que precisa da pessoa, como vão ficar, o
    // que vou guardar. A barra é o último bloco (ocupa lugar: não cobre nada).
    const tela = w.get(daCarteira('planilha-conferir')).element;
    const blocos = [
      daCarteira('contadores'),
      daCarteira('efeito-renovacao'),
      doBlocoA('precisam-de-voce'),
      daCarteira('exemplos'),
      doBlocoA('o-que-vou-guardar'),
      daCarteira('barra-de-trazer'),
    ].map(seletor => tela.querySelector(seletor));
    blocos.forEach(bloco => expect(bloco).not.toBeNull());
    blocos.slice(1).forEach((bloco, indice) => {
      const depois =
        // eslint-disable-next-line no-bitwise
        blocos[indice].compareDocumentPosition(bloco) &
        Node.DOCUMENT_POSITION_FOLLOWING;
      expect(Boolean(depois)).toBe(true);
    });
    expect(tela.lastElementChild).toBe(barra.element);
  });

  it('as fichas de exemplo mostram os seguros de cada pessoa; quem está sem telefone diz isso', async () => {
    const w = await irAteConferir();

    const fichas = w.findAll(
      `${daCarteira('exemplos')} [data-ficha-de-exemplo]`
    );
    expect(fichas).toHaveLength(3);
    expect(fichas[0].text()).toContain('Fábio Kalinoski');
    expect(fichas[0].findAll(daCarteira('seguro-do-exemplo'))).toHaveLength(3);
    expect(fichas[0].get(daCarteira('seguro-do-exemplo')).text()).toContain(
      'Auto · Seguradora Atlântica · termina em 29/11/2026'
    );
    expect(fichas[2].text()).toContain('Tiago Bragantino');
    expect(fichas[2].get(daCarteira('exemplo-sem-telefone')).text()).toBe(
      'Sem telefone'
    );
  });

  it('o único botão azul da conferência é "Trazer N seguros": o Salvar de cada problema é secundário', async () => {
    const w = await irAteConferir();
    const azuis = w
      .findAll('button')
      .filter(botao => botao.classes().includes('bg-n-blue-11'));

    expect(w.findAll(daCarteira('salvar-problema')).length).toBeGreaterThan(1);
    expect(azuis).toHaveLength(1);
    expect(azuis[0].text()).toMatch('Trazer ');
    expect(w.get(daCarteira('ficar-com-este')).classes()).not.toContain(
      'bg-n-blue-3'
    );
  });

  it('Salvar fica ligado: sem a data, diz o que falta, marca o campo e leva o foco', async () => {
    const w = await irAteConferir();
    const semData = problema(w, 52);
    expect(semData.text()).toContain(
      'Seguro de Hugo Orsolini: falta quando termina'
    );
    expect(semData.text()).toContain('Linha 52 da planilha');
    const salvar = semData.get(daCarteira('salvar-problema'));
    expect(salvar.attributes('disabled')).toBeUndefined();

    await salvar.trigger('click');

    const campo = semData.get('input[type="date"]');
    const aviso = semData.get('[role="alert"]');
    expect(aviso.text()).toBe('Diga quando o seguro termina.');
    expect(campo.attributes('aria-invalid')).toBe('true');
    expect(campo.attributes('aria-describedby')).toBe(aviso.attributes('id'));
    expect(emFoco()).toBe(campo.element);

    await campo.setValue('2027-03-10');
    expect(semData.find('[role="alert"]').exists()).toBe(false);
    await salvar.trigger('click');
    await assentarBem();

    // A linha resolvida diz o que ficou decidido, com o selo e "Mudar".
    const resolvida = problema(w, 52);
    expect(textoDe(resolvida, daCarteira('decidido'))).toBe(
      'Seguro de Hugo Orsolini · termina em 10/03/2027'
    );
    expect(resolvida.text()).not.toContain('falta quando termina');
    const selo = resolvida.get(daCarteira('selo-do-problema'));
    expect(selo.text()).toBe('Pronto');
    expect(selo.attributes('data-selo')).toBe('guardado');
    const mudar = resolvida.get(daCarteira('mudar'));
    expect(mudar.text()).toBe('Mudar');
    expect(mudar.attributes('aria-label')).toBe(
      'Mudar o seguro de Hugo Orsolini'
    );
    // Sempre no mesmo lugar: embaixo no celular, à direita em tela grande.
    const linha = resolvida.get(daCarteira('linha-resolvida'));
    expect(linha.classes()).toEqual(
      expect.arrayContaining(['flex-col', 'sm:flex-row', 'sm:justify-between'])
    );
    expect(linha.element.lastElementChild).toBe(mudar.element);
    expect(resolvida.find(daCarteira('voltar-atras')).exists()).toBe(false);
    expect(contador(w, 'PRONTOS')).toBe('165 prontos');
    expect(contador(w, 'PRECISAM')).toBe('3 precisam de você');
    expect(w.get(daCarteira('anuncio-precisam')).text()).toBe(
      'Hugo Orsolini: pronto'
    );
    expect(w.get(daCarteira('trazer-seguros')).text()).toBe(
      'Trazer 165 seguros'
    );
    // O foco segue para o próximo que ainda precisa da pessoa.
    expect(problema(w, 71).element.contains(emFoco())).toBe(true);
  });

  it('seguradora e telefone também dizem o que falta, sem desligar o Salvar', async () => {
    const w = await irAteConferir();

    const semSeguradora = problema(w, 71);
    // Vazio, o campo diz o que se espera dele.
    expect(semSeguradora.get('[role="combobox"]').text()).toBe(
      'Escolha a seguradora'
    );
    await semSeguradora.get(daCarteira('salvar-problema')).trigger('click');
    expect(semSeguradora.get('[role="alert"]').text()).toBe(
      'Escolha a seguradora.'
    );
    expect(semSeguradora.element.contains(emFoco())).toBe(true);
    expect(emFoco().getAttribute('aria-invalid')).toBe('true');
    expect(emFoco().getAttribute('aria-describedby')).toBe(
      semSeguradora.get('[role="alert"]').attributes('id')
    );

    const semTelefone = problema(w, 140);
    expect(semTelefone.text()).toContain(
      'Seguro de Inês Imbirussu: falta um número no telefone'
    );
    await semTelefone.get(daCarteira('salvar-problema')).trigger('click');
    // O campo de telefone da casa mostra o aviso dele mesmo, ligado ao campo.
    const campo = emFoco();
    expect(semTelefone.element.contains(campo)).toBe(true);
    expect(campo.getAttribute('aria-invalid')).toBe('true');
    expect(
      document.getElementById(campo.getAttribute('aria-describedby'))
        .textContent
    ).toContain('Escreva o telefone inteiro, com DDD.');
    expect(contador(w, 'PRECISAM')).toBe('4 precisam de você');
  });

  it('o seguro que veio duas vezes pergunta qual fica; deixar de fora tem volta', async () => {
    const w = await irAteConferir();

    const repetido = problema(w, 131);
    expect(repetido.text()).toContain(
      'O seguro AT-001288 de Paula Aguiardo aparece duas vezes. Qual fica?'
    );
    expect(repetido.text()).toContain('Linhas 88 e 131 da planilha');
    const opcoes = repetido.findAll('[data-opcao]');
    expect(opcoes.map(opcao => textoDe(opcao, 'span'))).toEqual([
      'Na planilha: R$ 3.410,00',
      'Na planilha: R$ 3.140,00',
    ]);
    // Cada opção é um cartão-botão inteiro: o valor, de que linha veio e
    // "Ficar com este". Não há link solto dentro dele.
    opcoes.forEach(opcao => {
      expect(opcao.element.tagName).toBe('BUTTON');
      expect(opcao.classes()).toEqual(
        expect.arrayContaining(['w-full', 'min-h-11'])
      );
      expect(opcao.find('a').exists()).toBe(false);
    });
    expect(textoDe(opcoes[0], daCarteira('linha-da-opcao'))).toBe(
      'Linha 88 da planilha'
    );
    expect(textoDe(opcoes[1], daCarteira('linha-da-opcao'))).toBe(
      'Linha 131 da planilha'
    );
    expect(
      opcoes.map(opcao => textoDe(opcao, daCarteira('ficar-com-este')))
    ).toEqual(['Ficar com este', 'Ficar com este']);
    expect(repetido.text()).not.toContain('Ficar com a linha');
    await opcoes[0].trigger('click');
    await assentarBem();
    expect(textoDe(problema(w, 131), daCarteira('decidido'))).toBe(
      'Seguro de Paula Aguiardo · fica o da linha 88'
    );
    expect(problema(w, 131).get(daCarteira('selo-do-problema')).text()).toBe(
      'Pronto'
    );

    await problema(w, 71).get(daCarteira('deixar-de-fora')).trigger('click');
    await assentarBem();
    expect(textoDe(problema(w, 71), daCarteira('decidido'))).toBe(
      'Seguro de Karina Tavolari'
    );
    const deixado = problema(w, 71).get(daCarteira('selo-do-problema'));
    expect(deixado.text()).toBe('Deixado de fora');
    expect(deixado.attributes('data-selo')).toBe('deixado');
    expect(contador(w, 'DEIXADOS')).toBe('1 ficou de fora');
    expect(w.get(doBlocoA('precisam-titulo')).text()).toBe(
      'Precisam de você (2)'
    );

    await problema(w, 71).get(daCarteira('mudar')).trigger('click');
    await assentarBem();
    expect(problema(w, 71).text()).toContain('qual é a seguradora “Atl.”?');
    expect(w.find('[data-contador="DEIXADOS"]').exists()).toBe(false);
  });

  it('traz, mostra o andamento, chega no Pronto e deixa desfazer sem prazo', async () => {
    const w = await irAteConferir();
    await problema(w, 52).get('input[type="date"]').setValue('2027-03-10');
    await problema(w, 52).get(daCarteira('salvar-problema')).trigger('click');
    await assentarBem();
    await problema(w, 131).get('[data-opcao="88"]').trigger('click');
    await assentarBem();
    await problema(w, 71).get(daCarteira('deixar-de-fora')).trigger('click');
    await assentarBem();
    await problema(w, 140).get(daCarteira('deixar-de-fora')).trigger('click');
    await assentarBem();
    expect(w.get(doBlocoA('precisam-titulo')).text()).toBe('Tudo resolvido');

    await clicar(w, 'trazer-seguros');
    const barra = w.get('[role="progressbar"]');
    expect(barra.attributes('aria-valuenow')).toBe('0');
    expect(w.get(doBlocoA('andamento')).text()).toContain('Pode fechar');

    await passar(DURACAO_DE_TRAZER_MS);
    expect(w.get(`${daCarteira('pronto')} [role="heading"]`).text()).toBe(
      '166 seguros chegaram, de 118 pessoas.'
    );
    expect(w.get(daCarteira('trazer-mais')).text()).toBe('Trazer outra lista');
    expect(w.get(daCarteira('pronto-sossego')).text()).toBe(
      'Você pode desfazer quando quiser, em “O que você já trouxe”.'
    );

    await clicar(w, 'ver-os-seguros');
    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', demo: 'cheio' },
    });

    const trazida = w.get(`${doBlocoA('historico')} li`);
    expect(trazida.text()).toContain('Carteira 2026.xlsx');
    expect(trazida.get(daCarteira('historico-seguros')).text()).toBe(
      '166 seguros'
    );
    await trazida.get(doBlocoA('desfazer')).trigger('click');
    await assentarBem();
    expect(
      w.findAll(`${daCarteira('o-que-sai')} p`).map(frase => frase.text())
    ).toEqual([
      'Isto tira os 166 seguros que vieram nesta planilha, com os PDFs deles.',
      'As 118 pessoas continuam aqui, como eram antes.',
    ]);
    await w.get('[data-dialogo-falso]').trigger('submit');
    await assentarBem();
    expect(w.get(`${doBlocoA('historico')} li [data-situacao]`).text()).toBe(
      'Desfeito'
    );
  });

  it('se trazer falha, a barra diz numa linha e "Trazer N seguros" tenta de novo', async () => {
    const w = await irAteConferir({ caso: 'trazer_falhou' });

    await clicar(w, 'trazer-seguros');
    // O aviso fica na barra sempre à vista, na linha de cima do botão: quem
    // clicou lá embaixo vê o que deu errado sem rolar a página.
    const barra = w.get(daCarteira('barra-de-trazer'));
    const erro = barra.get(daCarteira('erro'));
    expect(erro.text()).toBe('Não consegui trazer agora. Tente de novo.');
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.classes()).toContain('basis-full');
    expect(barra.element.firstElementChild).toBe(erro.element);
    // Uma linha de texto, sem botão próprio: o único azul continua sendo o de
    // trazer, e clicar nele de novo é o tentar de novo.
    expect(erro.element.matches('p')).toBe(true);
    expect(erro.find('button').exists()).toBe(false);
    const azuis = w
      .findAll('button')
      .filter(botao => botao.classes().includes('bg-n-blue-11'));
    expect(azuis.map(botao => botao.attributes('data-carteira'))).toEqual([
      'trazer-seguros',
    ]);
    // Depois do erro o botão está livre de novo: nem desligado, nem ocupado.
    expect(azuis[0].attributes('disabled')).toBeUndefined();
    expect(azuis[0].attributes('aria-busy')).not.toBe('true');

    await clicar(w, 'trazer-seguros');
    await assentarBem();
    expect(w.find(doBlocoA('andamento')).exists()).toBe(true);
  });

  it('"Não, só as pessoas" segue pelas telas de sempre; o Voltar devolve à pergunta dos seguros', async () => {
    const w = await abrir({ como: 'planilha' });
    await w.get(doBlocoA('usar-exemplo')).trigger('click');
    await assentarBem();

    await clicar(w, 'so-pessoas');

    expect(w.get(daCarteira('trazer')).isVisible()).toBe(false);
    const pergunta = w.get(doBlocoA('pergunta'));
    expect(pergunta.get('h1').text()).toBe('Essas pessoas já são clientes?');
    expect(emFoco()).toBe(pergunta.get('h1').element);

    await pergunta
      .findAll('button')
      .find(botao => botao.text() === 'Voltar')
      .trigger('click');
    await assentarBem();

    expect(w.find(doBlocoA('pergunta')).exists()).toBe(false);
    expect(w.get(daCarteira('trazer')).isVisible()).toBe(true);
    expect(w.get(daCarteira('pergunta-seguros')).isVisible()).toBe(true);
    expect(useAlert).not.toHaveBeenCalled();
  });
});

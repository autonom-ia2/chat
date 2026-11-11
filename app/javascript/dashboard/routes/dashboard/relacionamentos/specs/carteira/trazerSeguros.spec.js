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

const TITULO_DA_ESCOLHA = 'Como você quer trazer as pessoas e os seguros?';
const DURACAO_DE_TRAZER_MS = 8000;

// Da escolha até a conferência da planilha de exemplo.
const irAteConferir = async query => {
  const w = await abrir({ como: 'planilha', ...query });
  await w.get(doBlocoA('usar-exemplo')).trigger('click');
  await assentarBem();
  await clicar(w, 'tem-seguros');
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
  it('na conta de seguros a entrada é a escolha, com três cartões e um botão', async () => {
    const w = await abrir();

    expect(w.get('h1').text()).toBe(TITULO_DA_ESCOLHA);
    expect(textoDe(w, daCarteira('cartao-planilha'))).toBe(
      'Planilha Excel ou CSV, com os seguros ou só as pessoas.'
    );
    expect(textoDe(w, daCarteira('cartao-pdfs'))).toBe(
      'PDFs das apólices Arraste os PDFs. Eu leio cada um.'
    );
    expect(textoDe(w, daCarteira('cartao-agger'))).toBe(
      'Agger Traga direto do seu Agger e mantenha em dia sozinho.'
    );
    expect(w.get(daCarteira('continuar-como')).text()).toBe('Continuar');
    // As etapas do topo e a área de soltar só vêm depois da escolha.
    expect(w.find('ol').exists()).toBe(false);
    expect(w.find(doBlocoA('soltar-arquivo')).exists()).toBe(false);
    expect(w.get(`${doBlocoA('historico')} h2`).text()).toBe(
      'O que você já trouxe'
    );
  });

  it('Continuar fica ligado: sem escolha, diz o que falta e leva o foco aos cartões', async () => {
    const w = await abrir();
    const continuar = w.get(daCarteira('continuar-como'));
    expect(continuar.attributes('disabled')).toBeUndefined();

    await continuar.trigger('click');

    const aviso = w.get(daCarteira('falta-escolher'));
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toBe('Escolha de onde vêm as pessoas e os seguros.');
    const grupo = w.get('[role="radiogroup"]');
    expect(grupo.attributes('aria-invalid')).toBe('true');
    expect(grupo.attributes('aria-describedby')).toBe(aviso.attributes('id'));
    expect(emFoco()).toBe(w.get(daCarteira('cartao-planilha')).element);
    expect(roteador.push).not.toHaveBeenCalled();

    await w.get(daCarteira('cartao-pdfs')).trigger('click');
    expect(w.find(daCarteira('falta-escolher')).exists()).toBe(false);
  });

  it('a escolha vai para o endereço e abre o passo daquele jeito', async () => {
    const w = await abrir();

    await w.get(daCarteira('cartao-planilha')).trigger('click');
    await clicar(w, 'continuar-como');

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

    expect(textoDe(w, daCarteira('cartao-agger'))).toBe(
      'Agger Sua conta já está ligada ao Agger.'
    );
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

    expect(w.get('h1').text()).toBe('Achei 168 seguros de 120 pessoas.');
    expect(contador(w, 'PRONTOS')).toBe('164 prontos');
    expect(contador(w, 'PRECISAM')).toBe('4 precisam de você');
    expect(contador(w, 'JA_ESTAVAM')).toBe('120 pessoas já estavam aqui');
    expect(w.get(daCarteira('efeito-renovacao')).text()).toBe(
      'Amanhã cedo, 22 seguros que vencem em até 60 dias viram card de renovação.'
    );
    expect(w.get(daCarteira('trazer-seguros')).text()).toBe(
      'Trazer 164 seguros'
    );
    expect(w.get(daCarteira('planilha-conferir')).text()).toContain(
      'Você pode desfazer quando quiser.'
    );
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

    expect(problema(w, 52).text()).toContain('Pronto');
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
    await opcoes[0].trigger('click');
    await assentarBem();
    expect(problema(w, 131).text()).toContain('Pronto');

    await problema(w, 71).get(daCarteira('deixar-de-fora')).trigger('click');
    await assentarBem();
    expect(problema(w, 71).text()).toContain('Deixado de fora');
    expect(contador(w, 'DEIXADOS')).toBe('1 ficou de fora');
    expect(w.get(doBlocoA('precisam-titulo')).text()).toBe(
      'Precisam de você (2)'
    );

    await problema(w, 71).get(daCarteira('voltar-atras')).trigger('click');
    await assentarBem();
    expect(problema(w, 71).text()).toContain('não conheço a seguradora “Atl.”');
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

  it('se trazer falha, a tela diz e Tentar de novo resolve', async () => {
    const w = await irAteConferir({ caso: 'trazer_falhou' });

    await clicar(w, 'trazer-seguros');
    expect(w.get(daCarteira('erro')).text()).toContain(
      'Não consegui trazer os seguros. Tente de novo.'
    );

    await w.get(`${daCarteira('erro')} button`).trigger('click');
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

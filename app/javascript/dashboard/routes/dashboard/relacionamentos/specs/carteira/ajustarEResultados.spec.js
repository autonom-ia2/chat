import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import AjustarRenovacoesPage from '../../pages/AjustarRenovacoesPage.vue';
import ResultadosDasRenovacoesPage from '../../pages/ResultadosDasRenovacoesPage.vue';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { ajustesDaDemo } from '../../demo/carteiraAjustes';
import { usarDemo } from '../../fonte/modoDemo';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  semRolagem,
  textoDe,
} from './apoio';

// "Como as renovações andam" e "Resultados das renovações" (#2897, telas 13 e
// 14), com a conta fictícia e o texto de verdade em pt_BR. A demonstração entra
// pelo endereço (`?demo=`), como no navegador.
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('shared/composables/useBranding', async () => {
  const { computed } = await import('vue');
  return {
    useBranding: () => ({
      installationName: computed(() => 'Casa de Exemplo'),
    }),
  };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: '' });
  const roteador = { push: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});
vi.mock('../../fonte/renovacoesFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    renovacoesFonte: opcoes => real.renovacoesFonte({ ...opcoes, atraso: 0 }),
  };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();

let aberta;
const abrir = async (pagina, query = {}) => {
  rota.query = { demo: 'cheio', ...query };
  aberta = mount(pagina, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const escolhido = (w, cartao) =>
  w.get(`${daCarteira(cartao)} [role="radio"][aria-checked="true"]`).text();
const opcao = (cartao, id) => `${daCarteira(cartao)} [data-resposta="${id}"]`;

beforeAll(async () => {
  semRolagem();
  await carregarDemonstracao();
}, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  usarDemo({ demo: 'desligado' });
  vi.clearAllMocks();
});

describe('Tela 13: como as renovações andam', () => {
  const ajustar = query => abrir(AjustarRenovacoesPage, query);

  it('todo cartão chega respondido com o padrão, e o foco abre no título', async () => {
    const w = await ajustar();

    expect(w.get('h1').text()).toBe('Como as renovações andam');
    expect(document.activeElement).toBe(w.get('h1').element);
    expect(w.text()).toContain(
      'Já está funcionando assim. Mude só o que quiser.'
    );
    expect(
      w.findAll('section[data-carteira^="ajuste-"] h2').map(h2 => h2.text())
    ).toEqual([
      'Onde ficam as renovações?',
      'Mensagens antes de vencer',
      'Algo mudou?',
      'Quem faz a cotação?',
      'Como a proposta chega à pessoa?',
      'Quem responde depois?',
      'Seu seguro em palavras simples',
    ]);
    expect(escolhido(w, 'ajuste-onde')).toContain('Criar o funil Renovação');
    expect(w.get(`${daCarteira('dias-antes')} input`).element.value).toBe('60');
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 60 dias, 22 seguros entram em renovação amanhã cedo.'
    );
    expect(escolhido(w, 'ajuste-mensagens')).toBe(
      'Mandar sozinho aos 30, 15 e 7 dias'
    );
    expect(escolhido(w, 'ajuste-algo-mudou')).toBe('Perguntar');
    expect(escolhido(w, 'ajuste-quem-cota')).toContain('Robô de renovação');
    expect(escolhido(w, 'ajuste-como-envia')).toBe(
      'Uma pessoa confere e aperta Enviar'
    );
    expect(escolhido(w, 'ajuste-quem-responde')).toBe('Lia');
    expect(escolhido(w, 'ajuste-palavras-simples')).toBe('Eu confiro antes');
  });

  it('as prévias mostram as mensagens como chegam, com um seguro da conta de exemplo', async () => {
    const w = await ajustar();

    const previas = w
      .findAll(`${daCarteira('previa-das-mensagens')} figure`)
      .map(figura => figura.text());
    expect(previas).toHaveLength(3);
    expect(previas[0]).toContain('30 dias antes');
    expect(previas[0]).toContain('Oi, Fábio! Seu seguro Auto vence em ');
    expect(previas[1]).toContain(
      'Oi, Fábio! Faltam 15 dias para o seu seguro Auto vencer, em '
    );
    expect(previas[2]).toContain('Responda aqui para renovar a tempo.');
    const algoMudou = w.get(daCarteira('ajuste-algo-mudou')).text();
    [
      'Nada mudou',
      'Mudou algo',
      'Troquei de carro',
      'Mudei de endereço',
    ].forEach(botao => expect(algoMudou).toContain(botao));

    // "Não mandar" tira as prévias.
    await clicar(w, opcao('ajuste-mensagens', 'nao_mandar'));
    expect(w.find(daCarteira('previa-das-mensagens')).exists()).toBe(false);
  });

  it('não mostra consumo, custo nem limite de uso', async () => {
    const w = await ajustar();
    const tudo = w.text().toLowerCase();

    expect(w.find(daCarteira('ajuste-consumo')).exists()).toBe(false);
    ['consumo', 'cotações nos últimos', 'custo', 'limite', 'teto'].forEach(
      palavra => expect(tudo).not.toContain(palavra)
    );
  });

  it('Salvar fica ligado: sem mudança, o clique diz isso e leva o foco à primeira escolha', async () => {
    const w = await ajustar();
    const salvar = w.get(daCarteira('salvar-ajustes'));
    expect(salvar.attributes('disabled')).toBeUndefined();

    await clicar(w, daCarteira('salvar-ajustes'));

    const alerta = w.get(daCarteira('alerta-dos-ajustes'));
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'Você ainda não mudou nada. Mude o que quiser e salve.'
    );
    expect(salvar.attributes('aria-describedby')).toBe(alerta.attributes('id'));
    expect(document.activeElement).toBe(
      w.get(daCarteira('criar-funil')).element
    );
  });

  it('"sai sozinha": uma escolha simples, sem outra confirmação; salvar guarda e diz "Salvo."', async () => {
    const w = await ajustar();

    await clicar(w, daCarteira('envia-sozinha'));
    expect(textoDe(w, daCarteira('sai-sozinha'))).toBe(
      'Sai sem ninguém apertar nada. Você vê tudo o que saiu na renovação de cada seguro.'
    );
    await clicar(w, daCarteira('salvar-ajustes'));

    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
    const salvo = w.get(daCarteira('ajustes-salvos'));
    expect(salvo.attributes('role')).toBe('status');
    expect(salvo.text()).toBe('Salvo.');
    expect(ajustesDaDemo().comoEnvia).toBe('sozinha');
    // Salvo, nada mais mudou: o próximo clique volta a dizer isso.
    await clicar(w, daCarteira('salvar-ajustes'));
    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toContain(
      'Você ainda não mudou nada.'
    );
  });

  it('usar um funil que já tenho: falta o funil, o clique diz e leva o foco; a etapa já vem escolhida', async () => {
    const w = await ajustar();

    await clicar(w, daCarteira('usar-funil'));
    await clicar(w, daCarteira('salvar-ajustes'));
    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toBe(
      'Escolha o funil.'
    );
    const funil = w.get(`${daCarteira('escolher-funil')} button`);
    expect(document.activeElement).toBe(funil.element);
    expect(ajustesDaDemo().onde).toBe('criar');

    await funil.trigger('click');
    await clicar(w, `${daCarteira('escolher-funil')} [role="option"]`);
    expect(w.get(`${daCarteira('escolher-etapa')} button`).text()).toContain(
      'Novo contato'
    );
    expect(w.find(daCarteira('alerta-dos-ajustes')).exists()).toBe(false);
    await clicar(w, daCarteira('salvar-ajustes'));
    expect(ajustesDaDemo()).toMatchObject({
      onde: 'usar',
      funil: 'Vendas',
      etapa: 'Novo contato',
    });
  });

  it('os dias: menos e mais mudam o número e a linha de efeito; letra diz o que falta', async () => {
    const w = await ajustar();
    const dias = w.get(`${daCarteira('dias-antes')} input`);

    await dias.setValue('30');
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 30 dias, 17 seguros entram em renovação amanhã cedo.'
    );
    await w.get('[data-dias="mais"]').trigger('click');
    expect(dias.element.value).toBe('31');
    await w.get('[data-dias="menos"]').trigger('click');
    await w.get('[data-dias="menos"]').trigger('click');
    expect(dias.element.value).toBe('29');

    await dias.setValue('muitos');
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe('');
    await clicar(w, daCarteira('salvar-ajustes'));
    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toBe(
      'Escreva quantos dias antes, a partir de 1.'
    );
    expect(dias.attributes('aria-invalid')).toBe('true');
    expect(document.activeElement).toBe(dias.element);
  });

  it('se salvar falha, diz e mantém as escolhas; tentar de novo salva', async () => {
    const w = await ajustar({ caso: 'ajustes_nao_salvou' });
    await clicar(w, opcao('ajuste-palavras-simples', 'sozinho'));

    await clicar(w, daCarteira('salvar-ajustes'));
    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toBe(
      'Não consegui salvar. Tente de novo.'
    );
    expect(escolhido(w, 'ajuste-palavras-simples')).toBe('Sai sozinho');

    await clicar(w, daCarteira('salvar-ajustes'));
    expect(w.get(daCarteira('ajustes-salvos')).text()).toBe('Salvo.');
    expect(ajustesDaDemo().palavras).toBe('sozinho');
  });

  it('conta sem Agger: um cartão só, que leva a ligar; com a cotação desligada, explica quem liga', async () => {
    const semAgger = await ajustar({ demo: 'sem-seguros' });
    expect(semAgger.find(daCarteira('ajuste-quem-cota')).exists()).toBe(false);
    expect(semAgger.find(daCarteira('ajuste-como-envia')).exists()).toBe(false);
    expect(textoDe(semAgger, daCarteira('ajuste-cotacao'))).toContain(
      'Para cotar sozinho, ligue sua conta ao Agger.'
    );
    await clicar(semAgger, daCarteira('ligar-agger'));
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
      query: { como: 'agger' },
    });
    semAgger.unmount();

    const desligada = await ajustar({ cotacao: 'desligada' });
    expect(textoDe(desligada, daCarteira('ajuste-cotacao'))).toContain(
      'A cotação automática ainda não está ligada na sua conta.'
    );
    await clicar(desligada, daCarteira('quero-ligar'));
    expect(desligada.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Cotação automática'
    );
    expect(desligada.get('[data-dialogo-falso]').text()).toContain(
      'A cotação automática é ligada pela equipe da Casa de Exemplo. Fale com quem cuida da sua conta para ligar.'
    );
    expect(desligada.get(doBlocoA('entendi')).text()).toBe('Entendi');
  });

  it('sem quem atenda sozinho, só a equipe responde; sem permissão de funil, o cartão só mostra a escolha de hoje', async () => {
    const semAgente = await ajustar({ caso: 'cotacao_sem_agente' });
    expect(
      semAgente
        .findAll(`${daCarteira('ajuste-quem-responde')} [role="radio"]`)
        .map(cartao => cartao.text())
    ).toEqual(['A equipe']);
    expect(textoDe(semAgente, daCarteira('ajuste-quem-responde'))).toContain(
      'Quer que um agente responda sozinho? Veja em Agentes.'
    );
    semAgente.unmount();

    const semPermissao = await ajustar({ caso: 'sem_permissao_de_funil' });
    const onde = semPermissao.get(daCarteira('ajuste-onde'));
    expect(onde.find('[role="radio"]').exists()).toBe(false);
    expect(onde.get(daCarteira('escolha-de-hoje')).text()).toBe(
      'Hoje: funil Renovação, 60 dias antes do fim.'
    );
    expect(onde.text()).toContain(
      'Quem cuida dos funis da sua conta precisa fazer esta escolha.'
    );
    // Os outros cartões funcionam.
    await clicar(semPermissao, opcao('ajuste-mensagens', 'nao_mandar'));
    await clicar(semPermissao, daCarteira('salvar-ajustes'));
    expect(semPermissao.get(daCarteira('ajustes-salvos')).text()).toBe(
      'Salvo.'
    );
  });

  it('carregando: o esqueleto, sem Salvar; erro: a frase e "Tentar de novo"; o link volta aos seguros', async () => {
    const carregando = await ajustar({ demo: 'carregando' });
    expect(carregando.find(daCarteira('carregando')).exists()).toBe(true);
    expect(carregando.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
    carregando.unmount();

    const comErro = await ajustar({ 'demo-carteira': 'erro' });
    expect(comErro.get(daCarteira('erro')).text()).toContain(
      'Não consegui abrir os ajustes. Tente de novo.'
    );
    expect(comErro.get(`${daCarteira('erro')} button`).text()).toBe(
      'Tentar de novo'
    );
    await clicar(comErro, doBlocoA('voltar'));
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros' },
    });
  });
});

describe('Tela 14: resultados das renovações', () => {
  const resultados = query => abrir(ResultadosDasRenovacoesPage, query);
  const barras = (w, bloco) =>
    w
      .findAll(`${daCarteira(bloco)} ${daCarteira('barra-de-resultado')}`)
      .map(barra =>
        barra
          .findAll('span')
          .slice(0, 2)
          .map(parte => parte.text())
          .join(' ')
      );

  it('o herói diz quantos renovou e a ação leva a quem não renovou', async () => {
    const w = await resultados();

    expect(w.get('h1').text()).toBe('Resultados das renovações');
    expect(document.activeElement).toBe(w.get('h1').element);
    expect(
      w.get(`${daCarteira('resultados-heroi')} [data-heroi-frase]`).text()
    ).toBe('Nos últimos 30 dias, você renovou 14 de 19 seguros.');
    const ver = w.get(daCarteira('ver-nao-renovaram'));
    expect(ver.text()).toBe('Ver os 5 que não renovaram');

    await ver.trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', grupo: 'nao_renovaram_30' },
    });
  });

  it('os motivos e o recorte, com o número escrito ao lado de cada barra', async () => {
    const w = await resultados();

    expect(barras(w, 'motivos')).toEqual([
      'Achou caro 2',
      'Foi para outra corretora 1',
      'Vendeu o bem 1',
      'Não respondeu 1',
    ]);
    expect(barras(w, 'recorte')).toEqual([
      'Auto 7 de 9 renovaram',
      'Residencial 4 de 5 renovaram',
      'Vida 2 de 3 renovaram',
      'Empresarial 1 de 2 renovou',
    ]);
    // A barra é desenho: quem lê com leitor de tela fica com o número.
    const barra = w.get(`${daCarteira('motivos')} [data-largura]`);
    expect(barra.attributes('data-largura')).toBe('40');
    expect(barra.element.parentElement.getAttribute('aria-hidden')).toBe(
      'true'
    );

    await clicar(w, `${daCarteira('recorte')} [data-grupo="cuida"]`);
    expect(barras(w, 'recorte')).toEqual([
      'Bia Lunardelli 8 de 11 renovaram',
      'Caio Tavarone 6 de 8 renovaram',
    ]);
  });

  it('o período muda o herói, os motivos e para onde a ação leva', async () => {
    const w = await resultados();

    await w.get(`${daCarteira('periodo')} button`).trigger('click');
    const opcoes = w.findAll(`${daCarteira('periodo')} [role="option"]`);
    expect(opcoes.map(o => o.text())).toEqual([
      'Últimos 30 dias',
      'Últimos 90 dias',
      'Últimos 12 meses',
    ]);
    await opcoes[2].trigger('click');
    await assentar();

    expect(
      w.get(`${daCarteira('resultados-heroi')} [data-heroi-frase]`).text()
    ).toBe('Nos últimos 12 meses, você renovou 151 de 190 seguros.');
    expect(w.get(daCarteira('ver-nao-renovaram')).text()).toBe(
      'Ver os 39 que não renovaram'
    );
    expect(barras(w, 'motivos')[0]).toBe('Achou caro 17');
    await clicar(w, daCarteira('ver-nao-renovaram'));
    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', grupo: 'nao_renovaram_365' },
    });
  });

  it('o rodapé diz quantos vencem em 30 dias e leva a eles', async () => {
    const w = await resultados();

    expect(textoDe(w, daCarteira('vencem-30'))).toContain(
      'Vencem nos próximos 30 dias: 17.'
    );
    await clicar(w, daCarteira('ver-quais'));
    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', grupo: 'vence_30_dias' },
    });
  });

  it('sem vencimento no período: só a frase, com o período à vista', async () => {
    const w = await resultados({ demo: 'sem-seguros' });

    expect(w.get(daCarteira('resultados-vazio')).text()).toBe(
      'Nenhum seguro venceu neste período.'
    );
    expect(w.find(daCarteira('periodo')).exists()).toBe(true);
    expect(w.find(daCarteira('resultados-heroi')).exists()).toBe(false);
    expect(w.find(daCarteira('motivos')).exists()).toBe(false);
    expect(w.find(daCarteira('vencem-30')).exists()).toBe(false);
  });

  it('carregando: o esqueleto; erro: a frase e "Tentar de novo"', async () => {
    const carregando = await resultados({ demo: 'carregando' });
    expect(carregando.find(daCarteira('carregando')).exists()).toBe(true);
    expect(carregando.find(daCarteira('resultados-heroi')).exists()).toBe(
      false
    );
    carregando.unmount();

    const comErro = await resultados({ 'demo-carteira': 'erro' });
    expect(comErro.get(daCarteira('erro')).text()).toContain(
      'Não consegui mostrar os resultados. Tente de novo.'
    );
    expect(comErro.get(`${daCarteira('erro')} button`).text()).toBe(
      'Tentar de novo'
    );
  });
});

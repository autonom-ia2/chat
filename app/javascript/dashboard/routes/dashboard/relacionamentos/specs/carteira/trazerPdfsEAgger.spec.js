import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import SoltarArquivo from '../../components/trazer/SoltarArquivo.vue';
import { salvarAjustesNaDemo } from '../../demo/carteiraAjustes';
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

// Trazer por PDFs (Tela 16) e pelo Agger (Tela 17) na conta de seguros (#2897),
// pela página de verdade, com o texto em pt_BR. Nada é lido nem buscado de
// verdade: a fonte de demonstração responde conforme o relógio do teste.
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

const LEITURA_DOS_PDFS_MS = 7000;
const UM_PASSO_DA_BUSCA_MS = 1500;
const BUSCA_INTEIRA_MS = 6000;
const DURACAO_DE_TRAZER_MS = 8000;

const lerOsPdfsDeExemplo = async query => {
  const w = await abrir({ como: 'pdfs', ...query });
  await clicar(w, 'pdfs-usar-exemplo');
  await clicar(w, 'ler-pdfs');
  return w;
};

const entrarNoAgger = async (
  w,
  { usuario = 'corretora', senha = 'exemplo' }
) => {
  await w.get(daCarteira('agger-usuario')).setValue(usuario);
  await w.get(daCarteira('agger-senha')).setValue(senha);
  await clicar(w, 'agger-entrar');
};
const seguradoras = w =>
  w
    .findAll(daCarteira('agger-seguradora'))
    .map(linha => [
      linha.get('p').text(),
      linha.attributes('data-situacao'),
      linha.findAll('p')[1].text(),
    ]);

beforeAll(carregarDemonstracaoDeTrazer, 60000);
// A conta destes testes já escolheu onde ficam as renovações: o passo da
// primeira vez tem os testes dele (ondeFicamAsRenovacoes.spec.js).
beforeEach(() => {
  ligarRelogio();
  salvarAjustesNaDemo({});
});
afterEach(() => {
  fecharTrazer();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe('Tela 16: trazer por PDFs', () => {
  it('pede os PDFs e não fala em custo; "Ler os PDFs" sem arquivo diz o que falta', async () => {
    const w = await abrir({ como: 'pdfs' });

    expect(w.get('h1').text()).toBe('Traga os PDFs das suas apólices.');
    expect(w.get(daCarteira('pdfs-soltar')).text()).toContain(
      'De qualquer seguradora. Pode ser foto de celular.'
    );
    const tela = w.get(daCarteira('trazer')).text();
    expect(tela).not.toContain('R$');
    expect(tela).not.toContain('custa');

    const ler = w.get(daCarteira('ler-pdfs'));
    expect(ler.attributes('disabled')).toBeUndefined();
    await ler.trigger('click');
    await assentarBem();

    const aviso = w.get(daCarteira('falta-pdfs'));
    const area = w.get(doBlocoA('soltar-arquivo'));
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toBe('Escolha os PDFs das apólices.');
    expect(area.attributes('aria-invalid')).toBe('true');
    expect(area.attributes('aria-describedby')).toContain(
      aviso.attributes('id')
    );
    expect(emFoco()).toBe(area.element);
  });

  it('arquivo que não é PDF: a tela diz e continua pedindo os PDFs', async () => {
    const w = await abrir({ como: 'pdfs' });

    w.getComponent(SoltarArquivo).vm.$emit('arquivos', [
      { name: 'carteira.xlsx' },
    ]);
    await assentarBem();

    expect(w.get(daCarteira('pdfs-erro')).text()).toBe(
      'Nenhum destes arquivos é PDF. Escolha os PDFs das apólices.'
    );
    expect(w.find(daCarteira('pdfs-escolhidos')).exists()).toBe(false);
  });

  it('mostra quantos foram escolhidos, lê com barra de andamento e chega na conferência', async () => {
    const w = await abrir({ como: 'pdfs' });
    await clicar(w, 'pdfs-usar-exemplo');

    expect(textoDe(w, `${daCarteira('pdfs-escolhidos')} [role="status"]`)).toBe(
      '40 PDFs escolhidos'
    );
    const verNomes = w.get(daCarteira('pdfs-ver-nomes'));
    expect(verNomes.text()).toBe('Ver os 40');
    await verNomes.trigger('click');
    expect(w.findAll(`${daCarteira('pdfs-escolhidos')} li`)).toHaveLength(40);

    await clicar(w, 'ler-pdfs');
    const barra = w.get(`${daCarteira('pdfs-lendo')} [role="progressbar"]`);
    expect(barra.attributes('aria-valuemax')).toBe('40');
    expect(w.get(daCarteira('pdfs-lendo')).text()).toContain('de 40…');

    await passar(LEITURA_DOS_PDFS_MS);
    expect(w.get('h1').text()).toBe(
      'Li 40 PDFs. Achei 39 seguros de 31 pessoas.'
    );
    expect(emFoco()).toBe(w.get('h1').element);
    expect(contador(w, 'PRONTOS')).toBe('37 prontos');
    expect(contador(w, 'PRECISAM')).toBe('2 precisam de você');
    expect(contador(w, 'NAO_E_APOLICE')).toBe('1 não é apólice');
    expect(w.get(daCarteira('pdfs-nao-e-apolice')).text()).toContain(
      '“boleto-marco.pdf” não é uma apólice. Fica de fora.'
    );
    expect(w.get(daCarteira('trazer-pdfs')).text()).toBe('Trazer 37 seguros');
    expect(w.get(daCarteira('pdfs-conferir')).text()).not.toContain('R$ 0');
  });

  it('o PDF sem telefone pode seguir sem ele; depois de trazer, oferece trazer mais PDFs', async () => {
    const w = await lerOsPdfsDeExemplo();
    await passar(LEITURA_DOS_PDFS_MS);

    const semTelefone = problema(w, 2);
    expect(semTelefone.text()).toContain(
      'Seguro de Bruno Zambelli: não achei o telefone neste PDF'
    );
    expect(semTelefone.text()).toContain('No arquivo “apolice-31.pdf”');
    await semTelefone.get(daCarteira('seguir-sem-telefone')).trigger('click');
    await assentarBem();
    expect(problema(w, 2).text()).toContain('Pronto');
    expect(w.get(daCarteira('pdfs-precisam')).text()).toContain(
      'Seguro de Marina Tavolari: não achei quando termina neste PDF'
    );

    await clicar(w, 'trazer-pdfs');
    await passar(DURACAO_DE_TRAZER_MS);
    expect(w.get(`${daCarteira('pronto')} [role="heading"]`).text()).toBe(
      '38 seguros chegaram, de 30 pessoas.'
    );
    expect(w.get(daCarteira('trazer-mais')).text()).toBe('Trazer mais PDFs');
    expect(w.get(`${doBlocoA('historico')} li`).text()).toContain(
      '40 PDFs de apólices'
    );

    await clicar(w, 'trazer-mais');
    expect(w.get('h1').text()).toBe('Traga os PDFs das suas apólices.');
    expect(w.find(daCarteira('pdfs-escolhidos')).exists()).toBe(false);
  });

  it('se a leitura falha, diz e deixa tentar de novo', async () => {
    const w = await lerOsPdfsDeExemplo({ caso: 'pdfs_nao_leu' });

    expect(w.get(daCarteira('pdfs-erro')).text()).toContain(
      'Não consegui ler os PDFs. Tente de novo.'
    );
    await w.get(`${daCarteira('pdfs-erro')} button`).trigger('click');
    await passar(LEITURA_DOS_PDFS_MS);
    expect(w.find(daCarteira('pdfs-conferir')).exists()).toBe(true);
  });

  it('foto escura: pede outra foto ou deixa de fora', async () => {
    const w = await lerOsPdfsDeExemplo({ caso: 'foto_escura' });
    await passar(LEITURA_DOS_PDFS_MS);

    const foto = problema(w, 2);
    expect(foto.text()).toContain(
      '“apolice-ana.jpg” está escura demais. Tire outra foto com mais luz.'
    );
    expect(foto.get(daCarteira('trocar-o-arquivo')).text()).toBe(
      'Trocar o arquivo'
    );
    await foto.get(daCarteira('deixar-de-fora')).trigger('click');
    await assentarBem();
    expect(contador(w, 'DEIXADOS')).toBe('1 ficou de fora');
  });
});

describe('Tela 17: trazer pelo Agger', () => {
  it('pede o usuário e a senha; "Entrar e trazer" fica ligado e diz o que falta', async () => {
    const w = await abrir({ como: 'agger' });

    expect(w.get('h1').text()).toBe('Entre com o seu login do Agger');
    const usuario = w.get(daCarteira('agger-usuario'));
    const senha = w.get(daCarteira('agger-senha'));
    expect(senha.attributes('type')).toBe('password');
    expect(usuario.element.value).toBe('');
    expect(senha.element.value).toBe('');
    const entrar = w.get(daCarteira('agger-entrar'));
    expect(entrar.attributes('disabled')).toBeUndefined();

    await entrar.trigger('submit');
    await assentarBem();
    const avisos = w.findAll(
      `${daCarteira('agger-entrar-form')} [role="alert"]`
    );
    expect(avisos.map(aviso => aviso.text())).toEqual([
      'Escreva o seu usuário do Agger.',
      'Escreva a sua senha do Agger.',
    ]);
    expect(usuario.attributes('aria-invalid')).toBe('true');
    expect(usuario.attributes('aria-describedby')).toBe(
      avisos[0].attributes('id')
    );
    expect(emFoco()).toBe(usuario.element);

    await usuario.setValue('corretora');
    await entrar.trigger('submit');
    await assentarBem();
    expect(emFoco()).toBe(senha.element);

    // "Mostrar a senha" fica junto do campo e diz se está apertado.
    const mostrar = w.get(daCarteira('agger-mostrar-senha'));
    expect(
      w.get(daCarteira('agger-campo-senha')).element.contains(senha.element)
    ).toBe(true);
    expect(
      w.get(daCarteira('agger-campo-senha')).element.contains(mostrar.element)
    ).toBe(true);
    expect(mostrar.attributes('aria-label')).toBe('Mostrar a senha');
    expect(mostrar.attributes('aria-pressed')).toBe('false');
    await mostrar.trigger('click');
    expect(senha.attributes('type')).toBe('text');
    expect(mostrar.attributes('aria-pressed')).toBe('true');
    expect(mostrar.attributes('aria-label')).toBe('Mostrar a senha');
    await mostrar.trigger('click');
    expect(senha.attributes('type')).toBe('password');
  });

  it('o login diz para que serve a senha, e o primeiro passo do topo se chama Buscar', async () => {
    const w = await abrir({ como: 'agger' });

    const sossego = w.get(daCarteira('agger-senha-segura'));
    expect(sossego.text()).toBe(
      'Sua senha fica guardada com segurança. Ela serve para buscar os seus seguros e cotar as renovações.'
    );
    expect(
      w.get(daCarteira('agger-senha')).attributes('aria-describedby')
    ).toContain(sossego.attributes('id'));
    const passos = w.findAll('ol li').map(passo => passo.text());
    expect(passos[0]).toContain('Buscar');
    expect(passos.join(' ')).not.toContain('Enviar');
    fecharTrazer();

    // Na planilha e nos PDFs o primeiro passo continua "Enviar".
    const planilha = await abrir({ como: 'planilha' });
    expect(planilha.findAll('ol li')[0].text()).toContain('Enviar');
  });

  it('usuário ou senha que não conferem: a tela diz e fica no login', async () => {
    const w = await abrir({ como: 'agger' });

    await entrarNoAgger(w, { senha: 'errada' });

    const erro = w.get(daCarteira('agger-erro'));
    expect(erro.text()).toBe(
      'Usuário ou senha não conferem. Confira e tente de novo.'
    );
    expect(w.find(daCarteira('agger-buscando')).exists()).toBe(false);

    // Os dois campos ficam marcados, apontam para o aviso, e o foco volta ao
    // usuário: é por ele que a pessoa recomeça.
    const usuario = w.get(daCarteira('agger-usuario'));
    const senha = w.get(daCarteira('agger-senha'));
    [usuario, senha].forEach(campo => {
      expect(campo.attributes('aria-invalid')).toBe('true');
      expect(campo.attributes('aria-describedby').split(' ')).toContain(
        erro.attributes('id')
      );
    });
    expect(emFoco()).toBe(usuario.element);

    // Ao escrever de novo, os campos deixam de estar marcados.
    await usuario.setValue('corretora2');
    [usuario, senha].forEach(campo => {
      expect(campo.attributes('aria-invalid')).toBeUndefined();
      expect(campo.attributes('aria-describedby') ?? '').not.toContain(
        erro.attributes('id')
      );
    });
  });

  it('"Entrar e trazer" ocupa a linha inteira no celular, como os demais', async () => {
    const w = await abrir({ como: 'agger' });

    expect(w.get(daCarteira('agger-entrar')).classes()).toEqual(
      expect.arrayContaining(['w-full', 'sm:w-auto'])
    );
  });

  it('o campo tem a altura dos campos da casa, e "Mostrar a senha" continua com 44 px', async () => {
    const w = await abrir({ como: 'agger' });

    expect(w.get(daCarteira('agger-usuario')).classes()).toEqual(
      expect.arrayContaining(['h-10', 'text-sm'])
    );
    expect(w.get(daCarteira('agger-mostrar-senha')).classes()).toContain(
      'size-11'
    );
  });

  it('busca seguradora por seguradora e só segue quando a pessoa toca em Continuar', async () => {
    const w = await abrir({ como: 'agger' });
    await entrarNoAgger(w, {});

    expect(w.get('h1').text()).toBe('Buscando seus seguros no Agger.');
    expect(emFoco()).toBe(w.get('h1').element);
    expect(seguradoras(w).map(([, situacao]) => situacao)).toEqual([
      'buscando',
      'buscando',
      'buscando',
      'falta_senha',
    ]);
    expect(w.find(daCarteira('agger-continuar')).exists()).toBe(false);

    await passar(UM_PASSO_DA_BUSCA_MS + 700);
    expect(seguradoras(w)[0]).toEqual([
      'Seguradora Atlântica',
      'pronta',
      '64 seguros · chegou',
    ]);

    await passar(BUSCA_INTEIRA_MS);
    expect(w.get('h1').text()).toBe('A busca no Agger terminou.');
    expect(seguradoras(w)[3]).toEqual([
      'Seguradora Aurora',
      'falta_senha',
      'falta a senha desta seguradora no seu Agger',
    ]);
    expect(w.find(daCarteira('agger-conferir')).exists()).toBe(false);

    await clicar(w, 'agger-como-resolver');
    expect(w.get(doBlocoA('titulo-do-dialogo')).text()).toBe(
      'Falta a senha da Seguradora Aurora'
    );
    // Rótulo curto: cabe inteiro ao lado de "Entendi".
    expect(w.get(daCarteira('agger-buscar-de-novo')).text()).toBe(
      'Buscar agora'
    );

    await clicar(w, 'agger-continuar');
    expect(w.get('h1').text()).toBe('Achei 156 seguros de 116 pessoas.');
    expect(contador(w, 'PRONTOS')).toBe('152 prontos');
    expect(contador(w, 'SEM_TELEFONE')).toBe('4 sem telefone');
    expect(w.get(daCarteira('sem-telefone-apoio')).text()).toBe(
      'Essas pessoas entram sem telefone. A mensagem da renovação não chega até você pôr o telefone.'
    );
    expect(w.get(daCarteira('trazer-agger')).text()).toBe('Trazer 156 seguros');
  });

  it('depois de trazer, diz que busca todo dia; não oferece "trazer mais"', async () => {
    const w = await abrir({ como: 'agger' });
    await entrarNoAgger(w, {});
    await passar(BUSCA_INTEIRA_MS);
    await clicar(w, 'agger-continuar');

    await clicar(w, 'trazer-agger');
    await passar(DURACAO_DE_TRAZER_MS);

    const pronto = w.get(daCarteira('pronto'));
    expect(pronto.get('[role="heading"]').text()).toBe(
      '156 seguros chegaram, de 116 pessoas.'
    );
    expect(pronto.text()).toContain(
      'Daqui para a frente, eu busco no Agger todo dia.'
    );
    expect(w.find(daCarteira('trazer-mais')).exists()).toBe(false);
  });

  it('conta já ligada: uma frase e um botão, sem pedir login', async () => {
    const w = await abrir({ demo: 'cheio', como: 'agger' });

    expect(w.get(`${daCarteira('agger-ligado')} h1`).text()).toBe(
      'Sua conta já está ligada ao Agger.'
    );
    expect(w.find(daCarteira('agger-senha')).exists()).toBe(false);

    await clicar(w, 'agger-trazer');
    expect(w.find(daCarteira('agger-buscando')).exists()).toBe(true);
  });

  it('o Agger não respondeu: avisa, guarda o que chegou e deixa tentar agora', async () => {
    const w = await abrir({ como: 'agger', caso: 'agger_nao_respondeu' });
    await entrarNoAgger(w, {});
    await passar(UM_PASSO_DA_BUSCA_MS + 700);

    expect(w.get(daCarteira('agger-nao-respondeu')).text()).toContain(
      'O Agger não respondeu agora. Eu tento de novo sozinho; o que já chegou fica guardado.'
    );
    await clicar(w, 'agger-tentar-agora');
    expect(w.find(daCarteira('agger-nao-respondeu')).exists()).toBe(false);
    await passar(BUSCA_INTEIRA_MS);
    expect(w.find(daCarteira('agger-continuar')).exists()).toBe(true);
  });

  it('conta do Agger sem a parte de apólices: explica e volta à escolha', async () => {
    const w = await abrir({ como: 'agger', caso: 'agger_sem_apolices' });
    await entrarNoAgger(w, {});

    expect(w.get(`${daCarteira('agger-sem-apolices')} h1`).text()).toBe(
      'Sua conta no Agger não tem a parte de apólices. Peça ao Agger para ligar e volte aqui.'
    );
    await clicar(w, 'agger-entendi');
    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { demo: 'sem-seguros', caso: 'agger_sem_apolices' },
    });
    expect(w.find(daCarteira('como-trazer')).exists()).toBe(true);
  });

  it('no histórico dá para parar de buscar todo dia, e voltar', async () => {
    const w = await abrir({ demo: 'cheio' });

    await clicar(w, 'agger-parar');
    expect(useAlert).toHaveBeenLastCalledWith(
      'Parei de buscar no Agger todo dia. O que já veio fica.'
    );
    expect(w.get(daCarteira('agger-historico')).text()).toBe(
      'não busca mais todo dia'
    );

    await clicar(w, 'agger-voltar-a-buscar');
    expect(useAlert).toHaveBeenLastCalledWith(
      'Voltei a buscar no Agger todo dia.'
    );
    expect(w.get(daCarteira('agger-historico')).text()).toContain(
      'busca todo dia'
    );
  });
});

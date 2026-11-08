import { flushPromises, mount } from '@vue/test-utils';
import AgentePostCartao from '../components/AgentePostCartao.vue';
import AgenteDoPostPage from '../pages/AgenteDoPostPage.vue';
import CriarTipoDeAgente from '../components/criar/CriarTipoDeAgente.vue';
import {
  leituraDosComentarios,
  motivosDasPortas,
  tituloDaLegenda,
} from '../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436): o cartão de um post ou anúncio em Agentes, a página dele e as gavetas, nos 4 casos (post e
// anúncio, Instagram e Facebook). O servidor manda os grupos e as portas prontos; a tela só mostra.
const api = vi.hoisted(() => ({
  list: vi.fn(),
  get: vi.fn(),
  estado: vi.fn(),
  testar: vi.fn(),
  materiais: vi.fn(),
  anexar: vi.fn(),
  tirar: vi.fn(),
}));
vi.mock('dashboard/api/agentesDoPost', () => ({ default: api }));
const fontes = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/autonomia/sources', () => ({ default: fontes }));
const seusPosts = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({ default: seusPosts }));
const desligadas = vi.hoisted(() => new Set());
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () => computed(() => (_conta, flag) => !desligadas.has(flag)),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const rota = vi.hoisted(() => ({ query: {} }));
vi.mock('vue-router', () => ({ useRoute: () => rota }));

const RouterLink = {
  props: ['to'],
  template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
};

const porta = (network, agente, extra = {}) => ({
  network,
  inbox_id: network === 'instagram' ? 10 : 20,
  private: network === 'instagram',
  motivo: agente ? null : 'sem_porta',
  agente,
  ...extra,
});
const ANA = { id: 1, name: 'Ana' };
const BIA = { id: 2, name: 'Bia' };

const detalhe = (extra = {}) => ({
  id: 7,
  kind: 'post',
  target_id: '1790',
  perfil: 'instagram-3',
  network: 'instagram',
  status: 'on',
  legenda: 'Seguro viagem para a Europa. A partir de R$ 39 por dia.',
  capa: 'https://cdn.exemplo/capa.jpg',
  foto: 'Uma mala e um avião',
  nota: 'Atendo de segunda a sexta',
  can_manage: true,
  portas: [porta('instagram', ANA)],
  comentarios: {
    status: 'ready',
    results: { sent: 4, replied: 1, skipped: 1 },
    esperando: [
      {
        id: '1',
        author: 'carla',
        text: 'E o reembolso?',
        kind: 'complaint',
        created_time: new Date(Date.now() - 3 * 3600 * 1000).toISOString(),
      },
      {
        id: '3',
        author: 'joao',
        text: 'Quanto custa?',
        kind: 'waiting',
        conversation_path: '/app/accounts/1/conversations/9',
      },
    ],
    nao_respondo: [
      { id: '2', author: 'lu', text: 'Lindo!', kind: 'skipped' },
      { id: '4', author: 'spam', text: 'Compre', kind: 'hidden' },
    ],
  },
  ...extra,
});

const montadas = [];
const montar = (componente, props) => {
  const wrapper = mount(componente, {
    props,
    attachTo: document.body,
    global: { stubs: { RouterLink, 'router-link': RouterLink } },
  });
  montadas.push(wrapper);
  return wrapper;
};
const noBody = seletor => document.body.querySelector(seletor);
const todosNoBody = seletor => [...document.body.querySelectorAll(seletor)];
const clicar = async seletor => {
  noBody(seletor).click();
  await flushPromises();
};

describe('#2469 · os comentários do post em Agentes', () => {
  beforeEach(() => {
    rota.query = {};
    Object.values(api).forEach(fn => fn.mockReset());
    fontes.get.mockResolvedValue({ data: { payload: [] } });
    api.materiais.mockResolvedValue({ data: { materiais: [] } });
  });

  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
    document.body.innerHTML = '';
  });

  describe('#2522 · leituraDosComentarios', () => {
    const lido = (esperando, networkStatus) => ({
      status: 'ready',
      esperando,
      network_status: networkStatus,
    });

    it('a rede que faltou é a que não está pronta; lista vazia com ela de fora não é zero', () => {
      const parcial = { instagram: 'ready', facebook: 'needs_login' };
      expect(leituraDosComentarios(lido([], parcial))).toEqual({
        esperando: null,
        faltou: 'facebook',
      });
      expect(leituraDosComentarios(lido([{ id: '1' }], parcial))).toEqual({
        esperando: 1,
        faltou: 'facebook',
      });
    });

    it('tudo lido: zero é zero; leitura que não ficou pronta: null', () => {
      expect(
        leituraDosComentarios(
          lido([], { instagram: 'ready', facebook: 'ready' })
        )
      ).toEqual({ esperando: 0, faltou: null });
      expect(leituraDosComentarios(lido([], undefined))).toEqual({
        esperando: 0,
        faltou: null,
      });
      expect(leituraDosComentarios({ status: 'needs_login' })).toEqual({
        esperando: null,
        faltou: null,
      });
    });
  });

  describe('o cartão', () => {
    const cartao = async (item, lido) => {
      api.get.mockResolvedValue({ data: lido });
      const wrapper = montar(AgentePostCartao, {
        cuidado: item,
        href: '/post',
        hrefEsperando: '/post?grupo=esperando',
      });
      await flushPromises();
      return wrapper;
    };

    it('post do Instagram: título da legenda, estado, quantos esperam e o agente que escreve', async () => {
      const wrapper = await cartao(
        { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        detalhe()
      );

      expect(api.get).toHaveBeenCalledWith(7);
      expect(wrapper.get('[data-cartao-titulo]').text()).toBe(
        'Seguro viagem para a Europa.'
      );
      expect(wrapper.get('[data-estado]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.ESTADO.CUIDANDO'
      );
      expect(wrapper.get('[data-tipo]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.TIPO.POST'
      );
      expect(wrapper.get('[data-esperando]').text()).toContain(
        'AGENTS.AGENTE_DO_POST.CARTAO.ESPERANDO'
      );
      expect(wrapper.findAll('[data-rede]')).toHaveLength(1);
      expect(wrapper.get('[data-usa]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.USA'
      );
    });

    it('a faixa "esperando você" abre direto o grupo, e o cartão abre a página', async () => {
      const item = { id: 7, kind: 'post', network: 'facebook', status: 'on' };
      const wrapper = await cartao(item, detalhe({ network: 'facebook' }));

      await wrapper.get('[data-esperando]').trigger('click');
      await wrapper.get('a').trigger('click');

      expect(wrapper.emitted('abrir')).toEqual([
        [item, 'esperando'],
        [item, ''],
      ]);
    });

    it('anúncio nas duas redes: os dois ícones, o selo de anúncio e os dois agentes', async () => {
      const wrapper = await cartao(
        { id: 8, kind: 'ad', network: 'both', status: 'paused' },
        detalhe({
          kind: 'ad',
          network: 'both',
          status: 'paused',
          portas: [porta('instagram', ANA), porta('facebook', BIA)],
        })
      );

      expect(
        wrapper
          .findAll('[data-rede]')
          .map(rede => rede.attributes('aria-label'))
      ).toEqual([
        'AGENTS.AGENTE_DO_POST.REDE.INSTAGRAM',
        'AGENTS.AGENTE_DO_POST.REDE.FACEBOOK',
      ]);
      expect(wrapper.get('[data-tipo]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.TIPO.AD'
      );
      expect(wrapper.get('[data-estado]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.ESTADO.PAUSADO'
      );
      expect(wrapper.get('[data-usa]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.USA_DOIS'
      );
    });

    it('anúncio com o mesmo agente nas duas redes: o nome aparece uma vez', async () => {
      const wrapper = await cartao(
        { id: 8, kind: 'ad', network: 'both', status: 'on' },
        detalhe({
          kind: 'ad',
          network: 'both',
          portas: [porta('instagram', ANA), porta('facebook', ANA)],
        })
      );

      expect(wrapper.get('[data-usa]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.USA'
      );
    });

    it('sem agente na porta: diz o motivo de verdade e que ficam as frases fixas', async () => {
      const wrapper = await cartao(
        { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        detalhe({ portas: [porta('instagram', null)] })
      );

      expect(wrapper.get('[data-usa]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.MOTIVO_DA_PORTA.sem_porta AGENTS.AGENTE_DO_POST.MOTIVO_DA_PORTA.FRASES_FIXAS'
      );
    });

    it('#2487 · o motivo da conta inteira sai uma vez só, no anúncio nas duas redes', () => {
      const t = chave => chave;
      const semChave = { motivo: 'sem_chave' };

      expect(
        motivosDasPortas(
          [porta('instagram', ANA, semChave), porta('facebook', BIA, semChave)],
          t
        )
      ).toEqual(['AGENTS.AGENTE_DO_POST.MOTIVO_DA_PORTA.sem_chave']);
    });

    it('#2487 · o motivo leva a rede e o nome da caixa', () => {
      const t = (chave, params) =>
        params ? `${chave}|${params.rede}|${params.caixa}` : chave;

      expect(
        motivosDasPortas(
          [
            porta('instagram', ANA),
            porta('facebook', null, { caixa: 'Loja (Facebook)' }),
          ],
          t
        )
      ).toEqual([
        'AGENTS.AGENTE_DO_POST.MOTIVO_DA_PORTA.sem_porta|AGENTS.AGENTE_DO_POST.REDE.FACEBOOK|Loja (Facebook)',
      ]);
    });

    it('a leitura falhou: o cartão continua, com o aviso no título', async () => {
      api.get.mockRejectedValue({ response: { status: 500 } });
      const wrapper = montar(AgentePostCartao, {
        cuidado: { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        href: '/post',
        hrefEsperando: '/post',
      });
      await flushPromises();

      expect(wrapper.get('[data-cartao-titulo]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.ERRO'
      );
    });

    it('sem acesso (403) ou fora da conta (404): o cartão diz isso, não um erro genérico', async () => {
      const item = { id: 7, kind: 'ad', network: 'both', status: 'on' };
      api.get.mockRejectedValueOnce({ response: { status: 403 } });
      const semAcesso = montar(AgentePostCartao, {
        cuidado: item,
        href: '/a',
        hrefEsperando: '/a',
      });
      await flushPromises();
      api.get.mockRejectedValueOnce({ response: { status: 404 } });
      const sumiu = montar(AgentePostCartao, {
        cuidado: { ...item, id: 8 },
        href: '/a',
        hrefEsperando: '/a',
      });
      await flushPromises();

      expect(semAcesso.get('[data-cartao-titulo]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.SEM_ACESSO'
      );
      expect(sumiu.get('[data-cartao-titulo]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.SUMIU'
      );
      expect(sumiu.find('[data-sem-leitura]').exists()).toBe(true);
    });

    it('a Meta não deixou ler os comentários: a faixa diz que não leu, nunca "nenhum esperando"', async () => {
      const wrapper = await cartao(
        { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        detalhe({
          comentarios: {
            status: 'needs_permission',
            results: { sent: 0 },
            esperando: [],
            nao_respondo: [],
          },
        })
      );

      expect(wrapper.get('[data-esperando]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.SEM_LEITURA'
      );
    });

    // #2522: anúncio nas duas redes com o Facebook sem login. Lista vazia: não leu (os do Facebook podem estar
    // esperando), nunca "nenhum esperando". Com itens: o número. Nos dois, a rede que ficou de fora.
    it.each([
      ['vazia', [], 'AGENTS.AGENTE_DO_POST.CARTAO.SEM_LEITURA', false],
      ['com itens', [{ id: '1', kind: 'waiting' }], 'CARTAO.ESPERANDO', true],
    ])(
      'anúncio com o Facebook sem login, lista %s: sem zero falso',
      async (_nome, lista, texto, temNumero) => {
        const wrapper = await cartao(
          { id: 7, kind: 'ad', network: 'both', status: 'on' },
          detalhe({
            kind: 'ad',
            network: 'both',
            comentarios: {
              ...detalhe().comentarios,
              esperando: lista,
              network_status: { instagram: 'ready', facebook: 'needs_login' },
            },
          })
        );

        const faixa = wrapper.get('[data-esperando]');
        expect(faixa.text()).toContain(texto);
        expect(faixa.find('[data-sem-leitura]').exists()).toBe(!temNumero);
        expect(faixa.get('[data-faltou-rede]').text()).toContain(
          'AGENTS.AGENTE_DO_POST.CARTAO.FALTOU_REDE'
        );
      }
    );

    it('o cartão só lê quando aparece na tela', async () => {
      const observados = [];
      vi.stubGlobal(
        'IntersectionObserver',
        vi.fn(aviso => {
          const observador = { aviso, observe: vi.fn(), disconnect: vi.fn() };
          observados.push(observador);
          return observador;
        })
      );
      api.get.mockResolvedValue({ data: detalhe() });
      const wrapper = montar(AgentePostCartao, {
        cuidado: { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        href: '/post',
        hrefEsperando: '/post',
      });
      await flushPromises();
      expect(api.get).not.toHaveBeenCalled();

      observados[0].aviso([{ isIntersecting: true }]);
      await flushPromises();
      expect(api.get).toHaveBeenCalledWith(7);
      expect(wrapper.get('[data-cartao-titulo]').text()).toBe(
        'Seguro viagem para a Europa.'
      );
      vi.unstubAllGlobals();
    });

    it('muitos cartões: no máximo 3 leituras na Meta ao mesmo tempo', async () => {
      const pendentes = [];
      api.get.mockImplementation(
        () =>
          new Promise(resolve => {
            pendentes.push(resolve);
          })
      );
      [1, 2, 3, 4, 5].forEach(id =>
        montar(AgentePostCartao, {
          cuidado: { id, kind: 'post', network: 'instagram', status: 'on' },
          href: '/post',
          hrefEsperando: '/post',
        })
      );
      await flushPromises();
      expect(api.get).toHaveBeenCalledTimes(3);

      pendentes.shift()({ data: detalhe() });
      await flushPromises();
      expect(api.get).toHaveBeenCalledTimes(4);

      while (pendentes.length) {
        pendentes.shift()({ data: detalhe() });
        // eslint-disable-next-line no-await-in-loop
        await flushPromises();
      }
      expect(api.get).toHaveBeenCalledTimes(5);
    });

    it('o título corta só em fim de frase: "R$ 39.90" não corta', () => {
      expect(
        tituloDaLegenda('A partir de R$ 39.90 por dia. Fale comigo')
      ).toEqual({
        titulo: 'A partir de R$ 39.90 por dia.',
        resto: 'Fale comigo',
      });
      expect(tituloDaLegenda('Promo!')).toEqual({
        titulo: 'Promo!',
        resto: '',
      });
    });
  });

  describe('a página', () => {
    const pagina = async lido => {
      api.get.mockResolvedValue({ data: lido });
      const wrapper = montar(AgenteDoPostPage, { careId: '7' });
      await flushPromises();
      return wrapper;
    };

    // #2522: a página, o mesmo caso do cartão. Lista vazia com o Facebook de fora: não leu; com itens: o número. Nos
    // dois, a rede que faltou.
    it.each([
      ['vazia', [], 'AGENTS.AGENTE_DO_POST.CARTAO.SEM_LEITURA', false],
      ['com itens', [{ id: '1', kind: 'waiting' }], 'CARTAO.ESPERANDO', true],
    ])(
      'anúncio com o Facebook sem login, lista %s: a página sem zero falso',
      async (_nome, lista, texto, temNumero) => {
        const wrapper = await pagina(
          detalhe({
            kind: 'ad',
            network: 'both',
            comentarios: {
              ...detalhe().comentarios,
              esperando: lista,
              network_status: { instagram: 'ready', facebook: 'needs_login' },
            },
          })
        );

        const botao = wrapper.get('[data-esperando]');
        expect(botao.text()).toContain(texto);
        expect(botao.text().includes('CARTAO.SEM_LEITURA')).toBe(!temNumero);
        expect(botao.find('[data-faltou-rede]').exists()).toBe(true);
      }
    );

    it('pausar e voltar a cuidar pelo servidor; quem só vê não tem os controles nem o Testar', async () => {
      const wrapper = await pagina(detalhe());
      api.estado.mockResolvedValue({ data: detalhe({ status: 'paused' }) });

      await wrapper.get('[data-mudar-estado]').trigger('click');
      await flushPromises();

      expect(api.estado).toHaveBeenCalledWith('7', 'paused');
      expect(wrapper.get('[data-mudar-estado]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.PAGINA.RETOMAR'
      );

      const soVe = await pagina(detalhe({ can_manage: false }));
      expect(soVe.find('[data-mudar-estado]').exists()).toBe(false);
      expect(soVe.find('[data-editar]').exists()).toBe(false);
      expect(soVe.find('[data-abrir-gaveta="testar"]').exists()).toBe(false);
    });

    // #2520: o cuidado aparece sem seus_posts_comentarios, mas o post por dentro pede a flag: sem ela, nada leva lá.
    it('sem seus_posts_comentarios: o post fica sem "Ver post" e sem "Ver todos"; o anúncio mantém os dois', async () => {
      desligadas.add('seus_posts_comentarios');
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      try {
        await pagina(detalhe());
        expect(noBody('[data-ver-post]')).toBeNull();
        expect(noBody('[data-ver-todos]')).toBeNull();
        expect(todosNoBody('[data-comentario]').length).toBe(2);
        montadas.splice(0).forEach(wrapper => wrapper.unmount());

        await pagina(detalhe({ kind: 'ad', target_id: '1202', perfil: null }));
        expect(noBody('[data-ver-post]')).not.toBeNull();
        expect(noBody('[data-ver-todos]')).not.toBeNull();
      } finally {
        desligadas.clear();
        rota.query = {};
      }
    });

    it('editar leva aos passos do cuidado: o post no Seus posts, o anúncio em Anúncios', async () => {
      const post = await pagina(detalhe());
      expect(
        JSON.parse(post.get('[data-editar]').attributes('data-to'))
      ).toEqual({
        name: 'seus_posts_cuidar',
        params: { postId: '1790' },
        query: { perfil: 'instagram-3' },
      });

      const anuncio = await pagina(
        detalhe({ kind: 'ad', target_id: '1202', perfil: null })
      );
      expect(
        JSON.parse(anuncio.get('[data-editar]').attributes('data-to'))
      ).toEqual({
        name: 'campaigns_meta_ads_cuidar',
        params: { adId: '1202' },
      });
    });

    it('pausar que falha avisa e não muda a tela', async () => {
      const wrapper = await pagina(detalhe());
      api.estado.mockRejectedValue(new Error('500'));

      await wrapper.get('[data-mudar-estado]').trigger('click');
      await flushPromises();

      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.AGENTE_DO_POST.PAGINA.ERRO_MUDAR'
      );
      expect(wrapper.get('[data-mudar-estado]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.PAGINA.PAUSAR'
      );
    });

    it('anúncio cuja caixa a pessoa não vê: diz o porquê', async () => {
      api.get.mockRejectedValue({
        response: { status: 403, data: { error: 'not_inbox_member' } },
      });
      const wrapper = montar(AgenteDoPostPage, { careId: '7' });
      await flushPromises();

      expect(wrapper.get('[data-post-estado]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.PAGINA.NAO_VE_CAIXA'
      );
    });

    it('Comentários: os grupos do servidor, com o número de cada um e o motivo de cada comentário', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      await pagina(detalhe());

      const numeros = todosNoBody('[data-grupo]').map(grupo =>
        grupo.querySelector('span').textContent.trim()
      );
      expect(numeros).toEqual(['4', '2', '2']);
      expect(
        todosNoBody('[data-comentario]').map(item => item.dataset.comentario)
      ).toEqual(['1', '3']);
      expect(noBody('[data-comentario="1"]').textContent).toContain(
        'META_ADS_COMMENTS_AI.ON.KIND.complaint'
      );
      // #2519: há quanto tempo a pessoa espera; sem a hora, nada.
      expect(
        noBody('[data-comentario="1"] [data-quando]').textContent
      ).toContain('3');
      expect(noBody('[data-comentario="3"] [data-quando]')).toBeNull();
      expect(noBody('[data-ver-conversa]').getAttribute('href')).toBe(
        '/app/accounts/1/conversations/9'
      );

      await clicar('[data-grupo="nao_respondo"]');
      expect(
        todosNoBody('[data-comentario]').map(item => item.dataset.comentario)
      ).toEqual(['2', '4']);
    });

    it('#2481 · Comentários "no privado": quem recebeu, o comentário, se respondeu e o "Ver conversa" de quem a pessoa vê', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'respondidos' };
      await pagina(
        detalhe({
          comentarios: {
            ...detalhe().comentarios,
            no_privado: [
              {
                id: 21,
                contato: 'Mariana',
                comentario: 'Comentou no post: “Quanto custa?”',
                respondeu: true,
                conversation_path: '/app/accounts/1/conversations/21',
              },
              { id: 20, contato: 'Rafael', comentario: 'Qual o valor?' },
            ],
          },
        })
      );

      expect(
        todosNoBody('[data-no-privado-conversa]').map(
          item => item.dataset.noPrivadoConversa
        )
      ).toEqual(['21', '20']);
      const mariana = noBody('[data-no-privado-conversa="21"]');
      expect(mariana.textContent).toContain('Mariana');
      expect(mariana.textContent).toContain('Quanto custa?');
      expect(mariana.querySelector('[data-respondeu]')).not.toBeNull();
      expect(
        mariana.querySelector('[data-ver-conversa]').getAttribute('href')
      ).toBe('/app/accounts/1/conversations/21');
      const rafael = noBody('[data-no-privado-conversa="20"]');
      expect(rafael.querySelector('[data-respondeu]')).toBeNull();
      expect(rafael.querySelector('[data-ver-conversa]')).toBeNull();
    });

    it('#2481 · "no privado" vazio diz que não há nada', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'respondidos' };
      await pagina(detalhe());

      expect(noBody('[data-respondidos] [data-nenhum]')).not.toBeNull();
    });

    // #2522: anúncio nas duas redes com uma só lida: os números da rede que leu e o aviso da que faltou, sem
    // "tentar de novo" (a gaveta não relê).
    it('Comentários do anúncio com o Facebook sem login: a lista do Instagram e o aviso do Facebook', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      const base = detalhe().comentarios;
      await pagina(
        detalhe({
          kind: 'ad',
          network: 'both',
          comentarios: {
            ...base,
            network_status: { instagram: 'ready', facebook: 'needs_login' },
          },
        })
      );

      const avisos = todosNoBody(
        '[data-gaveta-comentarios] [data-ia-rede-faltou]'
      );
      expect(avisos.map(aviso => aviso.dataset.network)).toEqual(['facebook']);
      expect(avisos[0].querySelector('button')).toBeNull();
      expect(noBody('[data-sem-leitura]')).toBeNull();
      expect(todosNoBody('[data-lista] [data-comentario]')).toHaveLength(2);
    });

    it('Comentários do anúncio com uma rede faltando, em "Respondidos": sem aviso (o número vem do banco)', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'respondidos' };
      const base = detalhe().comentarios;
      await pagina(
        detalhe({
          kind: 'ad',
          network: 'both',
          comentarios: {
            ...base,
            network_status: { instagram: 'ready', facebook: 'needs_login' },
          },
        })
      );

      expect(noBody('[data-respondidos]')).not.toBeNull();
      expect(noBody('[data-ia-rede-faltou]')).toBeNull();
    });

    it('Comentários do anúncio, "Esperando" vazio com o Facebook sem login: sem número e sem "nada aqui"', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      const base = detalhe().comentarios;
      await pagina(
        detalhe({
          kind: 'ad',
          network: 'both',
          comentarios: {
            ...base,
            esperando: [],
            network_status: { instagram: 'ready', facebook: 'needs_login' },
          },
        })
      );

      const numeros = todosNoBody('[data-gaveta-comentarios] [data-grupo]').map(
        grupo => grupo.querySelector('span').textContent.trim()
      );
      expect(numeros).toEqual(['4', '–', '2']);
      expect(
        noBody('[data-gaveta-comentarios] [data-sem-leitura]')
      ).not.toBeNull();
      expect(noBody('[data-gaveta-comentarios] [data-nenhum]')).toBeNull();
    });

    it('Comentários com as duas redes lidas: sem aviso', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      const base = detalhe().comentarios;
      await pagina(
        detalhe({
          comentarios: { ...base, network_status: { instagram: 'ready' } },
        })
      );

      expect(noBody('[data-ia-rede-faltou]')).toBeNull();
    });

    it('Comentários sem leitura da Meta: esperando e não respondo sem número, com o aviso', async () => {
      rota.query = { gaveta: 'comentarios', grupo: 'esperando' };
      await pagina(
        detalhe({
          comentarios: {
            status: 'meta_unavailable',
            results: { sent: 4 },
            esperando: [],
            nao_respondo: [],
          },
        })
      );

      const numeros = todosNoBody('[data-grupo]').map(grupo =>
        grupo.querySelector('span').textContent.trim()
      );
      expect(numeros).toEqual(['4', '–', '–']);
      expect(noBody('[data-sem-leitura]').textContent).toContain(
        'AGENTS.AGENTE_DO_POST.COMENTARIOS.SEM_LEITURA'
      );
      expect(noBody('[data-nenhum]')).toBeNull();
      expect(noBody('[data-esperando]').textContent).toContain(
        'AGENTS.AGENTE_DO_POST.CARTAO.SEM_LEITURA'
      );
    });

    it('O que sabe: os materiais de cada agente da porta e o que é só do post', async () => {
      rota.query = { gaveta: 'sabe' };
      fontes.get.mockResolvedValue({
        data: {
          payload: [{ id: 5, name: 'Tabela de preços', status: 'ready' }],
        },
      });
      await pagina(
        detalhe({
          kind: 'ad',
          network: 'both',
          portas: [porta('instagram', ANA), porta('facebook', BIA)],
        })
      );

      expect(fontes.get.mock.calls).toEqual([[1], [2]]);
      expect(todosNoBody('[data-materiais]')).toHaveLength(2);
      expect(noBody('[data-o-que-vi]').textContent).toContain(
        'Uma mala e um avião'
      );
      expect(noBody('[data-nota]').textContent).toContain(
        'Atendo de segunda a sexta'
      );
    });

    describe('#2487 · o material só do post', () => {
      const TABELA = {
        id: 31,
        reference: 'Tabela.txt',
        source_type: 'txt',
        status: 'ready',
        agente: 'Ana',
        review: { status: 'accepted', reviewed_at: '2026-11-02T10:00:00Z' },
      };
      const arquivo = new File(['P, M e G'], 'Tabela.txt', {
        type: 'text/plain',
      });
      const escolher = async () => {
        const seletor = noBody('[data-anexar-arquivo]');
        Object.defineProperty(seletor, 'files', { value: [arquivo] });
        seletor.dispatchEvent(new Event('change'));
        await flushPromises();
      };

      it('lista o que é só deste post e anexa um arquivo para ler', async () => {
        rota.query = { gaveta: 'sabe' };
        api.materiais
          .mockResolvedValueOnce({ data: { materiais: [] } })
          .mockResolvedValue({ data: { materiais: [TABELA] } });
        api.anexar.mockResolvedValue({ data: TABELA });
        await pagina(detalhe());

        expect(api.materiais).toHaveBeenCalledWith(7);
        expect(noBody('[data-materiais-do-post]')).toBeNull();
        await escolher();

        expect(api.anexar).toHaveBeenCalledWith(7, arquivo);
        expect(noBody('[data-materiais-do-post]').textContent).toContain(
          'Tabela.txt'
        );
        expect(noBody('[data-material-erro]')).toBeNull();
      });

      it('sem agente na caixa, diz que ninguém lê o arquivo', async () => {
        rota.query = { gaveta: 'sabe' };
        api.anexar.mockRejectedValue({
          response: { data: { error: 'no_agent' } },
        });
        await pagina(detalhe());

        await escolher();

        expect(noBody('[data-material-erro]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.SABE.MATERIAL.SEM_AGENTE'
        );
      });

      it('quem só vê tem a lista, sem anexar', async () => {
        rota.query = { gaveta: 'sabe' };
        api.materiais.mockResolvedValue({ data: { materiais: [TABELA] } });
        await pagina(detalhe({ can_manage: false }));

        expect(noBody('[data-materiais-do-post]').textContent).toContain(
          'Tabela.txt'
        );
        expect(noBody('[data-anexar]')).toBeNull();
      });

      it('sem agente e com motivo: a página não mostra a faixa "Usa o que … sabe" vazia', async () => {
        await pagina(detalhe({ portas: [porta('instagram', null)] }));

        expect(noBody('[data-motivos-das-portas]')).not.toBeNull();
        expect(noBody('[data-usa]')).toBeNull();
      });

      it('agente parado na porta: a página diz o motivo de verdade', async () => {
        await pagina(
          detalhe({
            portas: [porta('instagram', ANA, { motivo: 'porta_parada' })],
          })
        );

        expect(noBody('[data-motivos-das-portas]').textContent).toContain(
          'MOTIVO_DA_PORTA.porta_parada'
        );
      });

      it('a resposta do Testar diz de que arquivo dele saiu', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());
        api.testar.mockResolvedValue({
          data: {
            status: 'ready',
            decisao: 'private',
            escrita: {
              status: 'escrito',
              privado: 'Temos P, M e G!',
              publico: 'Te mandei no direct!',
              material: ['Tabela.txt'],
            },
          },
        });

        const campo = noBody('[data-testar-pergunta]');
        campo.value = 'Tem G?';
        campo.dispatchEvent(new Event('input'));
        await flushPromises();
        await clicar('[data-testar-perguntar]');

        expect(noBody('[data-resposta-material]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.DO_MATERIAL'
        );
      });
    });

    it('O que sabe com agente parado na porta: o motivo, sem "Criar um agente"', async () => {
      rota.query = { gaveta: 'sabe' };
      await pagina(
        detalhe({
          portas: [porta('instagram', ANA, { motivo: 'porta_parada' })],
        })
      );

      expect(noBody('[data-motivo-da-porta]').textContent).toContain(
        'MOTIVO_DA_PORTA.porta_parada'
      );
      expect(noBody('[data-criar-agente]')).toBeNull();
    });

    it('O que sabe sem agente na porta: as frases fixas e o caminho para criar um', async () => {
      rota.query = { gaveta: 'sabe' };
      await pagina(detalhe({ portas: [porta('instagram', null)] }));

      expect(noBody('[data-sem-porta]')).not.toBeNull();
      expect(noBody('[data-criar-agente]')).not.toBeNull();
      expect(noBody('[data-motivo-da-porta]').textContent).toContain(
        'MOTIVO_DA_PORTA.sem_porta'
      );
      expect(fontes.get).not.toHaveBeenCalled();
    });

    describe('Testar', () => {
      const perguntar = async texto => {
        const campo = noBody('[data-testar-pergunta]');
        campo.value = texto;
        campo.dispatchEvent(new Event('input'));
        await flushPromises();
        await clicar('[data-testar-perguntar]');
      };

      const decidiu = (decisao, extra = {}) => ({
        data: {
          status: 'ready',
          decisao,
          motivo: 'Pergunta o preço.',
          ...extra,
        },
      });

      it('#2510 · post do Instagram: a decisão vem primeiro, com o porquê, e depois o privado e a frase do comentário', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());
        api.testar.mockResolvedValue(
          decidiu('price', {
            escrita: {
              status: 'escrito',
              privado: 'O seguro sai R$ 39 por dia.',
              publico: 'Te mandei no direct!',
            },
          })
        );

        expect(noBody('[data-testar-formato]')).toBeNull();
        await perguntar(' Quanto custa? ');

        expect(api.testar).toHaveBeenCalledWith('7', {
          pergunta: 'Quanto custa?',
          network: 'instagram',
        });
        expect(noBody('[data-decisao="price"]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.DECISAO.price'
        );
        expect(noBody('[data-decisao-motivo]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.POR_QUE'
        );
        expect(noBody('[data-resposta-privado]').textContent).toContain(
          'O seguro sai R$ 39 por dia.'
        );
        expect(noBody('[data-resposta-comentario]').textContent).toContain(
          'Te mandei no direct!'
        );
      });

      it('#2510 · o caso do 03/11: "Cobre bagagem?" com o "para quem" de preço não é respondido, e nenhum texto aparece', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());
        api.testar.mockResolvedValue(decidiu('no_reply'));

        await perguntar('Cobre bagagem?');

        expect(noBody('[data-decisao="no_reply"]')).not.toBeNull();
        expect(noBody('[data-resposta-privado]')).toBeNull();
        expect(noBody('[data-resposta-comentario]')).toBeNull();
      });

      it('#2510 · cada decisão que não responde aparece como tal: reclamação, assunto do dono, escondo, sem certeza', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());

        await ['to_you', 'owner_topic', 'hide', 'sem_certeza'].reduce(
          async (anterior, decisao) => {
            await anterior;
            api.testar.mockResolvedValueOnce(decidiu(decisao));
            await perguntar('Oi');
            expect(noBody(`[data-decisao="${decisao}"]`).textContent).toContain(
              `AGENTS.AGENTE_DO_POST.TESTAR.DECISAO.${decisao}`
            );
            expect(noBody('[data-resposta-privado]')).toBeNull();
          },
          Promise.resolve()
        );
      });

      it('anúncio nas duas redes: o dono escolhe a rede antes de perguntar; no Facebook o privado não sai', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(
          detalhe({
            kind: 'ad',
            network: 'both',
            portas: [porta('instagram', ANA), porta('facebook', BIA)],
          })
        );
        api.testar.mockResolvedValue(decidiu('no_private'));

        await perguntar('Quanto custa?');
        expect(api.testar).not.toHaveBeenCalled();

        await clicar('[data-testar-rede="facebook"]');
        await clicar('[data-testar-perguntar]');
        expect(api.testar).toHaveBeenCalledWith('7', {
          pergunta: 'Quanto custa?',
          network: 'facebook',
        });
        expect(noBody('[data-decisao="no_private"]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.DECISAO.no_private'
        );
        expect(noBody('[data-resposta-privado]')).toBeNull();
      });

      it('o agente não sabe: "Fica com você"; sem agente, as frases fixas com o motivo; IA fora do ar e sem chave avisam', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());

        api.testar.mockResolvedValueOnce(
          decidiu('private', {
            escrita: { status: 'fica_com_o_dono', motivo: 'no_knowledge' },
          })
        );
        await perguntar('Tem para Marte?');
        expect(noBody('[data-decisao="nao_sei"]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.DECISAO.nao_sei'
        );
        expect(noBody('[data-decisao="private"]')).toBeNull();
        expect(noBody('[data-resposta-privado]')).toBeNull();

        api.testar.mockResolvedValueOnce(
          decidiu('private', {
            escrita: {
              status: 'frases_fixas',
              motivo: 'sem_porta',
              privado: 'Oi! Te mandei os valores.',
              publico: 'Te chamei no direct 😊',
            },
          })
        );
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-privado]').textContent).toContain(
          'Oi! Te mandei os valores.'
        );
        expect(noBody('[data-resposta-frases-fixas]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.MOTIVO.sem_porta'
        );

        api.testar.mockRejectedValueOnce({
          response: { status: 422, data: { error: 'ai_unavailable' } },
        });
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.IA_FORA'
        );

        api.testar.mockRejectedValueOnce({
          response: { status: 422, data: { error: 'no_credential' } },
        });
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.MOTIVO.sem_chave'
        );

        api.testar.mockRejectedValueOnce({
          response: { status: 422, data: { error: 'ai_disabled' } },
        });
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.ERRO'
        );
      });
    });
  });

  describe('criar agente', () => {
    it('pergunta o tipo; "Cuidar dos comentários" lista os posts do perfil e leva ao post escolhido', async () => {
      seusPosts.get.mockResolvedValue({
        data: {
          perfis: [
            { id: 'instagram-3', network: 'instagram', name: 'loja' },
            { id: 'facebook-4', network: 'facebook', name: 'Loja' },
          ],
          perfil: {
            id: 'instagram-3',
            network: 'instagram',
            posts: [
              {
                id: '1790',
                text: 'Seguro viagem.',
                image_url: 'x',
                comments: 3,
              },
            ],
          },
        },
      });
      const wrapper = montar(CriarTipoDeAgente, {});

      await clicar('[data-criar-tipo="post"]');
      expect(seusPosts.get).toHaveBeenCalledWith({
        perfil: undefined,
        days: 30,
      });
      expect(todosNoBody('[data-criar-perfil]')).toHaveLength(2);

      await clicar('[data-criar-post="1790"]');
      expect(wrapper.emitted('post')).toEqual([
        [{ id: '1790', perfil: 'instagram-3' }],
      ]);

      expect(noBody('[data-criar-fontes]')).toBeNull();
    });

    it('"Atender conversas" segue a criação de hoje', async () => {
      const wrapper = montar(CriarTipoDeAgente, {});

      await clicar('[data-criar-tipo="atender"]');

      expect(wrapper.emitted('atender')).toHaveLength(1);
    });
  });
});

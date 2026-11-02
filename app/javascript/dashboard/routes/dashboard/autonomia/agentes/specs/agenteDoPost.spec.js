import { flushPromises, mount } from '@vue/test-utils';
import AgentePostCartao from '../components/AgentePostCartao.vue';
import AgenteDoPostPage from '../pages/AgenteDoPostPage.vue';
import CriarTipoDeAgente from '../components/criar/CriarTipoDeAgente.vue';
import { tituloDaLegenda } from '../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436): o cartão de um post ou anúncio em Agentes, a página dele e as gavetas, nos 4 casos (post e
// anúncio, Instagram e Facebook). O servidor manda os grupos e as portas prontos; a tela só mostra.
const api = vi.hoisted(() => ({
  list: vi.fn(),
  get: vi.fn(),
  estado: vi.fn(),
  testar: vi.fn(),
}));
vi.mock('dashboard/api/agentesDoPost', () => ({ default: api }));
const fontes = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/autonomia/sources', () => ({ default: fontes }));
const seusPosts = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({ default: seusPosts }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => () => true) };
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
      { id: '1', author: 'carla', text: 'E o reembolso?', kind: 'complaint' },
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
  });

  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
    document.body.innerHTML = '';
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

    it('sem agente na porta: diz que ficam as frases fixas', async () => {
      const wrapper = await cartao(
        { id: 7, kind: 'post', network: 'instagram', status: 'on' },
        detalhe({ portas: [porta('instagram', null)] })
      );

      expect(wrapper.get('[data-usa]').text()).toBe(
        'AGENTS.AGENTE_DO_POST.CARTAO.SEM_PORTA'
      );
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
      expect(noBody('[data-ver-conversa]').getAttribute('href')).toBe(
        '/app/accounts/1/conversations/9'
      );

      await clicar('[data-grupo="nao_respondo"]');
      expect(
        todosNoBody('[data-comentario]').map(item => item.dataset.comentario)
      ).toEqual(['2', '4']);
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

    it('O que sabe sem agente na porta: as frases fixas e o caminho para criar um', async () => {
      rota.query = { gaveta: 'sabe' };
      await pagina(detalhe({ portas: [porta('instagram', null)] }));

      expect(noBody('[data-sem-porta]')).not.toBeNull();
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

      it('post do Instagram: a rede já vem escolhida, e o privado escrito aparece como privado', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());
        api.testar.mockResolvedValue({
          data: { status: 'escrito', texto: 'Te mandei no direct!' },
        });

        await clicar('[data-testar-formato="privado"]');
        await perguntar(' Quanto custa? ');

        expect(api.testar).toHaveBeenCalledWith('7', {
          pergunta: 'Quanto custa?',
          formato: 'privado',
          network: 'instagram',
        });
        expect(noBody('[data-resposta-privado]').textContent).toContain(
          'Te mandei no direct!'
        );
      });

      it('anúncio nas duas redes: o dono escolhe a rede antes de perguntar', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(
          detalhe({
            kind: 'ad',
            network: 'both',
            portas: [porta('instagram', ANA), porta('facebook', BIA)],
          })
        );
        api.testar.mockResolvedValue({
          data: { status: 'escrito', texto: 'Oi!' },
        });

        await perguntar('Quanto custa?');
        expect(api.testar).not.toHaveBeenCalled();

        await clicar('[data-testar-rede="facebook"]');
        await clicar('[data-testar-perguntar]');
        expect(api.testar).toHaveBeenCalledWith('7', {
          pergunta: 'Quanto custa?',
          formato: 'publico',
          network: 'facebook',
        });
        expect(noBody('[data-resposta-comentario]').textContent).toContain(
          'Oi!'
        );
      });

      it('o privado do Facebook não sai: diz isso, sem balão de privado', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(
          detalhe({ network: 'facebook', portas: [porta('facebook', BIA)] })
        );
        api.testar.mockResolvedValue({ data: { status: 'no_private' } });

        await clicar('[data-testar-formato="privado"]');
        await perguntar('Quanto custa?');

        expect(noBody('[data-resposta-privado]')).toBeNull();
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.SEM_PRIVADO'
        );
      });

      it('o agente não sabe: "Fica com você"; sem agente, as frases fixas com o motivo; IA fora do ar avisa', async () => {
        rota.query = { gaveta: 'testar' };
        await pagina(detalhe());

        api.testar.mockResolvedValueOnce({
          data: { status: 'fica_com_o_dono', motivo: 'no_knowledge' },
        });
        await perguntar('Tem para Marte?');
        expect(noBody('[data-resposta-fica]')).not.toBeNull();

        api.testar.mockResolvedValueOnce({
          data: { status: 'frases_fixas', motivo: 'sem_chave' },
        });
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.MOTIVO.sem_chave'
        );

        api.testar.mockRejectedValueOnce({
          response: { status: 422, data: { error: 'ai_unavailable' } },
        });
        await perguntar('Quanto custa?');
        expect(noBody('[data-resposta-aviso]').textContent).toContain(
          'AGENTS.AGENTE_DO_POST.TESTAR.IA_FORA'
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

      await clicar('[data-criar-anuncio]');
      expect(wrapper.emitted('anuncio')).toHaveLength(1);
    });

    it('"Atender conversas" segue a criação de hoje', async () => {
      const wrapper = montar(CriarTipoDeAgente, {});

      await clicar('[data-criar-tipo="atender"]');

      expect(wrapper.emitted('atender')).toHaveLength(1);
    });
  });
});

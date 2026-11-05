import { flushPromises, mount } from '@vue/test-utils';
import CriarTipoDeAgente from '../components/criar/CriarTipoDeAgente.vue';

// #2479: o "Qual post?" de "Criar agente" em Agentes também lista os anúncios (chip "Posts | Anúncios"). A lista dos
// anúncios vem do servidor, só do banco; escolher um leva ao cuidado dele. Dados sintéticos.
const api = vi.hoisted(() => ({ anuncios: vi.fn() }));
vi.mock('dashboard/api/agentesDoPost', () => ({ default: api }));
const seusPosts = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({ default: seusPosts }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => () => true) };
});

const POSTS = {
  data: {
    perfis: [{ id: 'instagram-3', network: 'instagram', name: 'loja' }],
    perfil: {
      id: 'instagram-3',
      network: 'instagram',
      posts: [{ id: '1790', text: 'Seguro viagem.', image_url: null }],
    },
  },
};
const ANUNCIOS = {
  data: {
    anuncios: [
      { id: '120', name: 'Seguro viagem', image_url: '/foto.jpg', care: null },
      { id: '121', name: null, image_url: null, care: 'on' },
      { id: '122', name: 'Auto', image_url: null, care: 'paused' },
    ],
  },
};
const falha = (status, error) =>
  Object.assign(new Error('x'), { response: { status, data: { error } } });

const montadas = [];
const montar = props => {
  const wrapper = mount(CriarTipoDeAgente, { props, attachTo: document.body });
  montadas.push(wrapper);
  return wrapper;
};
const noBody = seletor => document.body.querySelector(seletor);
const todosNoBody = seletor => [...document.body.querySelectorAll(seletor)];
const clicar = async seletor => {
  noBody(seletor).click();
  await flushPromises();
};

describe('#2479 · anúncios no "Qual post?"', () => {
  beforeEach(() => {
    api.anuncios.mockReset();
    seusPosts.get.mockReset();
    seusPosts.get.mockResolvedValue(POSTS);
    api.anuncios.mockResolvedValue(ANUNCIOS);
  });

  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
    document.body.innerHTML = '';
  });

  it('com posts e anúncios: o chip troca a lista; o anúncio escolhido leva ao cuidado dele', async () => {
    const wrapper = montar({ comPosts: true, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');
    expect(noBody('[data-criar-fonte="posts"]').ariaPressed).toBe('true');
    expect(noBody('[data-criar-post="1790"]')).not.toBeNull();
    expect(api.anuncios).not.toHaveBeenCalled();

    await clicar('[data-criar-fonte="anuncios"]');
    expect(api.anuncios).toHaveBeenCalledTimes(1);
    expect(noBody('[data-criar-fonte="anuncios"]').ariaPressed).toBe('true');
    expect(noBody('[data-criar-post="1790"]')).toBeNull();
    expect(todosNoBody('[data-criar-anuncio]')).toHaveLength(3);

    await clicar('[data-criar-anuncio="120"]');
    expect(wrapper.emitted('anuncio')).toEqual([[{ id: '120' }]]);
  });

  it('o anúncio sem nome mostra o número; o já cuidado diz o estado do cuidado', async () => {
    montar({ comPosts: false, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');

    expect(noBody('[data-criar-fontes]')).toBeNull();
    expect(noBody('[data-criar-anuncio="121"]').textContent).toContain(
      'AGENTS.AGENTE_DO_POST.CRIAR.ANUNCIOS.SEM_NOME'
    );
    expect(noBody('[data-criar-anuncio-estado="on"]').textContent).toContain(
      'AGENTS.AGENTE_DO_POST.CRIAR.ANUNCIOS.CUIDANDO'
    );
    expect(
      noBody('[data-criar-anuncio-estado="paused"]').textContent
    ).toContain('AGENTS.AGENTE_DO_POST.CRIAR.ANUNCIOS.PAUSADO');
    expect(noBody('[data-criar-anuncio="120"] img')).not.toBeNull();
    expect(seusPosts.get).not.toHaveBeenCalled();
  });

  // #2519 (3A): o servidor já manda primeiro os que esperam; a tela só diz quantos.
  it('o anúncio com comentário esperando diz quantos; sem espera, nada', async () => {
    api.anuncios.mockResolvedValue({
      data: {
        anuncios: [
          { id: '130', name: 'Antigo', care: null, waiting: 3 },
          { id: '120', name: 'Seguro', care: null, waiting: 0 },
        ],
      },
    });
    montar({ comPosts: false, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');

    const esperando = todosNoBody('[data-criar-anuncio-esperando]');
    expect(esperando).toHaveLength(1);
    expect(
      noBody('[data-criar-anuncio="130"] [data-criar-anuncio-esperando]')
        .textContent
    ).toContain('AGENTS.AGENTE_DO_POST.CRIAR.ANUNCIOS.ESPERANDO');
    expect(
      noBody('[data-criar-anuncio="120"] [data-criar-anuncio-esperando]')
    ).toBeNull();
  });

  it('só posts: sem chip e sem ler os anúncios', async () => {
    montar({ comPosts: true, comAnuncios: false });

    await clicar('[data-criar-tipo="post"]');

    expect(noBody('[data-criar-fontes]')).toBeNull();
    expect(api.anuncios).not.toHaveBeenCalled();
  });

  it('nenhum anúncio nos últimos 30 dias: diz isso', async () => {
    api.anuncios.mockResolvedValue({ data: { anuncios: [] } });
    montar({ comPosts: false, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');

    expect(noBody('[data-criar-sem-anuncios]')).not.toBeNull();
  });

  it.each([
    [falha(404, 'not_connected'), 'SEM_CONEXAO'],
    [falha(403, 'forbidden'), 'SEM_ACESSO'],
    [falha(500), 'ERRO'],
  ])('a leitura falha (%#): diz o motivo', async (erro, chave) => {
    api.anuncios.mockRejectedValue(erro);
    montar({ comPosts: false, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');

    const aviso = noBody('[data-criar-leitura-anuncios]');
    expect(aviso.getAttribute('role')).toBe('alert');
    expect(aviso.textContent).toContain(
      `AGENTS.AGENTE_DO_POST.CRIAR.ANUNCIOS.${chave}`
    );
  });

  it('voltar ao chip dos posts não lê de novo', async () => {
    montar({ comPosts: true, comAnuncios: true });

    await clicar('[data-criar-tipo="post"]');
    await clicar('[data-criar-fonte="anuncios"]');
    await clicar('[data-criar-fonte="posts"]');
    await clicar('[data-criar-fonte="anuncios"]');

    expect(seusPosts.get).toHaveBeenCalledTimes(1);
    expect(api.anuncios).toHaveBeenCalledTimes(1);
  });
});

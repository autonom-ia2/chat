import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import VideoDoTrajeto from '../components/VideoDoTrajeto.vue';

const tamanho = ref('grande');
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('../composables/useTamanhoDaLetra', () => ({
  useTamanhoDaLetra: () => ({ tamanho }),
}));

const VIDEO = {
  arquivo: '/central-de-ajuda/videos/02.04.mp4',
  legenda: '/central-de-ajuda/videos/02.04.vtt',
  poster: '/central-de-ajuda/videos/02.04.jpg',
};

describe('VideoDoTrajeto', () => {
  beforeEach(() => {
    tamanho.value = 'grande';
  });

  it('mostra o vídeo com controles, sem começar sozinho, com pôster e legenda', () => {
    const video = mount(VideoDoTrajeto, { props: { video: VIDEO } }).find(
      'video'
    );

    expect(video.attributes('src')).toBe(VIDEO.arquivo);
    expect(video.attributes('poster')).toBe(VIDEO.poster);
    expect(video.attributes('controls')).toBeDefined();
    expect(video.attributes('autoplay')).toBeUndefined();
    expect(video.find('track').attributes('src')).toBe(VIDEO.legenda);
  });

  it('acompanha o tamanho de letra escolhido na Central', () => {
    tamanho.value = 'maior';

    const video = mount(VideoDoTrajeto, { props: { video: VIDEO } }).find(
      'video'
    );

    expect(video.classes()).toContain('text-xl');
  });

  it('funciona sem legenda', () => {
    const video = mount(VideoDoTrajeto, {
      props: { video: { arquivo: VIDEO.arquivo } },
    }).find('video');

    expect(video.find('track').exists()).toBe(false);
  });
});

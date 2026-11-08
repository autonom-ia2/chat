import {
  alvoDoImpulsionar,
  erroDoPublicar,
  faltaNoPost,
  juntarPublicado,
  lugarDoPost,
  motivosDasRedes,
  redesQueDao,
} from '../criarPost';

const PERMITE = { facebook: true, instagram: true };
const INSTAGRAM = { id: '178', username: 'loja', publish_left: 97 };

describe('Anúncios da Meta · regras do criar post (#2653)', () => {
  it('lugarDoPost: two networks are AUTO, one is that network', () => {
    expect(lugarDoPost(['instagram', 'facebook'])).toBe('AUTO');
    expect(lugarDoPost(['facebook'])).toBe('FACEBOOK');
  });

  it('motivosDasRedes: permission first, then the account on the Page, then the daily limit', () => {
    expect(motivosDasRedes(PERMITE, INSTAGRAM)).toEqual({});
    expect(
      motivosDasRedes({ facebook: false, instagram: false }, INSTAGRAM)
    ).toEqual({
      facebook: 'NO_PERMISSION',
      instagram: 'NO_PERMISSION',
    });
    expect(motivosDasRedes(PERMITE, null)).toEqual({
      instagram: 'NO_INSTAGRAM',
    });
    expect(motivosDasRedes(PERMITE, { ...INSTAGRAM, publish_left: 0 })).toEqual(
      {
        instagram: 'LIMIT',
      }
    );
    // Meta did not say how many are left: Instagram stays available.
    expect(
      motivosDasRedes(PERMITE, { ...INSTAGRAM, publish_left: null })
    ).toEqual({});
  });

  it('redesQueDao: only the networks without a reason', () => {
    expect(redesQueDao({ instagram: 'LIMIT' })).toEqual(['facebook']);
  });

  it('faltaNoPost: Page, network, upload and media, in that order', () => {
    const post = {
      page_id: '1',
      networks: ['facebook'],
      uploading: false,
      media: { signed_id: 's' },
    };
    expect(faltaNoPost({ ...post, page_id: null }, {})).toBe('NEED_PAGE');
    expect(
      faltaNoPost({ ...post, networks: ['instagram'] }, { instagram: 'LIMIT' })
    ).toBe('NEED_NETWORK');
    expect(faltaNoPost({ ...post, uploading: true }, {})).toBe('UPLOADING');
    expect(faltaNoPost({ ...post, media: null }, {})).toBe('NEED_MEDIA');
    expect(faltaNoPost(post, {})).toBe('');
  });

  it('alvoDoImpulsionar: Instagram first; a Page video alone cannot be boosted', () => {
    const facebook = { id: '1_2', boostable: true };
    const instagram = { id: '1799', boostable: true };
    expect(alvoDoImpulsionar({ instagram, facebook })).toEqual({
      post_source: 'instagram',
      post_id: '1799',
    });
    expect(alvoDoImpulsionar({ facebook })).toEqual({
      post_source: 'facebook',
      post_id: '1_2',
    });
    expect(
      alvoDoImpulsionar({ facebook: { id: '555', boostable: false } })
    ).toBeNull();
  });

  it('juntarPublicado: keeps what was published before and takes the new failures', () => {
    const antes = {
      facebook: { id: 'f' },
      failed: ['instagram'],
      errors: { instagram: 'processing' },
    };
    expect(
      juntarPublicado(antes, { instagram: { id: 'i' }, failed: [], errors: {} })
    ).toEqual({
      facebook: { id: 'f' },
      instagram: { id: 'i' },
      failed: [],
      errors: {},
    });
  });

  it('erroDoPublicar: known refusals, conflict and no answer', () => {
    expect(
      erroDoPublicar({
        response: { status: 422, data: { error: 'processing' } },
      })
    ).toBe('PROCESSING');
    expect(
      erroDoPublicar({
        response: { status: 409, data: { error: 'in_progress' } },
      })
    ).toBe('IN_PROGRESS');
    expect(
      erroDoPublicar({
        response: { status: 422, data: { error: 'meta_refused' } },
      })
    ).toBe('UNKNOWN');
    expect(erroDoPublicar(new Error('offline'))).toBe('NETWORK');
  });
});

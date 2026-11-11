import {
  MAX_IMAGE_BYTES,
  TOO_LARGE,
  UNREADABLE,
  UNSUPPORTED,
  altFromFileName,
  isImageFile,
  planImage,
  prepareImageFile,
} from '../imageFile';

const MB = 1024 * 1024;
const fileOf = (name, type, size = 1000) => {
  const file = new File(['x'], name, { type });
  Object.defineProperty(file, 'size', { value: size });
  return file;
};
const bitmap = (width, height) => ({ width, height, close: vi.fn() });
const blobOf = size => {
  const blob = new Blob(['x']);
  Object.defineProperty(blob, 'size', { value: size });
  return blob;
};

describe('isImageFile', () => {
  it.each([
    ['foto.jpg', 'image/jpeg', true],
    ['foto.HEIC', '', true],
    ['scan.tiff', '', true],
    ['contrato.pdf', 'application/pdf', false],
    ['video.mp4', 'video/mp4', false],
    ['planilha.xlsx', '', false],
  ])('%s (%s) -> %s', (name, type, expected) => {
    expect(isImageFile(fileOf(name, type))).toBe(expected);
  });
});

describe('planImage', () => {
  it('keeps a small JPEG/PNG and any GIF up to the limit', () => {
    expect(
      planImage({ type: 'image/jpeg', width: 800, height: 600, size: MB })
    ).toEqual({ keep: true });
    expect(
      planImage({ type: 'image/gif', width: 4000, height: 10, size: MB })
    ).toEqual({ keep: true });
  });

  it('reduces a big phone photo to 1200 px wide JPEG', () => {
    expect(
      planImage({ type: 'image/jpeg', width: 4000, height: 3000, size: 8 * MB })
    ).toEqual({ keep: false, width: 1200, height: 900, type: 'image/jpeg' });
  });

  it('converts HEIC/WebP/BMP to JPEG and keeps PNG as PNG', () => {
    expect(
      planImage({ type: 'image/heic', width: 1000, height: 500, size: MB })
    ).toMatchObject({ keep: false, width: 1000, type: 'image/jpeg' });
    expect(
      planImage({ type: 'image/png', width: 2400, height: 400, size: MB })
    ).toMatchObject({
      keep: false,
      width: 1200,
      height: 200,
      type: 'image/png',
    });
  });
});

describe('prepareImageFile', () => {
  it('refuses what is not an image', async () => {
    await expect(
      prepareImageFile(fileOf('a.pdf', 'application/pdf'))
    ).rejects.toMatchObject({ code: UNSUPPORTED });
  });

  it('refuses a photo the browser cannot open, in plain words', async () => {
    const decode = vi
      .fn()
      .mockRejectedValue(Object.assign(new Error('x'), { code: UNREADABLE }));

    await expect(
      prepareImageFile(fileOf('a.heic', 'image/heic'), { decode })
    ).rejects.toMatchObject({ code: UNREADABLE });
  });

  it('sends a small JPEG as it is', async () => {
    const file = fileOf('a.jpg', 'image/jpeg');
    const draw = vi.fn();

    expect(
      await prepareImageFile(file, {
        decode: async () => bitmap(600, 400),
        draw,
      })
    ).toBe(file);
    expect(draw).not.toHaveBeenCalled();
  });

  it('redraws a big photo as a 1200 px JPEG named after the original', async () => {
    const draw = vi.fn().mockResolvedValue(blobOf(300 * 1024));

    const out = await prepareImageFile(
      fileOf('IMG_0001.HEIC', 'image/heic', 9 * MB),
      { decode: async () => bitmap(4032, 3024), draw }
    );

    expect(draw).toHaveBeenCalledWith(expect.anything(), {
      keep: false,
      width: 1200,
      height: 900,
      type: 'image/jpeg',
    });
    expect(out.name).toBe('IMG_0001.jpg');
    expect(out.type).toBe('image/jpeg');
  });

  it('refuses an image still above 10 MB after reducing it', async () => {
    await expect(
      prepareImageFile(fileOf('a.png', 'image/png', 30 * MB), {
        decode: async () => bitmap(1000, 1000),
        draw: async () => blobOf(MAX_IMAGE_BYTES + 1),
      })
    ).rejects.toMatchObject({ code: TOO_LARGE });
    await expect(
      prepareImageFile(fileOf('a.gif', 'image/gif', 11 * MB))
    ).rejects.toMatchObject({ code: TOO_LARGE });
  });
});

describe('altFromFileName', () => {
  it('uses the name without extension', () => {
    expect(altFromFileName('Fachada da loja.jpg')).toBe('Fachada da loja');
    expect(altFromFileName('.png')).toBe('.png');
    expect(altFromFileName('')).toBe('Imagem');
  });
});

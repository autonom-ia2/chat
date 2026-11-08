import {
  LIMITE_DO_PRIVADO_EM_BYTES,
  bytesDoTexto,
  privadoLongoDemais,
} from '../privadoDoInstagram';

// #2543: o privado do Instagram é medido em bytes UTF-8, como a Meta mede.
describe('privadoDoInstagram', () => {
  it('limite de 1000 bytes', () => {
    expect(LIMITE_DO_PRIVADO_EM_BYTES).toBe(1000);
  });

  it('conta acento como 2 bytes e emoji como 4', () => {
    expect(bytesDoTexto('a')).toBe(1);
    expect(bytesDoTexto('ã')).toBe(2);
    expect(bytesDoTexto('🙂')).toBe(4);
    expect(bytesDoTexto()).toBe(0);
  });

  it('1000 bytes passa; 1001 não', () => {
    expect(privadoLongoDemais('a'.repeat(1000))).toBe(false);
    expect(privadoLongoDemais('a'.repeat(1001))).toBe(true);
    expect(privadoLongoDemais('🙂'.repeat(250))).toBe(false);
    expect(privadoLongoDemais(`${'🙂'.repeat(250)}a`)).toBe(true);
  });

  it('texto com acento abaixo de 1000 letras pode passar do limite', () => {
    const texto = 'ã'.repeat(501);

    expect(texto.length).toBeLessThan(1000);
    expect(privadoLongoDemais(texto)).toBe(true);
  });
});

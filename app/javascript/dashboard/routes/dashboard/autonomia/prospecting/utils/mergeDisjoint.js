// Junta objetos que não podem dividir chave. Com spread, duas frentes que
// escolhem o mesmo nome (country, mode, reset...) se sobrescrevem em silêncio;
// aqui a montagem quebra na hora e diz qual chave repetiu.
const hasOwn = (object, key) =>
  Object.prototype.hasOwnProperty.call(object, key);

export const mergeDisjoint = (...parts) =>
  parts.reduce((merged, part) => {
    const repeated = Object.keys(part).find(key => hasOwn(merged, key));
    if (repeated) {
      throw new Error(`mergeDisjoint: chave repetida "${repeated}"`);
    }
    return { ...merged, ...part };
  }, {});

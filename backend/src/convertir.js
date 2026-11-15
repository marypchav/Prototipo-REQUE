/*
Funciones de apoyo para los controladores.
Lo que llega del navegador siempre es texto: aquí se convierte al tipo que
espera el SP. Si el valor no sirve se manda NULL y el SP responde con su
código de error, así las reglas viven en un solo lugar: la base de datos.
*/

// "3" -> 3, "1.5" -> null, "" -> null
function aEntero(valor) {
  if (valor === null || valor === undefined || valor === '') {
    return null;
  }
  const numero = Number(valor);
  return Number.isInteger(numero) ? numero : null;
}

// "12500.50" -> 12500.5, "abc" -> null, "" -> null
function aNumero(valor) {
  if (valor === null || valor === undefined || valor === '') {
    return null;
  }
  const numero = Number(valor);
  return Number.isFinite(numero) ? numero : null;
}

// cualquier valor -> texto; null y undefined quedan en null
function aTexto(valor) {
  if (valor === null || valor === undefined) {
    return null;
  }
  return String(valor);
}

// "2,3" de la URL -> '[2,3]' para el SP; vacío -> null (sin filtro).
// un valor que no sea número queda null y el SP responde 50010
function idsDeConsulta(valor) {
  if (valor === undefined || valor === null || String(valor).trim() === '') {
    return null;
  }
  const ids = String(valor)
    .split(',')
    .map((parte) => aEntero(parte.trim()));
  return JSON.stringify(ids);
}

// une la lista de tallas a cada producto por IdProducto
function agruparTallas(productos, tallas) {
  return productos.map((producto) => ({
    ...producto,
    tallas: tallas.filter((talla) => talla.IdProducto === producto.IdProducto),
  }));
}

// "async" en Express 4: si la función falla, el error llega al manejador
function envolver(funcion) {
  return (req, res, next) => Promise.resolve(funcion(req, res, next)).catch(next);
}

module.exports = { aEntero, aNumero, aTexto, idsDeConsulta, agruparTallas, envolver };

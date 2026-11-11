/*
Funciones de apoyo para los controladores.
Lo que llega del navegador siempre es texto: aquí se convierte al tipo que
espera el SP
*/

function aEntero(valor) {
  if (valor === null || valor === undefined || valor === '') {
    return null;
  }
  const numero = Number(valor);
  return Number.isInteger(numero) ? numero : null;
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

module.exports = { aEntero, agruparTallas, envolver };

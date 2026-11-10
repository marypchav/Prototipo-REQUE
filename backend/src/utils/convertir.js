/*
Convierte lo que llega del navegador (siempre texto o JSON) al tipo que
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

// "12500.50" -> 12500.5, "abc" -> null
function aNumero(valor) {
  if (valor === null || valor === undefined || valor === '') {
    return null;
  }
  const numero = Number(valor);
  return Number.isFinite(numero) ? numero : null;
}

function aTexto(valor) {
  if (valor === null || valor === undefined) {
    return null;
  }
  return String(valor);
}

// "2026-11-09" -> fecha para un parámetro DATE; cualquier otra cosa -> null
function aFecha(valor) {
  if (typeof valor !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(valor)) {
    return null;
  }
  // medianoche en hora local (la conexión usa useUTC: false)
  const [anio, mes, dia] = valor.split('-').map(Number);
  const fecha = new Date(anio, mes - 1, dia);
  return fecha.getMonth() === mes - 1 ? fecha : null; // descarta "2026-02-31"
}

// une la lista de tallas a cada producto por IdProducto
function agruparTallas(productos, tallas) {
  return productos.map((producto) => ({
    ...producto,
    tallas: tallas.filter((talla) => talla.IdProducto === producto.IdProducto),
  }));
}

// IP del cliente para la bitácora, sin el prefijo de IPv6 "::ffff:"
function ipDe(req) {
  return String(req.ip || '').replace('::ffff:', '').slice(0, 64);
}

// "async" en Express 4: si la función falla, el error llega al manejador
function envolver(funcion) {
  return (req, res, next) => Promise.resolve(funcion(req, res, next)).catch(next);
}

module.exports = { aEntero, aNumero, aTexto, aFecha, agruparTallas, ipDe, envolver };
/*
CU2: carrito de compras (GP007 a GP010) y cálculo del costo (GP020).
*/
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const { aEntero } = require('../utils/convertir');

const CANTIDAD_QUITAR = 0;

// GET /api/carrito?metodoEntrega=1  (GP008, GP020)
// metodoEntrega es opcional: con él el total incluye el envío
async function obtener(req, res) {
  const [lineas, [resumen]] = await ejecutarSP('spListarCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdMetodoEntrega: [sql.Int, aEntero(req.query.metodoEntrega)],
  });

  res.json({ ok: true, datos: { lineas, resumen } });
}

// POST /api/carrito  (GP007)
// cuerpo: { idProductoTalla, cantidad }
async function agregar(req, res) {
  const [[fila]] = await ejecutarSP('spAgregarCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdProductoTalla: [sql.Int, aEntero(req.body?.idProductoTalla)],
    inCantidad: [sql.Int, aEntero(req.body?.cantidad)],
  });

  res.status(201).json({
    ok: true,
    mensaje: 'El producto fue agregado al carrito.',
    datos: { cantidadArticulos: fila.CantidadArticulos }, // indicador del carrito
  });
}

async function cambiarCantidad(req, res, cantidad, mensaje) {
  const [[fila]] = await ejecutarSP('spActualizarCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdCarritoDetalle: [sql.Int, aEntero(req.params.id)],
    inCantidad: [sql.Int, cantidad],
  });

  res.json({ ok: true, mensaje, datos: { cantidadArticulos: fila.CantidadArticulos } });
}

// PUT /api/carrito/:id  (GP009)  cuerpo: { cantidad }
async function actualizar(req, res) {
  await cambiarCantidad(req, res, aEntero(req.body?.cantidad), 'El carrito fue actualizado.');
}

// DELETE /api/carrito/:id  (GP009: quitar un producto)
async function quitar(req, res) {
  await cambiarCantidad(req, res, CANTIDAD_QUITAR, 'El producto fue quitado del carrito.');
}

// DELETE /api/carrito  (GP010)
async function vaciar(req, res) {
  await ejecutarSP('spVaciarCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, mensaje: 'Su carrito fue vaciado.', datos: { cantidadArticulos: 0 } });
}

module.exports = { obtener, agregar, actualizar, quitar, vaciar };

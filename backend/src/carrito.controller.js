/*
Módulo Gestión de pedidos: carrito del cliente.
    GP007 Agregar productos al carrito     GP009 Modificar carrito
    GP008 Visualizar carrito               GP010 Eliminar carrito
    GP020 Calcular costo del pedido (lo hace spListarCarrito)
Todas pasan antes por requiereCliente (ver rutas.js).
El carrito NO toca el inventario: eso pasa al confirmar la orden (GP014).
*/
const { ejecutarSP, sql } = require('./ejecutarSP');
const ErrorApp = require('./ErrorApp');
const { aEntero } = require('./convertir');

const SUPERA_EXISTENCIAS = 50048;

// "Solo hay 2 disponibles y ya tiene 1 en su carrito." con los datos del SP
function mensajeExistencias(datos) {
  const fila = datos?.[0];
  if (!fila || fila.Existencias === undefined) {
    return null; // se usa el mensaje general de codigosError.js
  }
  const hay = fila.Existencias === 1 ? 'Solo hay 1 disponible' : `Solo hay ${fila.Existencias} disponibles`;
  const yaTiene = fila.EnCarrito > 0 ? ` y ya tiene ${fila.EnCarrito} en su carrito` : '';
  return `${hay}${yaTiene}.`;
}

// cambia el mensaje de 50048 por uno con las cantidades; los demás errores siguen igual
async function conMensajeDeExistencias(promesa) {
  try {
    return await promesa;
  } catch (error) {
    if (error instanceof ErrorApp && error.codigo === SUPERA_EXISTENCIAS) {
      throw new ErrorApp(error.codigo, error.datos, mensajeExistencias(error.datos));
    }
    throw error;
  }
}

// líneas y desglose de costos (GP008, GP020). idMetodoEntrega es opcional:
// con él se suma el envío o se marca "Envío a coordinar con la administradora"
async function leerCarrito(idUsuario, idMetodoEntrega) {
  const [lineas, [resumen]] = await ejecutarSP('spListarCarrito', {
    inIdUsuario: [sql.Int, idUsuario],
    inIdMetodoEntrega: [sql.Int, aEntero(idMetodoEntrega)],
  });
  return { lineas, resumen };
}

// GET /api/cliente/carrito?metodoEntrega=1   (GP008, GP020)
// lineas vacío = "Su carrito está vacío" (GP008 flujo alterno 1)
// Disponible = false: se marca "No disponible" y no suma al total (flujo alterno 2)
async function ver(req, res) {
  const datos = await leerCarrito(req.usuario.idUsuario, req.query.metodoEntrega);

  res.json({ ok: true, datos });
}

// POST /api/cliente/carrito   (GP007)
// cuerpo: { idProductoTalla, cantidad }
// idProductoTalla viene en las tallas de GET /api/productos/:id
async function agregar(req, res) {
  const { idProductoTalla, cantidad } = req.body ?? {};

  const [[fila]] = await conMensajeDeExistencias(
    ejecutarSP('spAgregarAlCarrito', {
      inIdUsuario: [sql.Int, req.usuario.idUsuario],
      inIdProductoTalla: [sql.Int, aEntero(idProductoTalla)],
      inCantidad: [sql.Int, aEntero(cantidad)], // "1.5" o "abc" -> null -> 50046
    })
  );

  // GP007 paso 2.3: mensaje y el número para el indicador del carrito
  res.status(201).json({
    ok: true,
    mensaje: 'El producto fue agregado al carrito.',
    datos: { cantidadArticulos: fila.CantidadArticulos },
  });
}

// PUT /api/cliente/carrito/:idDetalle?metodoEntrega=1   (GP009)
// cuerpo: { cantidad }. Responde el carrito ya recalculado (GP009 restricción 2)
async function modificar(req, res) {
  await conMensajeDeExistencias(
    ejecutarSP('spModificarCarrito', {
      inIdUsuario: [sql.Int, req.usuario.idUsuario],
      inIdCarritoDetalle: [sql.Int, aEntero(req.params.idDetalle)],
      inCantidad: [sql.Int, aEntero(req.body?.cantidad)],
    })
  );

  const datos = await leerCarrito(req.usuario.idUsuario, req.query.metodoEntrega);
  res.json({ ok: true, mensaje: 'El carrito fue actualizado.', datos });
}

// DELETE /api/cliente/carrito/:idDetalle?metodoEntrega=1   (GP009: quitar un producto)
async function quitar(req, res) {
  await ejecutarSP('spQuitarDelCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdCarritoDetalle: [sql.Int, aEntero(req.params.idDetalle)],
  });

  const datos = await leerCarrito(req.usuario.idUsuario, req.query.metodoEntrega);
  res.json({ ok: true, mensaje: 'El producto fue quitado del carrito.', datos });
}

// DELETE /api/cliente/carrito   (GP010)
// la pregunta "¿Confirma que desea vaciar su carrito?" la hace el frontend
async function vaciar(req, res) {
  await ejecutarSP('spVaciarCarrito', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, mensaje: 'Su carrito fue vaciado.' });
}

module.exports = { ver, agregar, modificar, quitar, vaciar, leerCarrito };

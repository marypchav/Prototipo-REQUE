/*
CU1 Gestión de inventario: GI002 a GI008, y CP008 (detalle público).
Después de cada cambio se avisa a los navegadores (CP010).
*/
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const ErrorApp = require('../utils/ErrorApp');
const { aEntero, aNumero, aTexto, agruparTallas, ipDe } = require('../utils/convertir');
const { rutaRelativa, borrarArchivo } = require('../middlewares/subirImagen');
const { avisarCatalogo } = require('../servicios/tiempoReal');

// [{ idTalla: 2, cantidad: 1 }] -> '[{"IdTalla":2,"Cantidad":1}]' (formato del SP)
function tallasAJson(tallas) {
  if (!Array.isArray(tallas)) {
    return null; // el SP responde 50010
  }
  return JSON.stringify(
    tallas.map((talla) => ({
      IdTalla: aEntero(talla?.idTalla),
      Cantidad: aEntero(talla?.cantidad),
    }))
  );
}

// GET /api/admin/productos?texto=blusa&categoria=1&talla=3  (GI004, GI008)
async function listarAdmin(req, res) {
  const [productos, tallas] = await ejecutarSP('spListarProductoAdmin', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inTextoBusqueda: [sql.NVarChar(100), aTexto(req.query.texto)],
    inIdCategoria: [sql.Int, aEntero(req.query.categoria)],
    inIdTalla: [sql.Int, aEntero(req.query.talla)],
  });

  res.json({ ok: true, datos: agruparTallas(productos, tallas) });
}

// GET /api/productos/:id  (CP008, y carga del formulario de GI005)
async function obtener(req, res) {
  const [[producto], tallas] = await ejecutarSP('spObtenerProducto', {
    inIdProducto: [sql.Int, aEntero(req.params.id)],
  });

  res.json({ ok: true, datos: { ...producto, tallas } });
}

// POST /api/admin/productos  (GI002)
// cuerpo: { idCategoria, nombre, descripcion, precio, tallas: [{ idTalla, cantidad }] }
async function agregar(req, res) {
  const { idCategoria, nombre, descripcion, precio, tallas } = req.body ?? {};

  const [[fila]] = await ejecutarSP('spAgregarProducto', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdCategoria: [sql.Int, aEntero(idCategoria)],
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inDescripcion: [sql.NVarChar(500), aTexto(descripcion)],
    inPrecio: [sql.Money, aNumero(precio)],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasAJson(tallas)],
  });

  avisarCatalogo(fila.IdProducto);
  res.status(201).json({
    ok: true,
    mensaje: 'El producto fue agregado.',
    datos: { idProducto: fila.IdProducto }, // con este id se sube la foto (GI003)
  });
}

// PUT /api/admin/productos/:id  (GI005)
// cuerpo: { idCategoria, nombre, descripcion, precio }
async function actualizar(req, res) {
  const { idCategoria, nombre, descripcion, precio } = req.body ?? {};
  const idProducto = aEntero(req.params.id);

  await ejecutarSP('spActualizarProducto', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdProducto: [sql.Int, idProducto],
    inIdCategoria: [sql.Int, aEntero(idCategoria)],
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inDescripcion: [sql.NVarChar(500), aTexto(descripcion)],
    inPrecio: [sql.Money, aNumero(precio)],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'El producto fue actualizado con éxito.' });
}

// DELETE /api/admin/productos/:id  (GI006)
async function eliminar(req, res) {
  const idProducto = aEntero(req.params.id);

  await ejecutarSP('spEliminarProducto', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdProducto: [sql.Int, idProducto],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'El producto fue eliminado.' });
}

// PUT /api/admin/productos/:id/tallas/:idTalla  (GI007)
// cuerpo: { cantidad }
async function actualizarDisponibilidad(req, res) {
  const idProducto = aEntero(req.params.id);

  await ejecutarSP('spActualizarDisponibilidad', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdProducto: [sql.Int, idProducto],
    inIdTalla: [sql.Int, aEntero(req.params.idTalla)],
    inCantidad: [sql.Int, aEntero(req.body?.cantidad)],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'La disponibilidad fue actualizada.' });
}

// POST /api/admin/productos/:id/foto  (GI003)
// formulario multipart con el campo "foto"
async function subirFoto(req, res) {
  if (!req.file) {
    throw new ErrorApp(50003, null, 'Seleccione una imagen.');
  }

  const idProducto = aEntero(req.params.id);
  const ruta = rutaRelativa(req.file);

  // si el SP falla, el manejador de errores borra la imagen recién subida
  const [[fila]] = await ejecutarSP('spActualizarImagenProducto', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdProducto: [sql.Int, idProducto],
    inRutaImagen: [sql.VarChar(260), ruta],
  });

  // la foto anterior ya no se usa
  if (fila.RutaAnterior && fila.RutaAnterior !== ruta) {
    await borrarArchivo(fila.RutaAnterior);
  }

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'La foto fue guardada.', datos: { rutaImagen: ruta } });
}

module.exports = {
  listarAdmin,
  obtener,
  agregar,
  actualizar,
  eliminar,
  actualizarDisponibilidad,
  subirFoto,
};

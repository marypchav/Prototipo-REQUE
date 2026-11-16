/*
Módulo Gestión de pedidos: direcciones de envío del cliente.
    GP003 Visualizar   GP004 Agregar   GP005 Modificar   GP006 Eliminar
Todas pasan antes por requiereCliente (ver rutas.js). El id del cliente sale
SIEMPRE de la sesión, nunca del navegador: así nadie ve ni cambia las
direcciones de otro (GP003 restricción 1, GP005 restricción 2).
*/
const { ejecutarSP, sql } = require('./ejecutarSP');
const { aEntero, aTexto } = require('./convertir');

function parametrosDireccion(cuerpo) {
  const { idProvincia, canton, distrito, otrasSenas } = cuerpo ?? {};
  return {
    inIdProvincia: [sql.Int, aEntero(idProvincia)],
    inCanton: [sql.NVarChar(64), aTexto(canton)],
    inDistrito: [sql.NVarChar(64), aTexto(distrito)],
    inOtrasSenas: [sql.NVarChar(256), aTexto(otrasSenas)],
  };
}

// GET /api/cliente/direcciones   (GP003)
// también trae las provincias para el formulario de GP004 y GP005
async function listar(req, res) {
  const [direcciones, provincias] = await ejecutarSP('spListarDirecciones', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, datos: { direcciones, provincias } });
}

// POST /api/cliente/direcciones   (GP004)
// cuerpo: { idProvincia, canton, distrito, otrasSenas }
async function agregar(req, res) {
  const [[fila]] = await ejecutarSP('spAgregarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    ...parametrosDireccion(req.body),
  });

  res.status(201).json({
    ok: true,
    mensaje: 'La dirección fue agregada.',
    datos: { idDireccion: fila.IdDireccion },
  });
}

// PUT /api/cliente/direcciones/:id   (GP005)   mismo cuerpo que al agregar
async function modificar(req, res) {
  await ejecutarSP('spModificarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdDireccion: [sql.Int, aEntero(req.params.id)],
    ...parametrosDireccion(req.body),
  });

  res.json({ ok: true, mensaje: 'La dirección fue actualizada.' });
}

// DELETE /api/cliente/direcciones/:id   (GP006)
// la pregunta "¿Confirma que desea eliminar esta dirección?" la hace el frontend
async function eliminar(req, res) {
  await ejecutarSP('spEliminarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdDireccion: [sql.Int, aEntero(req.params.id)],
  });

  res.json({ ok: true, mensaje: 'La dirección fue eliminada.' });
}

module.exports = { listar, agregar, modificar, eliminar };
